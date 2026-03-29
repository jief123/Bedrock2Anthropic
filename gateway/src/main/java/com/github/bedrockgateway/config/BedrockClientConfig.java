package com.github.bedrockgateway.config;

import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeAsyncClient;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.auth.StsAssumeRoleCredentialsProvider;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;

import java.util.HashMap;
import java.util.Map;

@Configuration
public class BedrockClientConfig {

    private static final Logger log = LoggerFactory.getLogger(BedrockClientConfig.class);
    private final Map<String, BedrockRuntimeAsyncClient> clients = new HashMap<>();

    @Bean
    public Map<String, BedrockRuntimeAsyncClient> bedrockClients(GatewayProperties props) {
        for (var entry : props.getAccounts().entrySet()) {
            String accountId = entry.getKey();
            GatewayProperties.AccountConfig config = entry.getValue();

            AwsCredentialsProvider credentialsProvider;
            if (config.getRoleArn() != null && !config.getRoleArn().isBlank()) {
                StsClient stsClient = StsClient.builder()
                        .region(Region.of(config.getRegion()))
                        .build();
                credentialsProvider = StsAssumeRoleCredentialsProvider.builder()
                        .stsClient(stsClient)
                        .refreshRequest(AssumeRoleRequest.builder()
                                .roleArn(config.getRoleArn())
                                .roleSessionName("bedrock-gateway-" + accountId)
                                .build())
                        .build();
            } else {
                credentialsProvider = DefaultCredentialsProvider.create();
            }

            BedrockRuntimeAsyncClient client = BedrockRuntimeAsyncClient.builder()
                    .region(Region.of(config.getRegion()))
                    .credentialsProvider(credentialsProvider)
                    .build();

            clients.put(accountId, client);
            log.info("Initialized Bedrock client for account '{}' in region '{}'", accountId, config.getRegion());
        }
        return clients;
    }

    @PreDestroy
    public void shutdown() {
        clients.values().forEach(BedrockRuntimeAsyncClient::close);
    }
}
