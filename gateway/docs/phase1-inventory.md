# Phase 1: Protocol Translation Inventory

Source Protocol: Anthropic Messages API (`POST /v1/messages`)
Target Protocol: AWS Bedrock InvokeModel / InvokeModelWithResponseStream

> **Updated**: 2026-03-28 — 基于 V2 独立测试结果更新，所有标注 "V2 证实" 的条目均通过实际 Bedrock API 调用验证。

---

## 1.1 Control Mode Inventory

| Mode ID | Source Trigger | Target Behavior | Bidirectional | Notes |
|---------|---------------|-----------------|---------------|-------|
| M1 | `stream: false` or absent | `InvokeModel` (sync JSON→JSON) | Yes | Basic request-response |
| M2 | `stream: true` | `InvokeModelWithResponseStream` (EventStream→SSE) | Yes | Protocol conversion: AWS EventStream binary → HTTP SSE text |
| M3 | API Key auth (`x-api-key` header) | AWS SigV4 (SDK handles) | No | Auth translation, one-way |
| M4 | Multi-account routing | Select BedrockRuntimeAsyncClient from pool | No | Control plane, no protocol equivalent |
| M5 | Rate limiting | Pre-flight check, no target call | No | Gateway-only, blocks before translation |
| M6 | Model name resolution | Bedrock modelId mapping | No | 查表 + 回退模式 (`us.anthropic.{model}-v1:0`) |

---

## 1.2 Data Mapping Inventory

### Request Mappings

| Map ID | Source Field | Target Field | Transform | Default | Lossy | V2 Status |
|--------|-------------|-------------|-----------|---------|-------|-----------|
| D1 | `model` (body) | `modelId` (SDK param) | Lookup table mapping | Fallback: `us.anthropic.{model}-v1:0` | No | ✅ Verified |
| D2 | `stream` (body) | (controls which API to call) | Removed from body | `false` | No | ✅ Verified |
| D3 | `anthropic-version` (header) | `anthropic_version` (body) | Header→body, **always overwrite** to `bedrock-2023-05-31` | `"bedrock-2023-05-31"` | **Yes** — original version value replaced | ✅ V2 证实: 客户端传入 `2023-06-01` 会导致 Bedrock 400 |
| D4 | `anthropic-beta` (header) | `anthropic_beta` (body array) | Header→body, comma-split to array | — | No | ✅ Verified |
| D5 | `x-api-key` (header) | (not forwarded) | Consumed by gateway | — | Yes (by design) | ✅ |
| D6 | `metadata` (body) | (dropped) | Stripped | — | **Yes** | ✅ |
| D7 | `service_tier` (body) | (dropped) | Stripped | — | **Yes** | ✅ |
| D8 | `inference_geo` (body) | (dropped) | Stripped | — | **Yes** | ✅ |
| D9 | `container` (body) | (dropped) | Stripped | — | **Yes** | ✅ |
| D10 | `mcp_servers` (body) | (dropped) | Stripped | — | **Yes** | ✅ |
| D11 | `max_tokens` (body) | `max_tokens` (body) | Pass-through | — | No | ✅ |
| D12 | `messages` (body) | `messages` (body) | Pass-through | — | No | ✅ |
| D13 | `system` (body) | `system` (body) | Pass-through | — | No | ✅ |
| D14 | `temperature` (body) | `temperature` (body) | Pass-through | — | No | ✅ |
| D15 | `top_p` (body) | `top_p` (body) | Pass-through | — | No | ✅ |
| D16 | `top_k` (body) | `top_k` (body) | Pass-through | — | No | ✅ |
| D17 | `stop_sequences` (body) | `stop_sequences` (body) | Pass-through | — | No | ✅ |
| D18 | `tools` (body) | `tools` (body) | **Filtered** — server tools removed, client tools pass-through | — | **Yes** — server tools silently dropped | ✅ V2 证实: server tools 被 Bedrock 静默忽略 |
| D19 | `tool_choice` (body) | `tool_choice` (body) | Pass-through (removed if all tools filtered) | — | No | ✅ |
| D20 | `thinking` (body) | `thinking` (body) | Pass-through | — | No | ✅ Verified (enabled + adaptive) |
| D21 | (none) | `anthropic_version` (body) | **Always set** to `"bedrock-2023-05-31"` | `"bedrock-2023-05-31"` | No | ✅ V2 证实 |
| D22 | `cache_control` (top-level body) | (dropped) | **Stripped** | — | **Yes** | ✅ V2 证实: Bedrock 不支持 top-level cache_control，透传导致 400 |
| D23 | `output_config` (body) | `output_config` (body, effort stripped) | **effort 字段剥离**, format 保留 | — | **Partial** — effort 被丢弃 | ✅ V2 证实: effort 导致 Bedrock 400 |

### Response Mappings

| Map ID | Source (Bedrock) | Target (Anthropic) | Transform | Lossy | V2 Status |
|--------|-----------------|-------------------|-----------|-------|-----------|
| R1 | Response body JSON | Response body JSON | **Pass-through** (no transform) | No | ✅ Verified |
| R2 | EventStream chunks | SSE `event: {type}\ndata: {json}\n\n` | Protocol wrapping only | No | ✅ Verified |
| R3 | `amazon-bedrock-invocationMetrics` (in message_stop) | Passed through | Not stripped | **Extra field** — Anthropic API doesn't have this | ✅ V2 证实存在 |

---

## 1.3 Error & Edge Path Inventory

