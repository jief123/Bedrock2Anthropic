# 通过 Bedrock 调用 Claude：从零开始的实战手册

> 基于 Bedrock Gateway 项目的实战经验编写。所有标注"实测"的结论均通过真实 Bedrock API 调用验证。

---

## 一句话理解关系

Anthropic 做模型，自己卖 API，也把模型放到 AWS Bedrock 上卖。两套 API 调的是同一个模型，但接口协议不同。

```
Anthropic API  ──→  Anthropic 基础设施  ──→  Claude
Bedrock API    ──→  AWS 基础设施        ──→  Claude (同一个模型)
```

## 为什么要关心这个区别

- 你的公司可能要求所有 AI 调用走 AWS（合规、计费、IAM 权限管控）
- 你可能已经有 Anthropic SDK 写的代码，想迁移到 Bedrock
- 你可能要做一个 proxy，让 Anthropic SDK 的客户端透明地走 Bedrock

不管哪种场景，你需要知道两套 API 哪里一样、哪里不一样。

---

## 第一件事：两套 API 的调用方式

### Anthropic API

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: sk-ant-xxx" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### Bedrock API (用 AWS SDK，不能直接 curl)

```python
import boto3, json

client = boto3.client("bedrock-runtime", region_name="us-east-1")

response = client.invoke_model(
    modelId="anthropic.claude-sonnet-4-5-20250929-v1:0",
    contentType="application/json",
    body=json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": "Hello"}]
    })
)

result = json.loads(response["body"].read())
```

看出区别了吗？下面逐个拆解。

---

## 核心差异：6 个你必须知道的点

### 1. 认证方式完全不同

| | Anthropic | Bedrock |
|---|---|---|
| 认证 | `x-api-key` HTTP header | AWS SigV4 (IAM) |
| 密钥 | Anthropic Console 生成的 API key | AWS credentials (AK/SK, IAM Role, SSO) |
| 权限控制 | Anthropic workspace 级别 | IAM Policy，可以精确到模型级别 |

Bedrock 的认证由 AWS SDK 自动处理，你不需要手动签名。

### 2. 模型指定方式不同

Anthropic 在 request body 里指定模型：
```json
{ "model": "claude-sonnet-4-5-20250929", ... }
```

Bedrock 在 SDK 调用参数里指定，不在 body 里：
```python
client.invoke_model(modelId="anthropic.claude-sonnet-4-5-20250929-v1:0", body=...)
```

模型名也不一样。Bedrock 有三种 model ID 格式：

| 格式 | 示例 | 用途 |
|------|------|------|
| `anthropic.{model}` | `anthropic.claude-sonnet-4-5-20250929-v1:0` | 单 region，请求只在你指定的 region 处理 |
| `us.anthropic.{model}` | `us.anthropic.claude-3-7-sonnet-20250219-v1:0` | US cross-region inference profile，自动路由到 US 内最优 region |
| `global.anthropic.{model}` | `global.anthropic.claude-sonnet-4-5-20250929-v1:0` | Global cross-region inference profile，自动路由到全球最优 region |

推荐用 `global.` 前缀，延迟最低、可用性最高。不是所有模型都有 global profile，没有的用 `us.`。

完整映射表：

| Anthropic 模型名 | Bedrock Model ID (推荐) |
|-----------------|------------------------|
| `claude-opus-4-6` | `global.anthropic.claude-opus-4-6-v1` |
| `claude-sonnet-4-6` | `global.anthropic.claude-sonnet-4-6` |
| `claude-sonnet-4-5-20250929` | `global.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `claude-opus-4-5-20251101` | `global.anthropic.claude-opus-4-5-20251101-v1:0` |
| `claude-haiku-4-5-20251001` | `global.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `claude-sonnet-4-20250514` | `global.anthropic.claude-sonnet-4-20250514-v1:0` |
| `claude-opus-4-1-20250805` | `us.anthropic.claude-opus-4-1-20250805-v1:0` |
| `claude-opus-4-20250514` | `us.anthropic.claude-opus-4-20250514-v1:0` |
| `claude-3-7-sonnet-20250219` | `us.anthropic.claude-3-7-sonnet-20250219-v1:0` |

### 3. 版本号和 Beta header 位置不同

Anthropic 用 HTTP header：
```
anthropic-version: 2023-06-01
anthropic-beta: interleaved-thinking-2025-05-14,output-128k-2025-02-19
```

Bedrock 放在 request body 里：
```json
{
    "anthropic_version": "bedrock-2023-05-31",
    "anthropic_beta": ["interleaved-thinking-2025-05-14", "output-128k-2025-02-19"],
    ...
}
```

注意两点：
- 版本号的值不一样：Anthropic 是 `2023-06-01`，Bedrock 是 `bedrock-2023-05-31`
- Beta 从逗号分隔的 header 变成了 JSON 数组

> **实测**: 如果你把 `2023-06-01` 传给 Bedrock，它会返回 400 错误。必须用 `bedrock-2023-05-31`。

