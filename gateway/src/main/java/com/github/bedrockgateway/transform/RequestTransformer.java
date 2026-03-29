package com.github.bedrockgateway.transform;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.github.bedrockgateway.config.GatewayProperties;

@Service
public class RequestTransformer {

    private static final Logger log = LoggerFactory.getLogger(RequestTransformer.class);
    private static final ObjectMapper mapper = new ObjectMapper();

    // Fields that Bedrock does not support and must be stripped
    private static final List<String> UNSUPPORTED_FIELDS = List.of(
            "model", "stream", "metadata", "service_tier", "inference_geo", "container", "mcp_servers",
            "cache_control" // D12: Bedrock does not support top-level cache_control
    );

    // Anthropic server tool types that Bedrock does not support
    private static final List<String> SERVER_TOOL_TYPES = List.of(
            "web_search_20250305", "web_fetch_20250305", "code_execution_20250522",
            "mcp", "text_editor_20250124", "bash_20250124", "computer_20250124"
    );

    // Default beta flags if not configured in YAML
    private static final List<String> DEFAULT_SUPPORTED_BETA_FLAGS = List.of(
            "computer-use-2025-01-24",
            "computer-use-2024-10-22",
            "token-efficient-tools-2025-02-19",
            "interleaved-thinking-2025-05-14",
            "output-128k-2025-02-19",
            "dev-full-thinking-2025-05-14",
            "context-1m-2025-08-07",
            "context-management-2025-06-27",
            "effort-2025-11-24",
            "tool-search-tool-2025-10-19",
            "tool-examples-2025-10-29",
            "fine-grained-tool-streaming-2025-05-14"
    );

    private final Set<String> supportedBetaFlags;

    public RequestTransformer(GatewayProperties props) {
        List<String> configured = props.getSupportedBetaFlags();
        if (configured != null && !configured.isEmpty()) {
            this.supportedBetaFlags = new HashSet<>(configured);
            log.info("Using configured beta flags whitelist: {}", this.supportedBetaFlags);
        } else {
            this.supportedBetaFlags = new HashSet<>(DEFAULT_SUPPORTED_BETA_FLAGS);
            log.info("Using default beta flags whitelist ({} flags)", this.supportedBetaFlags.size());
        }
    }

    /**
     * Transform Anthropic Messages API request body to Bedrock InvokeModel body.
     * Returns the transformed JSON bytes and the extracted model name.
     */
    public TransformResult transform(byte[] requestBody, HttpHeaders headers) throws Exception {
        ObjectNode root = (ObjectNode) mapper.readTree(requestBody);

        // Extract model before removing
        String model = root.has("model") ? root.get("model").asText() : null;
        boolean streaming = root.has("stream") && root.get("stream").asBoolean(false);

        log.trace(">>> Incoming request: model={}, stream={}", model, streaming);
        log.trace(">>> anthropic-version header: {}", headers.getFirst("anthropic-version"));
        log.trace(">>> anthropic-beta header: {}", headers.getOrEmpty("anthropic-beta"));
        if (root.has("anthropic_beta")) {
            log.trace(">>> anthropic_beta in body: {}", root.get("anthropic_beta"));
        }

        // Remove unsupported fields
        for (String field : UNSUPPORTED_FIELDS) {
            root.remove(field);
        }

        // D24: Always set anthropic_version — Bedrock only accepts "bedrock-2023-05-31"
        root.put("anthropic_version", "bedrock-2023-05-31");

        // D20: Filter out server tools from tools array
        if (root.has("tools") && root.get("tools").isArray()) {
            ArrayNode tools = (ArrayNode) root.get("tools");
            ArrayNode filtered = mapper.createArrayNode();
            for (JsonNode tool : tools) {
                String type = tool.has("type") ? tool.get("type").asText() : "custom";
                if (!SERVER_TOOL_TYPES.contains(type)) {
                    filtered.add(tool);
                }
            }
            if (filtered.size() != tools.size()) {
                if (filtered.isEmpty()) {
                    root.remove("tools");
                    root.remove("tool_choice"); // no tools left, remove tool_choice too
                } else {
                    root.set("tools", filtered);
                }
            }
        }

        // Convert anthropic-beta header to anthropic_beta array in body, filtering unsupported flags
        List<String> betaHeaders = headers.getOrEmpty("anthropic-beta");
        if (!betaHeaders.isEmpty() && !root.has("anthropic_beta")) {
            ArrayNode betaArray = mapper.createArrayNode();
            for (String header : betaHeaders) {
                for (String beta : header.split(",")) {
                    String trimmed = beta.trim();
                    if (supportedBetaFlags.contains(trimmed)) {
                        betaArray.add(trimmed);
                    } else {
                        log.trace("Filtered unsupported beta flag: {}", trimmed);
                    }
                }
            }
            if (!betaArray.isEmpty()) {
                root.set("anthropic_beta", betaArray);
            }
        }
        // Also filter anthropic_beta if it was already in the body
        if (root.has("anthropic_beta") && root.get("anthropic_beta").isArray()) {
            ArrayNode existing = (ArrayNode) root.get("anthropic_beta");
            ArrayNode filtered = mapper.createArrayNode();
            for (JsonNode flag : existing) {
                if (supportedBetaFlags.contains(flag.asText())) {
                    filtered.add(flag);
                } else {
                    log.trace("Filtered unsupported beta flag from body: {}", flag.asText());
                }
            }
            if (filtered.isEmpty()) {
                root.remove("anthropic_beta");
            } else {
                root.set("anthropic_beta", filtered);
            }
        }

        byte[] transformedBody = mapper.writeValueAsBytes(root);
        log.trace("<<< Transformed body: {}", new String(transformedBody, java.nio.charset.StandardCharsets.UTF_8));
        return new TransformResult(transformedBody, model, streaming);
    }

    public record TransformResult(byte[] body, String model, boolean streaming) {}
}