| Error ID | Source Condition | Target Response | Handling | V2 Status |
|----------|----------------|-----------------|----------|-----------|
| E1 | Missing `x-api-key` header | 401 `authentication_error` | Mapped | ✅ Verified |
| E2 | Invalid API key | 403 `permission_error` | Mapped | ✅ Verified |
| E3 | Rate limit exceeded | 429 `rate_limit_error` | Mapped | ✅ |
| E4 | No route for account | 404 `not_found_error` | Mapped | ✅ |
| E5 | Bedrock `ValidationException` (400) | 400 `invalid_request_error` | ✅ Mapped | ✅ Verified |
| E6 | Bedrock `ThrottlingException` (429) | 429 `rate_limit_error` | ✅ Mapped | ✅ Code review |
| E7 | Bedrock `AccessDeniedException` (403) | 403 `permission_error` | ✅ Mapped | ✅ Code review |
| E8 | Bedrock `ModelTimeoutException` | 408 `api_error` | ✅ Mapped | ✅ Code review |
| E9 | Bedrock `ServiceUnavailableException` | 529 `overloaded_error` | ✅ Mapped | ✅ Code review |
| E10 | Bedrock `ModelErrorException` | 500 `api_error` | ✅ Mapped | ✅ Code review |
| E11 | Malformed JSON request body | 400 `invalid_request_error` | ✅ Mapped | ✅ Verified |
| E12 | Missing `model` field in request | 400 `invalid_request_error` | ✅ Mapped | ✅ Verified |
| E13 | Missing `max_tokens` field | Bedrock returns 400 → E5 | ✅ Indirect | ✅ Verified |
| E14 | Stream error mid-way | SSE error event | ✅ Mapped | ✅ Code review |
| E15 | `model` not in mapping and not a valid Bedrock ID | Bedrock returns 400 → E5 | ✅ Indirect | ✅ Verified |
| E16 | Request body too large | Spring default limit | **UNMAPPED** | ⚠️ 未测试 |
| E17 | Bedrock `ModelStreamErrorException` | SSE error event | ✅ Mapped | ✅ Code review |
| E18 | Stream chunk JSON parse failure | Logged, chunk silently dropped | **⚠️ 部分 Mapped** — 客户端不知情 | 🔍 Code review 确认风险 |
| E19 | Client disconnect during stream | Sink may leak, Bedrock call not cancelled | **⚠️ UNMAPPED** — 资源泄漏风险 | 🔍 Code review 确认风险 |
| E20 | Bedrock error message contains SDK metadata | Cleaned: `(Service: ...)` suffix stripped | ✅ Mapped | ✅ Verified |
| E21 | CompletionException wrapping | Auto-unwrap cause | ✅ Mapped | ✅ Code review |

---

## 1.4 Risk Assessment

> Updated 2026-03-28: 基于 V2 测试结果重新评估。之前的 P0 错误映射问题 (E5/E6/E7) 已修复并验证。

| Item | Type | Impact | Likelihood | Risk | Priority | V2 Status |
|------|------|--------|------------|------|----------|-----------|
| M2 | Mode | High | High | **Critical** | P0 | ✅ V2 测试通过 (流式 happy path + thinking + tool_use) |
| E19 | Error | Medium | High | **High** | P1 | 🔍 代码审查确认 — 客户端断开时资源泄漏 |
| E18 | Error | High | Medium | **High** | P1 | 🔍 代码审查确认 — 流式 chunk 静默丢弃 |
| D22 | Data | Medium | Medium | **Medium** | P1 | ✅ V2 证实并修复 — top-level cache_control 已剥离 |
| D3/D21 | Data | Medium | Medium | **Medium** | P1 | ✅ V2 证实并修复 — anthropic_version 始终覆盖 |
| D23 | Data | Medium | Medium | **Medium** | P1 | ✅ V2 证实并修复 — output_config.effort 已剥离 |
| D18 | Data | Low | Medium | **Medium** | P1 | ✅ V2 证实并修复 — server tools 已过滤 |
| R3 | Data | Low | High | **Low** | P2 | ✅ V2 证实存在 — Bedrock metrics 未剥离 |
| D6-D10 | Data | Low | Low | **Low** | P2 | ✅ 有意丢弃的字段 |
| D11-D17,D20 | Data | Low | Low | **Low** | P2 | ✅ 透传字段，V2 测试通过 |

### V2 测试已修复的问题

| 问题 | 原始状态 | 修复 | V2 验证 |
|------|---------|------|---------|
| E5: Bedrock 400 → 500 | 所有 Bedrock 错误返回 500 | `mapBedrockError()` 正确映射状态码 | ✅ 400 → 400 |
| E6: Bedrock 429 → 500 | 丢失限流语义 | 映射为 429 `rate_limit_error` | ✅ Code review |
| E7: Bedrock 403 → 500 | 丢失权限语义 | 映射为 403 `permission_error` | ✅ Code review |
| E10: 畸形 JSON → 500 | Jackson 异常未处理 | 捕获 `JsonProcessingException` → 400 | ✅ Verified |
| E11: 缺少 model → NPE | 路由器空指针 | 空值检查 → 400 | ✅ Verified |
| D22: top-level cache_control 透传 | Bedrock 400 | 加入 UNSUPPORTED_FIELDS 剥离 | ✅ V2 Bedrock 400 证实 |
| D3/D21: anthropic_version 不覆盖 | Bedrock 400 | 始终覆盖为 `bedrock-2023-05-31` | ✅ V2 Bedrock 400 证实 |
| D23: output_config.effort 透传 | Bedrock 400 | 剥离 effort 字段 | ✅ V2 Bedrock 400 证实 |
| D18: server tools 透传 | Bedrock 静默忽略 | 过滤 server tool types | ✅ V2 证实 |