### 4. 流式调用是两个不同的 API

Anthropic 用同一个 endpoint，body 里加 `stream: true`：
```json
{ "model": "...", "stream": true, "messages": [...] }
```

Bedrock 是两个完全不同的 API：
- 非流式：`invoke_model()`
- 流式：`invoke_model_with_response_stream()`

而且 body 里不能有 `stream` 字段。

传输协议也不同：
- Anthropic 返回标准 HTTP SSE（`text/event-stream`）
- Bedrock 返回 AWS EventStream 二进制协议（AWS SDK 自动解码）

但好消息是：解码后的 JSON payload 结构是一样的。事件类型（`message_start`, `content_block_delta`, `message_stop` 等）完全相同。

### 5. 有些字段 Bedrock 不认

以下 Anthropic API 的字段，Bedrock 不支持，发过去会报错或被忽略：

| 字段 | Anthropic 用途 | Bedrock 态度 |
|------|---------------|-------------|
| `model` | 指定模型 | 不在 body 里，在 SDK 参数里 |
| `stream` | 控制流式 | 不在 body 里，由调用的 API 决定 |
| `metadata` | 请求元数据 (user_id) | 不支持 |
| `service_tier` | 优先级队列 | 不支持 |
| `inference_geo` | 推理地理位置 | 不支持（通过 region 配置替代） |
| `container` | 代码执行沙箱 | 不支持 |
| `mcp_servers` | MCP 服务器配置 | 不支持 |
| `cache_control` (top-level) | 自动缓存最后一个 block | 不支持 top-level（实测返回 400） |

> **实测**: `cache_control` 放在 top-level 会被 Bedrock 拒绝。但放在 content block 内部的 `cache_control` 是支持的（这是 Bedrock 的 prompt caching 机制）。

### 6. Server Tools 是最大的鸿沟

Anthropic API 有一类 "Server Tools"，由 Anthropic 的基础设施执行，不需要客户端实现：

| Server Tool | 功能 |
|-------------|------|
| `web_search` | 实时网页搜索 |
| `web_fetch` | 抓取网页内容 |
| `code_execution` | 沙箱代码执行 |
| `memory` | 持久化记忆 |
| `tool_search` | 工具搜索 (BM25/Regex) |

**Bedrock 完全不支持这些。** 如果你把 server tool 定义发给 Bedrock，它不会报错，但模型不会执行搜索或代码——它只会假装自己没有这个能力，返回纯文本回复。（实测确认）

自定义工具（client tools）两边完全兼容。

---

## 哪些东西是一样的（直接透传）

好消息是，核心功能高度兼容：

```
✅ messages 结构（role + content blocks）
✅ max_tokens, temperature, top_p, top_k, stop_sequences
✅ system prompt（string 或 TextBlock 数组）
✅ 自定义 tools 和 tool_choice
✅ thinking（enabled / adaptive / disabled + budget_tokens）
✅ thinking signature（跨平台兼容）
✅ 图片输入（base64）
✅ 大部分 beta headers
✅ Response 结构（id, type, role, content, stop_reason, usage）
✅ 流式事件类型（message_start, content_block_delta, text_delta, thinking_delta 等）
```

Response body 的 JSON 结构两边基本一致，因为 Bedrock 内部就是用 Anthropic 的 Messages API 格式。

---

## Thinking（深度思考）

两边都支持，参数一样：

```json
{
    "thinking": {
        "type": "enabled",
        "budget_tokens": 4000
    }
}
```

三种模式：

| 模式 | 适用模型 | 说明 |
|------|---------|------|
| `"type": "enabled"` + `budget_tokens` | Claude 3.7 ~ Opus 4.5 | 经典模式，指定 token 预算 |
| `"type": "adaptive"` | Claude Opus 4.6, Sonnet 4.6 | 新模式，模型自己决定是否思考、思考多深 |
| `"type": "disabled"` | 所有模型 | 关闭思考 |

关键约束（两边一样）：
- 开启 thinking 时不能改 `temperature`/`top_p`/`top_k`
- `budget_tokens` 必须 < `max_tokens`（interleaved thinking 除外）
- 最小 budget: 1,024 tokens
- `max_tokens` > 21,333 时必须用流式

Response 中会多一个 `thinking` content block：
```json
{
    "content": [
        { "type": "thinking", "thinking": "...", "signature": "..." },
        { "type": "text", "text": "最终回答" }
    ]
}
```

Claude 4+ 默认返回摘要版 thinking（不是完整推理过程）。想看完整的需要 beta header `dev-full-thinking-2025-05-14`。

---

## Prompt Caching

两边都支持，但机制略有不同。

Bedrock 的 prompt caching 用 block-level `cache_control`：

```json
{
    "messages": [{
        "role": "user",
        "content": [
            { "type": "text", "text": "很长的文档内容..." },
            {
                "type": "text",
                "text": "这之前的内容都会被缓存",
                "cache_control": { "type": "ephemeral" }
            }
        ]
    }]
}
```

