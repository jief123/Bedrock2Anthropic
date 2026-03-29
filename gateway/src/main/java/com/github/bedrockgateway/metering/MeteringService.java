package com.github.bedrockgateway.metering;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

@Service
public class MeteringService {

    private static final Logger log = LoggerFactory.getLogger(MeteringService.class);
    private final JdbcTemplate jdbc;

    public MeteringService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void record(UsageRecord record) {
        try {
            jdbc.update(
                    "INSERT INTO usage_records (api_key, api_key_name, account_id, region, model, bedrock_model_id, " +
                            "input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens, " +
                            "streaming, status, error_message, duration_ms) " +
                            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    record.apiKey(), record.apiKeyName(), record.accountId(), record.region(),
                    record.model(), record.bedrockModelId(),
                    record.inputTokens(), record.outputTokens(),
                    record.cacheCreationInputTokens(), record.cacheReadInputTokens(),
                    record.streaming(), record.status(), record.errorMessage(), record.durationMs()
            );
        } catch (Exception e) {
            log.error("Failed to record usage: {}", e.getMessage());
        }
    }
}
