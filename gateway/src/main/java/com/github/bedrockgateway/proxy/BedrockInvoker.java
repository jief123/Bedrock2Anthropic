package com.github.bedrockgateway.proxy;

import java.util.concurrent.CompletableFuture;

import org.springframework.stereotype.Service;

import com.github.bedrockgateway.routing.RouteDecision;

import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

@Service
public class BedrockInvoker {

    public CompletableFuture<InvokeModelResponse> invoke(RouteDecision route, byte[] body) {
        InvokeModelRequest request = InvokeModelRequest.builder()
                .modelId(route.bedrockModelId())
                .contentType("application/json")
                .accept("application/json")
                .body(SdkBytes.fromByteArray(body))
                .build();

        return route.client().invokeModel(request);
    }
}
