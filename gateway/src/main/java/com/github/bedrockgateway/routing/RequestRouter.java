package com.github.bedrockgateway.routing;

import java.util.Map;
import java.util.Optional;

import org.springframework.stereotype.Service;

import com.github.bedrockgateway.config.GatewayProperties;

import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeAsyncClient;

@Service
public class RequestRouter {

    private final Map<String, BedrockRuntimeAsyncClient> clients;
    private final GatewayProperties props;

    public RequestRouter(Map<String, BedrockRuntimeAsyncClient> clients, GatewayProperties props) {
        this.clients = clients;
        this.props = props;
    }

    public Optional<RouteDecision> route(GatewayProperties.ApiKeyConfig keyConfig, String anthropicModel) {
        String accountId = keyConfig.getRoute();
        BedrockRuntimeAsyncClient client = clients.get(accountId);
        if (client == null) {
            return Optional.empty();
        }

        String bedrockModelId = resolveModelId(anthropicModel);
        var accountConfig = props.getAccounts().get(accountId);
        String region = accountConfig != null ? accountConfig.getRegion() : "us-east-1";

        return Optional.of(new RouteDecision(accountId, region, bedrockModelId, client));
    }

    private String resolveModelId(String anthropicModel) {
        // Direct mapping lookup
        String mapped = props.getModelMapping().get(anthropicModel);
        if (mapped != null) {
            return mapped;
        }
        // If already looks like a Bedrock model ID, pass through
        if (anthropicModel.startsWith("anthropic.") || anthropicModel.startsWith("us.anthropic.")
                || anthropicModel.startsWith("global.anthropic.")
                || anthropicModel.contains(":")) {
            return anthropicModel;
        }
        // Default: use cross-region inference profile
        return "us.anthropic." + anthropicModel + "-v1:0";
    }
}
