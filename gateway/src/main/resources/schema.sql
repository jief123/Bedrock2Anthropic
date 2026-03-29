CREATE TABLE IF NOT EXISTS usage_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    api_key VARCHAR(128) NOT NULL,
    api_key_name VARCHAR(256),
    account_id VARCHAR(64),
    region VARCHAR(32),
    model VARCHAR(128),
    bedrock_model_id VARCHAR(256),
    input_tokens INT DEFAULT 0,
    output_tokens INT DEFAULT 0,
    cache_creation_input_tokens INT DEFAULT 0,
    cache_read_input_tokens INT DEFAULT 0,
    streaming BOOLEAN DEFAULT FALSE,
    status VARCHAR(16),
    error_message VARCHAR(1024),
    duration_ms BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_usage_api_key ON usage_records(api_key);
CREATE INDEX IF NOT EXISTS idx_usage_created_at ON usage_records(created_at);
CREATE INDEX IF NOT EXISTS idx_usage_account ON usage_records(account_id);
