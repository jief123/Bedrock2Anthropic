package com.github.bedrockgateway.controller;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ServerWebExchange;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.bedrockgateway.config.GatewayProperties;
import com.github.bedrockgateway.metering.MeteringService;
import com.github.bedrockgateway.metering.UsageRecord;
import com.github.bedrockgateway.proxy.BedrockInvoker;
import com.github.bedrockgateway.proxy.BedrockStreamInvoker;
import com.github.bedrockgateway.routing.RequestRouter;
import com.github.bedrockgateway.routing.RouteDecision;
import com.github.bedrockgateway.transform.RequestTransformer;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/v1")
public class MessagesController {

    private static final Logger log = LoggerFactory.getLogger(MessagesController.class);
    private static final ObjectMapper mapper = new ObjectMapper();

    private final RequestTransformer transformer;
    private final RequestRouter router;
    private final BedrockInvoker invoker;
    private final BedrockStreamInvoker streamInvoker;
    private final MeteringService metering;
    private final GatewayProperties props;

    public MessagesController(RequestTransformer transformer, RequestRouter router,
                              BedrockInvoker invoker, BedrockStreamInvoker streamInvoker,
                              MeteringService metering, GatewayProperties props) {
        this.transformer = transformer;
        this.router = router;
        this.invoker = invoker;
        this.streamInvoker = streamInvoker;
        this.metering = metering;
        this.props = props;
    }

    @PostMapping(value = "/messages", consumes = MediaType.APPLICATION_JSON_VALUE)
    public Mono<ResponseEntity<?>> messages(@RequestBody byte[] body, ServerWebExchange exchange) {
        long startTime = System.currentTimeMillis();
        var keyConfig = (GatewayProperties.ApiKeyConfig) exchange.getAttributes().get("apiKeyConfig");
        HttpHeaders headers = exchange.getRequest().getHeaders();

        try {
            var result = transformer.transform(body, headers);

            if (result.model() == null || result.model().isBlank()) {
                return Mono.just(errorResponse(400, "invalid_request_error", "Missing required field: model"));
            }

            var routeOpt = router.route(keyConfig, result.model());
            if (routeOpt.isEmpty()) {
                return Mono.just(errorResponse(404, "not_found_error",
                        "No route found for account '" + keyConfig.getRoute() + "'"));
            }
            RouteDecision route = routeOpt.get();

            if (result.streaming()) {
                return handleStreaming(result, route, keyConfig, startTime, exchange);
            } else {
                return handleNonStreaming(result, route, keyConfig, startTime);
            }
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
            return Mono.just(errorResponse(400, "invalid_request_error", "Invalid JSON: " + e.getOriginalMessage()));
        } catch (Exception e) {
            log.error("Request processing error: {}", e.getMessage(), e);
            return Mono.just(errorResponse(500, "api_error", e.getMessage()));
        }
    }

    @SuppressWarnings("unchecked")
    private Mono<ResponseEntity<?>> handleNonStreaming(
            RequestTransformer.TransformResult result, RouteDecision route,
            GatewayProperties.ApiKeyConfig keyConfig, long startTime) {

        return Mono.fromFuture(invoker.invoke(route, result.body()))
                .<ResponseEntity<?>>map(response -> {
                    byte[] responseBody = response.body().asByteArray();
                    recordUsage(responseBody, result.model(), route, keyConfig, false, startTime, "success", null);
                    return ResponseEntity.ok()
                            .contentType(MediaType.APPLICATION_JSON)
                            .body(responseBody);
                })
                .onErrorResume(e -> {
                    log.error("Bedrock invocation error: {}", e.getMessage());
                    recordUsage(null, result.model(), route, keyConfig, false, startTime, "error", e.getMessage());
                    return Mono.just(mapBedrockError(e));
                });
    }

    private Mono<ResponseEntity<?>> handleStreaming(
            RequestTransformer.TransformResult result, RouteDecision route,
            GatewayProperties.ApiKeyConfig keyConfig, long startTime, ServerWebExchange exchange) {

        // Accumulate usage from multiple SSE events
        StreamUsageAccumulator usage = new StreamUsageAccumulator();

        var response = exchange.getResponse();
        response.setStatusCode(org.springframework.http.HttpStatus.OK);
        response.getHeaders().setContentType(MediaType.TEXT_EVENT_STREAM);
        response.getHeaders().set("Cache-Control", "no-cache");
        response.getHeaders().set("Connection", "keep-alive");

        var bufferFactory = response.bufferFactory();

        Flux<org.springframework.core.io.buffer.DataBuffer> dataFlux = streamInvoker.invokeStream(route, result.body())
                .doOnNext(sseEvent -> usage.accumulate(sseEvent))
                .map(sseEvent -> bufferFactory.wrap(sseEvent.getBytes(java.nio.charset.StandardCharsets.UTF_8)))
                .doOnComplete(() -> {
                    recordStreamUsage(usage, result.model(), route, keyConfig, startTime);
                })
                .doOnError(e -> {
                    log.error("Stream error: {}", e.getMessage());
                    recordUsage(null, result.model(), route, keyConfig, true, startTime, "error", e.getMessage());
                });

        return response.writeAndFlushWith(dataFlux.map(Flux::just))
                .then(Mono.empty());
    }

