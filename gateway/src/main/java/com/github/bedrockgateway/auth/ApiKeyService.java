package com.github.bedrockgateway.auth;

import com.github.bedrockgateway.config.GatewayProperties;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class ApiKeyService {

    private final Map<String, GatewayProperties.ApiKeyConfig> keyMap = new ConcurrentHashMap<>();

    public ApiKeyService(GatewayProperties props) {
        for (var keyConfig : props.getApiKeys()) {
            keyMap.put(keyConfig.getKey(), keyConfig);
        }
    }

    public Optional<GatewayProperties.ApiKeyConfig> validate(String apiKey) {
        return Optional.ofNullable(keyMap.get(apiKey));
    }
}
