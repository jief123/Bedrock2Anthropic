package com.github.bedrockgateway.routing;

import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeAsyncClient;

public record RouteDecision(
        String accountId,
        String region,
        String bedrockModelId,
        BedrockRuntimeAsyncClient client
) {}
