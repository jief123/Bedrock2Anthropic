package com.github.bedrockgateway.ratelimit;

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
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

@Component
@Order(2)
public class RateLimitFilter implements WebFilter {

    private final ObjectMapper objectMapper = new ObjectMapper();
    // Simple sliding window: key -> (count, windowStart)
    private final Map<String, RateWindow> windows = new ConcurrentHashMap<>();

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        var keyConfig = (GatewayProperties.ApiKeyConfig) exchange.getAttributes().get("apiKeyConfig");
        if (keyConfig == null) {
            return chain.filter(exchange);
        }

        int limit = keyConfig.getRateLimitPerMinute();
        if (limit <= 0) {
            return chain.filter(exchange);
        }

        RateWindow window = windows.computeIfAbsent(keyConfig.getKey(), k -> new RateWindow());
        long now = System.currentTimeMillis();

        synchronized (window) {
            if (now - window.windowStart > 60_000) {
                window.windowStart = now;
                window.count.set(0);
            }
            if (window.count.incrementAndGet() > limit) {
                exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
                exchange.getResponse().getHeaders().add("retry-after", "60");
                try {
                    byte[] body = objectMapper.writeValueAsBytes(Map.of(
                            "type", "error",
                            "error", Map.of("type", "rate_limit_error", "message", "Rate limit exceeded: " + limit + " requests per minute")
                    ));
                    DataBuffer buffer = exchange.getResponse().bufferFactory().wrap(body);
                    return exchange.getResponse().writeWith(Mono.just(buffer));
                } catch (Exception e) {
                    return exchange.getResponse().setComplete();
                }
            }
        }

        return chain.filter(exchange);
    }

    private static class RateWindow {
        volatile long windowStart = System.currentTimeMillis();
        final AtomicLong count = new AtomicLong(0);
    }
}
