package com.github.bedrockgateway.metering;

public record UsageRecord(
        String apiKey,
        String apiKeyName,
        String accountId,
        String region,
        String model,
        String bedrockModelId,
        int inputTokens,
        int outputTokens,
        int cacheCreationInputTokens,
        int cacheReadInputTokens,
        boolean streaming,
        String status,
        String errorMessage,
        long durationMs
) {
    public static Builder builder() { return new Builder(); }

    public static class Builder {
        private String apiKey, apiKeyName, accountId, region, model, bedrockModelId;
        private int inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens;
        private boolean streaming;
        private String status = "success", errorMessage;
        private long durationMs;

        public Builder apiKey(String v) { this.apiKey = v; return this; }
        public Builder apiKeyName(String v) { this.apiKeyName = v; return this; }
        public Builder accountId(String v) { this.accountId = v; return this; }
        public Builder region(String v) { this.region = v; return this; }
        public Builder model(String v) { this.model = v; return this; }
        public Builder bedrockModelId(String v) { this.bedrockModelId = v; return this; }
        public Builder inputTokens(int v) { this.inputTokens = v; return this; }
        public Builder outputTokens(int v) { this.outputTokens = v; return this; }
        public Builder cacheCreationInputTokens(int v) { this.cacheCreationInputTokens = v; return this; }
        public Builder cacheReadInputTokens(int v) { this.cacheReadInputTokens = v; return this; }
        public Builder streaming(boolean v) { this.streaming = v; return this; }
        public Builder status(String v) { this.status = v; return this; }
        public Builder errorMessage(String v) { this.errorMessage = v; return this; }
        public Builder durationMs(long v) { this.durationMs = v; return this; }

        public UsageRecord build() {
            return new UsageRecord(apiKey, apiKeyName, accountId, region, model, bedrockModelId,
                    inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens,
                    streaming, status, errorMessage, durationMs);
        }
    }
}