可缓存的字段：`system`, `messages`, `tools`。

| 配置 | 说明 |
|------|------|
| TTL 默认 | 5 分钟 |
| TTL 可选 | 1 小时（仅 Opus 4.5, Sonnet 4.5, Haiku 4.5） |
| 最大 checkpoint | 4 个 |
| 最小 tokens/checkpoint | 1,024（部分模型 4,096） |

Response 中会返回缓存指标：
```json
{
    "usage": {
        "input_tokens": 100,
        "output_tokens": 50,
        "cache_creation_input_tokens": 5000,
        "cache_read_input_tokens": 0
    }
}
```

> **关键区别**: Anthropic API 支持 top-level `cache_control`（自动应用到最后一个可缓存 block），Bedrock 不支持。必须手动放在 content block 上。

---

## 如果你要做 Proxy（Anthropic API → Bedrock）

基于我们的实战经验，这是你需要做的转换清单：

### 必须做的

1. **认证替换**: 消费 `x-api-key`，用 AWS credentials 调 Bedrock
2. **提取 model**: 从 body 中取出 `model`，映射为 Bedrock modelId
3. **删除 stream**: 从 body 中取出 `stream`，决定调哪个 API
4. **覆盖 version**: 始终设置 `anthropic_version: "bedrock-2023-05-31"`（不管客户端传什么）
5. **转换 beta header**: `anthropic-beta` HTTP header → body 中 `anthropic_beta` 数组
6. **剥离不支持字段**: `metadata`, `service_tier`, `inference_geo`, `container`, `mcp_servers`, top-level `cache_control`
7. **流式协议转换**: AWS EventStream → HTTP SSE

### 建议做的

8. **过滤 server tools**: 从 `tools` 数组中移除 server tool types
9. **剥离 output_config.effort**: 大多数模型不支持（实测 Bedrock 返回 400）
10. **错误码映射**: Bedrock SDK 异常 → Anthropic 风格的 HTTP 错误

### Bedrock 错误码映射参考

| Bedrock 异常 | 应返回的 HTTP 状态码 | Anthropic error type |
|-------------|-------------------|---------------------|
| `ValidationException` | 400 | `invalid_request_error` |
| `ThrottlingException` | 429 | `rate_limit_error` |
| `AccessDeniedException` | 403 | `permission_error` |
| `ResourceNotFoundException` | 404 | `not_found_error` |
| `ModelTimeoutException` | 408 | `api_error` |
| `ServiceUnavailableException` | 529 | `overloaded_error` |
| `ModelErrorException` | 500 | `api_error` |

### Response 基本不用改

Bedrock 返回的 JSON 结构和 Anthropic API 一致，可以直接透传给客户端。唯一的额外字段是流式 `message_stop` 事件中的 `amazon-bedrock-invocationMetrics`，Anthropic API 没有这个。

---

## 实测踩过的坑

以下都是我们在开发 Bedrock Gateway 时通过真实 API 调用发现的：

1. **`anthropic_version` 必须覆盖，不能保留客户端的值**
   客户端可能传 `2023-06-01`（Anthropic 的版本号），Bedrock 只认 `bedrock-2023-05-31`，否则 400。

2. **Top-level `cache_control` 会导致 400**
   Anthropic SDK 可能发送 `"cache_control": {"type": "ephemeral"}` 在请求顶层，Bedrock 不认。必须剥离。

3. **`output_config.effort` 大多数模型不支持**
   即使加了 beta header `effort-2025-11-24`，也只有特定模型（如 Opus 4.5）支持。其他模型直接 400。

4. **Server tools 不会报错但也不会执行**
   把 `web_search` tool 定义发给 Bedrock，它不报错，但模型不会搜索——只会说"我没有搜索能力"。这是静默降级，比报错更危险。

5. **流式 chunk 解析失败会静默丢数据**
   如果 EventStream 中某个 chunk 的 JSON 解析失败，你的代码可能只是 log 一下就跳过了。客户端不知道丢了数据。

6. **客户端断开时 Bedrock 调用不会自动取消**
   流式请求中客户端断开，Bedrock 那边还在跑。你需要主动取消，否则浪费 token 和资源。

---

## 快速参考卡片

```
Anthropic API                          Bedrock InvokeModel
─────────────                          ───────────────────
POST /v1/messages                      invoke_model(modelId=..., body=...)
x-api-key: sk-ant-xxx                  AWS SigV4 (自动)
anthropic-version: 2023-06-01          body.anthropic_version: "bedrock-2023-05-31"
anthropic-beta: xxx,yyy                body.anthropic_beta: ["xxx","yyy"]
body.model: "claude-xxx"               modelId: "global.anthropic.claude-xxx"
body.stream: true → 同一 endpoint       invoke_model_with_response_stream()
Response: HTTP SSE                     Response: AWS EventStream → SDK 解码
Server tools: ✅                        Server tools: ❌
```