    private void recordUsage(byte[] responseBody, String model, RouteDecision route,
                             GatewayProperties.ApiKeyConfig keyConfig, boolean streaming,
                             long startTime, String status, String errorMessage) {
        if (!props.getLogging().isLogUsage()) return;

        var builder = UsageRecord.builder()
                .apiKey(keyConfig.getKey())
                .apiKeyName(keyConfig.getName())
                .accountId(route.accountId())
                .region(route.region())
                .model(model)
                .bedrockModelId(route.bedrockModelId())
                .streaming(streaming)
                .status(status)
                .errorMessage(errorMessage)
                .durationMs(System.currentTimeMillis() - startTime);

        if (responseBody != null) {
            try {
                JsonNode root = mapper.readTree(responseBody);
                JsonNode usage = root.get("usage");
                if (usage != null) {
                    builder.inputTokens(usage.path("input_tokens").asInt(0));
                    builder.outputTokens(usage.path("output_tokens").asInt(0));
                    builder.cacheCreationInputTokens(usage.path("cache_creation_input_tokens").asInt(0));
                    builder.cacheReadInputTokens(usage.path("cache_read_input_tokens").asInt(0));
                }
            } catch (Exception e) {
                log.warn("Failed to parse usage from response: {}", e.getMessage());
            }
        }
        metering.record(builder.build());
    }

    private void recordStreamUsage(StreamUsageAccumulator usage, String model, RouteDecision route,
                                   GatewayProperties.ApiKeyConfig keyConfig, long startTime) {
        if (!props.getLogging().isLogUsage()) return;

        metering.record(UsageRecord.builder()
                .apiKey(keyConfig.getKey())
                .apiKeyName(keyConfig.getName())
                .accountId(route.accountId())
                .region(route.region())
                .model(model)
                .bedrockModelId(route.bedrockModelId())
                .streaming(true)
                .status("success")
                .inputTokens(usage.inputTokens)
                .outputTokens(usage.outputTokens)
                .cacheCreationInputTokens(usage.cacheCreationInputTokens)
                .cacheReadInputTokens(usage.cacheReadInputTokens)
                .durationMs(System.currentTimeMillis() - startTime)
                .build());
    }

    /**
     * Accumulates usage data from streaming SSE events.
     * message_start carries input_tokens; message_delta carries output_tokens.
     */
    private static class StreamUsageAccumulator {
        int inputTokens;
        int outputTokens;
        int cacheCreationInputTokens;
        int cacheReadInputTokens;

        void accumulate(String sseEvent) {
            try {
                int dataIdx = sseEvent.indexOf("data: ");
                if (dataIdx < 0) return;
                String json = sseEvent.substring(dataIdx + 6).trim();
                JsonNode node = mapper.readTree(json);
                String type = node.path("type").asText("");

                if ("message_start".equals(type)) {
                    JsonNode usage = node.path("message").path("usage");
                    inputTokens = usage.path("input_tokens").asInt(0);
                    cacheCreationInputTokens = usage.path("cache_creation_input_tokens").asInt(0);
                    cacheReadInputTokens = usage.path("cache_read_input_tokens").asInt(0);
                } else if ("message_delta".equals(type)) {
                    JsonNode usage = node.path("usage");
                    if (!usage.isMissingNode()) {
                        outputTokens = usage.path("output_tokens").asInt(0);
                    }
                }
            } catch (Exception e) {
                // ignore parse errors during streaming
            }
        }
    }

    /**
     * Maps Bedrock SDK exceptions to Anthropic-compatible error responses,
     * preserving HTTP status codes.
     */
    private ResponseEntity<byte[]> mapBedrockError(Throwable e) {
        Throwable cause = e;
        // Unwrap CompletionException
        if (cause.getCause() != null && cause instanceof java.util.concurrent.CompletionException) {
            cause = cause.getCause();
        }

        int status = 500;
        String errorType = "api_error";
        String message = cause.getMessage() != null ? cause.getMessage() : "Unknown error";

        if (cause instanceof software.amazon.awssdk.services.bedrockruntime.model.ValidationException) {
            status = 400;
            errorType = "invalid_request_error";
        } else if (cause instanceof software.amazon.awssdk.services.bedrockruntime.model.ThrottlingException) {
            status = 429;
            errorType = "rate_limit_error";
        } else if (cause instanceof software.amazon.awssdk.services.bedrockruntime.model.AccessDeniedException) {
            status = 403;
            errorType = "permission_error";
        } else if (cause instanceof software.amazon.awssdk.services.bedrockruntime.model.ResourceNotFoundException) {
            status = 404;
            errorType = "not_found_error";
        } else if (cause instanceof software.amazon.awssdk.services.bedrockruntime.model.ModelTimeoutException) {
            status = 408;
            errorType = "api_error";
            message = "Request timed out";
        } else if (cause instanceof software.amazon.awssdk.services.bedrockruntime.model.ServiceUnavailableException) {
            status = 529;
            errorType = "overloaded_error";
        } else if (cause instanceof software.amazon.awssdk.services.bedrockruntime.model.ModelErrorException) {
            status = 500;
            errorType = "api_error";
        }

        // Try to extract cleaner message from Bedrock error
        String cleanMsg = extractBedrockErrorMessage(message);
        return errorResponse(status, errorType, cleanMsg);
    }

    private String extractBedrockErrorMessage(String msg) {
        if (msg != null && msg.contains("(Service:")) {
            // Strip SDK metadata suffix: "(Service: BedrockRuntime, Status Code: 400, ...)"
            int idx = msg.indexOf(" (Service:");
            if (idx > 0) return msg.substring(0, idx);
        }
        return msg != null ? msg : "Unknown error";
    }

    private ResponseEntity<byte[]> errorResponse(int status, String type, String message) {
        try {
            byte[] body = mapper.writeValueAsBytes(Map.of(
                    "type", "error",
                    "error", Map.of("type", type, "message", message)
            ));
            return ResponseEntity.status(status)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body);
        } catch (Exception e) {
            return ResponseEntity.status(500).build();
        }
    }
}
