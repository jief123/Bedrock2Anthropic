package com.github.bedrockgateway.proxy;

import java.util.concurrent.CompletableFuture;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.github.bedrockgateway.routing.RouteDecision;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelWithResponseStreamRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelWithResponseStreamResponseHandler;

/**
 * Handles streaming invocation: Bedrock EventStream → SSE events.
 * Each EventStream chunk payload is a JSON object with a "type" field
 * that maps directly to Anthropic SSE event types.
 */
@Service
public class BedrockStreamInvoker {

    private static final Logger log = LoggerFactory.getLogger(BedrockStreamInvoker.class);
    private static final ObjectMapper mapper = new ObjectMapper();

    /**
     * Returns a Flux of SSE-formatted strings: "event: {type}\ndata: {json}\n\n"
     */
    public Flux<String> invokeStream(RouteDecision route, byte[] body) {
        Sinks.Many<String> sink = Sinks.many().unicast().onBackpressureBuffer();

        InvokeModelWithResponseStreamRequest request = InvokeModelWithResponseStreamRequest.builder()
                .modelId(route.bedrockModelId())
                .contentType("application/json")
                .body(SdkBytes.fromByteArray(body))
                .build();

        InvokeModelWithResponseStreamResponseHandler handler = InvokeModelWithResponseStreamResponseHandler.builder()
                .onEventStream(stream -> {
                    stream.subscribe(event -> {
                        event.accept(InvokeModelWithResponseStreamResponseHandler.Visitor.builder()
                                .onChunk(chunk -> {
                                    try {
                                        String json = chunk.bytes().asUtf8String();
                                        JsonNode node = mapper.readTree(json);
                                        String eventType = node.has("type") ? node.get("type").asText() : "unknown";

                                        // R3: Strip amazon-bedrock-invocationMetrics from message_stop
                                        if (node.isObject() && node.has("amazon-bedrock-invocationMetrics")) {
                                            ((ObjectNode) node).remove("amazon-bedrock-invocationMetrics");
                                            json = mapper.writeValueAsString(node);
                                        }

                                        String sseEvent = "event: " + eventType + "\ndata: " + json + "\n\n";
                                        sink.tryEmitNext(sseEvent);
                                    } catch (Exception e) {
                                        // E23: Notify client about chunk parse failure instead of silent discard
                                        log.error("Error processing stream chunk: {}", e.getMessage());
                                        try {
                                            String errorJson = mapper.writeValueAsString(java.util.Map.of(
                                                    "type", "error",
                                                    "error", java.util.Map.of(
                                                            "type", "api_error",
                                                            "message", "Stream chunk processing error: " + e.getMessage()
                                                    )
                                            ));
                                            sink.tryEmitNext("event: error\ndata: " + errorJson + "\n\n");
                                        } catch (Exception ignored) {
                                            // last resort — nothing we can do
                                        }
                                    }
                                })
                                .onDefault(e -> {
                                    // Ignore other event types
                                })
                                .build());
                    });
                })
                .onComplete(() -> {
                    sink.tryEmitComplete();
                })
                .onError(error -> {
                    log.error("Stream error: {}", error.getMessage());
                    // Emit an error event in SSE format
                    try {
                        String errorJson = mapper.writeValueAsString(java.util.Map.of(
                                "type", "error",
                                "error", java.util.Map.of("type", "api_error", "message", error.getMessage())
                        ));
                        sink.tryEmitNext("event: error\ndata: " + errorJson + "\n\n");
                    } catch (Exception e) {
                        // ignore
                    }
                    sink.tryEmitComplete();
                })
                .build();

        // E18: Track the future so we can cancel on client disconnect
        CompletableFuture<Void> bedrockFuture = route.client()
                .invokeModelWithResponseStream(request, handler);

        // E18: Cancel Bedrock call when client disconnects (subscriber cancels)
        return sink.asFlux()
                .doOnCancel(() -> {
                    log.info("Client disconnected, cancelling Bedrock stream");
                    bedrockFuture.cancel(true);
                    sink.tryEmitComplete();
                });
    }
}
