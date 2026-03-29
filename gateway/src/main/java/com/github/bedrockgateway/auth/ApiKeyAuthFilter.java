package com.github.bedrockgateway.auth;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.bedrockgateway.config.GatewayProperties;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

import java.util.Map;

@Component
@Order(1)
public class ApiKeyAuthFilter implements WebFilter {

    private final ApiKeyService apiKeyService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public ApiKeyAuthFilter(ApiKeyService apiKeyService) {
        this.apiKeyService = apiKeyService;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String path = exchange.getRequest().getPath().value();
        if (!path.startsWith("/v1/")) {
            return chain.filter(exchange);
        }

        String apiKey = exchange.getRequest().getHeaders().getFirst("x-api-key");
        if (apiKey == null || apiKey.isBlank()) {
            return writeError(exchange, HttpStatus.UNAUTHORIZED, "authentication_error", "Missing x-api-key header");
        }

        var keyConfig = apiKeyService.validate(apiKey);
        if (keyConfig.isEmpty()) {
            return writeError(exchange, HttpStatus.FORBIDDEN, "permission_error", "Invalid API key");
        }

        // Store key config in exchange attributes for downstream use
        exchange.getAttributes().put("apiKeyConfig", keyConfig.get());
        return chain.filter(exchange);
    }

    private Mono<Void> writeError(ServerWebExchange exchange, HttpStatus status, String type, String message) {
        exchange.getResponse().setStatusCode(status);
        exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
        try {
            byte[] body = objectMapper.writeValueAsBytes(Map.of(
                    "type", "error",
                    "error", Map.of("type", type, "message", message)
            ));
            DataBuffer buffer = exchange.getResponse().bufferFactory().wrap(body);
            return exchange.getResponse().writeWith(Mono.just(buffer));
        } catch (Exception e) {
            return exchange.getResponse().setComplete();
        }
    }
}
