# Bedrock Gateway

A lightweight API gateway that exposes the standard **Anthropic Messages API** (`POST /v1/messages`) and translates requests to **AWS Bedrock InvokeModel** under the hood.

Drop-in replacement for `api.anthropic.com` — point your Anthropic SDK, Claude Code, or any compatible client at this gateway, and it routes through your AWS account.

## Why

- **Unified billing** — all AI usage goes through your AWS account
- **IAM control** — fine-grained permissions on who can call which model
- **Multi-account routing** — distribute requests across multiple AWS accounts
- **API key management** — issue gateway keys to teams, with per-key rate limits
- **Token metering** — track input/output tokens per key, per model, per account
- **Data compliance** — requests stay within your AWS network

## What It Does

```
Anthropic SDK / Claude Code / curl
        │
        ▼
   Bedrock Gateway (this project)
   ├── Authenticate (gateway API key)
   ├── Rate limit (per-key)
   ├── Transform request (Anthropic format → Bedrock format)
   ├── Route to AWS account
   ├── Call Bedrock InvokeModel / InvokeModelWithResponseStream
   ├── Transform response (EventStream → SSE for streaming)
   ├── Record token usage
   └── Return Anthropic-compatible response
        │
        ▼
   Your application
```

## Quick Start

### Prerequisites

- Java 21+
- Maven 3.9+
- AWS credentials configured (`~/.aws/credentials`, env vars, or IAM role)
- Bedrock model access enabled in your AWS account

### Build & Run

```bash
cd gateway
mvn package -DskipTests
java -jar target/bedrock-gateway-0.1.0-SNAPSHOT.jar
```

Gateway starts on `http://localhost:8080`.

### Test

```bash
curl -X POST http://localhost:8080/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: gw-test-key-001" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Use with Claude Code

```bash
export ANTHROPIC_BASE_URL=http://localhost:8080
export ANTHROPIC_API_KEY=gw-test-key-001
claude
```

### Use with Anthropic Python SDK

```python
import anthropic

client = anthropic.Anthropic(
    api_key="gw-test-key-001",
    base_url="http://localhost:8080",
)

message = client.messages.create(
    model="claude-sonnet-4-5-20250929",
    max_tokens=100,
    messages=[{"role": "user", "content": "Hello!"}],
)
```

## Configuration

All configuration is in `gateway/src/main/resources/application.yml`:

```yaml
gateway:
  # API keys for clients
  api-keys:
    - key: "gw-test-key-001"
      name: "Default Test Key"
      rate-limit-per-minute: 60
      route: "default"

  # AWS accounts
  accounts:
    default:
      region: "us-east-1"
      # For cross-account access:
      # role-arn: "arn:aws:iam::123456789:role/bedrock-access"

  # Anthropic model name → Bedrock model ID
  model-mapping:
    claude-sonnet-4-5-20250929: "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    claude-sonnet-4-6: "global.anthropic.claude-sonnet-4-6"
    claude-opus-4-6: "global.anthropic.claude-opus-4-6-v1"
    # ... see application.yml for full list

  # Bedrock-supported beta flags (whitelist)
  supported-beta-flags:
    - "interleaved-thinking-2025-05-14"
    - "context-1m-2025-08-07"
    - "context-management-2025-06-27"
    # ... see application.yml for full list
```

## Request Translation

The gateway handles all the differences between Anthropic API and Bedrock API:

| What | Anthropic | Bedrock | Gateway handles |
|------|-----------|---------|-----------------|
| Auth | `x-api-key` header | AWS SigV4 | ✅ |
| Model | `model` in body | `modelId` in URL path | ✅ |
| Version | `anthropic-version` header | `anthropic_version` in body | ✅ |
| Beta flags | `anthropic-beta` header | `anthropic_beta` array in body (whitelist filtered) | ✅ |
| Streaming | `stream: true` in body | Different API endpoint | ✅ |
| Unsupported fields | `metadata`, `service_tier`, etc. | N/A | ✅ Stripped |
| Server tools | `web_search`, `code_execution` | Not supported | ✅ Filtered |
| Streaming protocol | SSE | EventStream | ✅ Converted |

## Tech Stack

- Java 21 + Spring Boot 3.x + WebFlux
- AWS SDK for Java v2 (BedrockRuntimeAsyncClient)
- H2 (embedded, for token metering)

## Documentation

- [Architecture](docs/architecture.md) — design decisions, data flow, multi-account routing
- [Bedrock Claude API Handbook](docs/bedrock-claude-api-handbook.md) — comprehensive guide for developers new to Bedrock
- [Interactive Guide](docs/site/index.html) — single-page HTML reference (open in browser)
- [Reference Docs](reference-docs/) — Bedrock Claude API reference material

## License

MIT
