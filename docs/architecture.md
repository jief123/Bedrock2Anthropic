# Bedrock Gateway - 架构设计

## 项目定位

一个轻量级 API Gateway，对外暴露标准 Anthropic Messages API，内部转发到 AWS Bedrock InvokeModel API。
支持多账号分发、API Key 管理、限速、token 计量、请求日志。

## 技术栈

- Java 21 + Spring Boot 3.x + WebFlux (响应式，支持 SSE streaming)
- AWS SDK for Java v2 (BedrockRuntimeAsyncClient)
- Jackson (JSON 处理)
- SQLite / H2 (轻量存储：API Key、计量、配置)
- Bucket4j (限速)

## 核心模块

```
bedrock-gateway/
├── src/main/java/com/github/bedrockgateway/
│   ├── GatewayApplication.java
│   ├── config/
│   │   ├── GatewayProperties.java          # YAML 配置绑定
│   │   └── BedrockClientConfig.java         # 多账号 Client 池初始化
│   ├── controller/
│   │   └── MessagesController.java          # POST /v1/messages
│   ├── auth/
│   │   ├── ApiKeyAuthFilter.java            # API Key 认证 WebFilter
│   │   └── ApiKeyService.java               # API Key CRUD + 验证
│   ├── routing/
│   │   ├── RouteDecision.java               # 路由结果 (account + region + modelId)
│   │   └── RequestRouter.java               # 路由决策逻辑
│   ├── transform/
│   │   ├── RequestTransformer.java          # Anthropic → Bedrock 请求转换
│   │   └── ResponseTransformer.java         # Bedrock → Anthropic 响应转换 (如需)
│   ├── proxy/
│   │   ├── BedrockInvoker.java              # 非流式调用
│   │   └── BedrockStreamInvoker.java        # 流式调用 + SSE 转换
│   ├── metering/
│   │   ├── UsageRecord.java                 # token 用量记录
│   │   └── MeteringService.java             # 计量写入
│   ├── ratelimit/
│   │   └── RateLimitFilter.java             # API Key 级别限速
│   └── logging/
│       └── RequestLogger.java               # 请求/响应日志
├── src/main/resources/
│   ├── application.yml                      # 主配置
│   └── schema.sql                           # 数据库初始化
└── pom.xml
```

## 数据流

### Non-streaming

```
Client → POST /v1/messages (x-api-key: gw-xxx, stream: false)
  → ApiKeyAuthFilter: 验证 API Key
  → RateLimitFilter: 检查限速
  → MessagesController:
      1. RequestTransformer:
         - 提取 model, 去掉 stream/metadata/service_tier/inference_geo/container/mcp_servers/cache_control
         - 始终设置 anthropic_version = "bedrock-2023-05-31" (覆盖客户端传入的任何值)
         - 剥离 output_config.effort (Bedrock 对大多数模型不支持)
         - 过滤 tools 数组中的 server tools (web_search, code_execution 等 Bedrock 不支持)
         - 转换 anthropic-beta header → body 中 anthropic_beta 数组
      2. RequestRouter: 根据 API Key 配置选择 (account, region, modelId)
      3. BedrockInvoker: client.invokeModel(body, modelId)
      4. 解析 response.usage → MeteringService 记录
      5. RequestLogger 记录请求日志
      6. 返回 Bedrock response body (几乎不需要转换)
```

### Streaming

```
Client → POST /v1/messages (x-api-key: gw-xxx, stream: true)
  → ApiKeyAuthFilter + RateLimitFilter
  → MessagesController:
      1. RequestTransformer: 同上
      2. RequestRouter: 选择路由
      3. BedrockStreamInvoker:
         - client.invokeModelWithResponseStream(body, modelId, handler)
         - handler 收到每个 EventStream chunk (已解码为 JSON)
         - 包装成 SSE: "event: xxx\ndata: {json}\n\n"
         - 通过 Flux<ServerSentEvent> 推给客户端
      4. 从 message_delta 事件提取 usage → MeteringService
      5. RequestLogger 记录
```

## 配置设计 (application.yml)

```yaml
gateway:
  # API Keys
  api-keys:
    - key: "gw-key-001"
      name: "Team Alpha"
      rate-limit-per-minute: 60
      allowed-models:          # 可选，不配则允许所有
        - "claude-sonnet-4-5-*"
        - "claude-haiku-*"
      route: "account-a"       # 路由到哪个账号

  # Bedrock 账号配置
  accounts:
    account-a:
      region: "us-east-1"
      # 使用默认 credentials chain，或指定 profile/role
      # profile: "account-a-profile"
      # role-arn: "arn:aws:iam::111111:role/bedrock-access"
    account-b:
      region: "us-west-2"
      role-arn: "arn:aws:iam::222222:role/bedrock-access"

  # Model ID 映射 (Anthropic name → Bedrock model ID)
  # 优先使用 global. 前缀的 cross-region inference profile
  model-mapping:
    # global. 前缀 — Cross-region inference profile (推荐，自动路由到最近可用 region)
    claude-sonnet-4-5-20250929: "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    claude-sonnet-4-6: "global.anthropic.claude-sonnet-4-6"
    claude-opus-4-6: "global.anthropic.claude-opus-4-6-v1"
    claude-opus-4-5-20251101: "global.anthropic.claude-opus-4-5-20251101-v1:0"
    claude-haiku-4-5-20251001: "global.anthropic.claude-haiku-4-5-20251001-v1:0"
    claude-sonnet-4-20250514: "global.anthropic.claude-sonnet-4-20250514-v1:0"
    # us. 前缀 — 尚无 global profile 的模型，使用 US region inference profile
    claude-opus-4-1-20250805: "us.anthropic.claude-opus-4-1-20250805-v1:0"
    claude-opus-4-20250514: "us.anthropic.claude-opus-4-20250514-v1:0"
    claude-3-7-sonnet-20250219: "us.anthropic.claude-3-7-sonnet-20250219-v1:0"
    claude-3-5-sonnet-20241022: "us.anthropic.claude-3-5-sonnet-20241022-v2:0"

  # 日志
  logging:
    log-request-body: false    # 是否记录请求体 (注意隐私)
    log-response-body: false
    log-usage: true            # 记录 token 用量
```

## Model ID 解析规则

Bedrock 的 model ID 有三种格式，网关按以下优先级解析：

### 1. 映射表查找 (最高优先级)

从 `model-mapping` 配置中查找 Anthropic 模型名对应的 Bedrock model ID。

```
客户端发送: model: "claude-sonnet-4-5-20250929"
映射结果:   modelId: "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
```

### 2. 直接透传 (已是 Bedrock 格式)

如果模型名已经是 Bedrock model ID 格式，直接透传：
- `anthropic.` 前缀 — 单 region model ID (如 `anthropic.claude-sonnet-4-5-20250929-v1:0`)
- `us.anthropic.` 前缀 — US cross-region inference profile
- `global.anthropic.` 前缀 — Global cross-region inference profile
- 包含 `:` — 带版本号的完整 model ID

```
客户端发送: model: "global.anthropic.claude-sonnet-4-6"
透传结果:   modelId: "global.anthropic.claude-sonnet-4-6"
```

### 3. 回退规则 (兜底)

不在映射表中且不是 Bedrock 格式的模型名，使用 `us.anthropic.` 前缀拼接：

```
客户端发送: model: "claude-unknown-model"
回退结果:   modelId: "us.anthropic.claude-unknown-model-v1:0"
```

### Bedrock Model ID 格式说明

| 前缀 | 格式 | 说明 | 示例 |
|------|------|------|------|
| `anthropic.` | `anthropic.{model}-v{n}:{patch}` | 单 region，需要 account 在该 region 有模型访问权限 | `anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `us.anthropic.` | `us.anthropic.{model}-v{n}:{patch}` | US cross-region inference profile，自动路由到 US 内可用 region | `us.anthropic.claude-3-7-sonnet-20250219-v1:0` |
| `global.anthropic.` | `global.anthropic.{model}-v{n}:{patch}` | Global cross-region inference profile，自动路由到全球最近可用 region | `global.anthropic.claude-sonnet-4-5-20250929-v1:0` |

推荐优先使用 `global.` 前缀，可获得最佳延迟和可用性。对于尚未提供 global profile 的模型，使用 `us.` 前缀。

## 关键设计决策

1. **用 InvokeModel，不用 Converse API**
   - body 是 raw JSON bytes 透传，不存在类型不匹配
   - 支持所有 Anthropic 特有功能 (thinking, cache_control, beta headers)

2. **用 WebFlux，不用 Spring MVC**
   - Streaming SSE 需要非阻塞 IO
   - BedrockRuntimeAsyncClient 天然配合 CompletableFuture/Flux

3. **配置驱动，不做数据库管理界面**
   - API Key、路由、模型映射全在 YAML
   - 计量数据写 SQLite/H2，可以后续导出分析
   - 保持简单，避免过度设计

4. **请求转换最小化但安全**
   - 剥离 Bedrock 不支持的字段: `model`, `stream`, `metadata`, `service_tier`, `inference_geo`, `container`, `mcp_servers`, `cache_control` (top-level)
   - 始终覆盖 `anthropic_version` 为 `bedrock-2023-05-31`，不保留客户端传入的值（Bedrock 拒绝 Anthropic 原生版本号 `2023-06-01`，V2 测试证实）
   - 剥离 `output_config.effort`（Bedrock 对大多数模型不支持，V2 测试证实会导致 400）
   - 过滤 `tools` 数组中的 Anthropic server tools（`web_search`, `code_execution`, `memory` 等 Bedrock 不支持）
   - 其余 JSON 字段原样透传
   - Response 基本不改，Bedrock Claude 返回格式和 Anthropic API 一致

5. **Streaming 协议转换**
   - SDK 解码 EventStream → JSON chunks
   - Gateway 包装成 SSE text/event-stream
   - JSON payload 内容不需要改

## 请求转换详细规则

### 剥离的字段 (UNSUPPORTED_FIELDS)

| 字段 | 原因 | V2 测试验证 |
|------|------|------------|
| `model` | 提取后用于 Bedrock modelId 路由 | ✅ |
| `stream` | 提取后用于选择 InvokeModel / InvokeModelWithResponseStream | ✅ |
| `metadata` | Bedrock 不支持 | ✅ |
| `service_tier` | Bedrock 不支持 | ✅ |
| `inference_geo` | Bedrock 不支持，通过 region 配置替代 | ✅ |
| `container` | Bedrock 不支持 (Anthropic code execution) | ✅ |
| `mcp_servers` | Bedrock 不支持 (Anthropic MCP) | ✅ |
| `cache_control` (top-level) | Bedrock 不支持 top-level cache_control，仅支持 block-level | ✅ V2 测试证实 Bedrock 400 |

### 特殊转换

| 转换 | 规则 | V2 测试验证 |
|------|------|------------|
| `anthropic_version` | 始终覆盖为 `"bedrock-2023-05-31"`，不保留客户端值 | ✅ V2 测试证实 `2023-06-01` 导致 Bedrock 400 |
| `output_config.effort` | 剥离 effort 字段，保留 `output_config.format` | ✅ V2 测试证实 effort 导致 Bedrock 400 |
| `anthropic-beta` header | 转换为 body 中 `anthropic_beta` 数组 | ✅ |
| `tools` 数组 | 过滤 server tool types，仅保留 client tools | ✅ V2 测试证实 server tools 被 Bedrock 静默忽略 |

### Server Tools 过滤

以下 Anthropic server tool types 会被网关过滤，不转发到 Bedrock：

- `web_search_20250305`, `web_search_20260209`
- `web_fetch_20250910`, `web_fetch_20260209`, `web_fetch_20260309`
- `code_execution_20250522`, `code_execution_20250825`, `code_execution_20260120`
- `memory_20250818`
- `tool_search_bm25_20251119`, `tool_search_regex_20251119`

如果过滤后 tools 数组为空，同时移除 `tool_choice`。

## 已知限制

- **流式 chunk 解析失败**: 如果 Bedrock EventStream 中某个 chunk 的 JSON 解析失败，当前行为是静默丢弃并记录日志，客户端不会收到通知（代码审查确认的风险）
- **客户端断开时的资源清理**: 流式请求中客户端断开时，Bedrock 的 EventStream 调用不会被主动取消，Sink 可能继续缓冲数据（代码审查确认的风险）
- **Bedrock 额外字段**: `amazon-bedrock-invocationMetrics` 会出现在流式 `message_stop` 事件中，Anthropic API 原生不包含此字段

---

## 多账户分发与 Token 配额管理

### 现状

当前实现是静态 1:1 路由：

```
API Key (route: "account-a") ──→ Account "account-a" ──→ BedrockRuntimeAsyncClient
```

每个 API Key 绑定一个固定的 AWS 账户。`BedrockClientConfig` 启动时为每个 account 创建独立的 `BedrockRuntimeAsyncClient`，支持通过 STS AssumeRole 跨账户访问。

### 为什么需要多账户分发

Bedrock 对每个 AWS 账户有 token 级别的配额限制（RPM/TPM），单账户的配额可能不够用。多账户分发的目的：

1. **突破单账户配额上限**: 将请求分散到多个 AWS 账户，聚合配额
2. **Token 预算管理**: 给不同团队/API Key 分配 token 预算，用完即止
3. **成本隔离**: 不同团队的用量计入不同 AWS 账户的账单
4. **容灾**: 某个账户被限流或异常时自动切换

### 方案设计

#### 配置扩展

```yaml
gateway:
  api-keys:
    - key: "gw-team-alpha-001"
      name: "Team Alpha"
      rate-limit-per-minute: 120
      # 路由策略: 支持单账户或多账户
      route: "pool-main"
      # Token 预算 (可选): 每日/每月 token 上限
      token-budget:
        daily-input-tokens: 10000000     # 1000 万 input tokens/天
        daily-output-tokens: 2000000     # 200 万 output tokens/天
        monthly-input-tokens: 200000000  # 2 亿 input tokens/月

    - key: "gw-team-beta-002"
      name: "Team Beta"
      route: "account-b"               # 固定路由到单账户（向后兼容）
      token-budget:
        daily-input-tokens: 5000000

  # 账户池: 一个 route 可以对应多个账户
  account-pools:
    pool-main:
      strategy: "token-balanced"        # 路由策略
      accounts: ["account-a", "account-b", "account-c"]
      # 每个账户的权重或配额
      weights:
        account-a: 50                   # 50% 流量
        account-b: 30
        account-c: 20

  accounts:
    account-a:
      region: "us-east-1"
      # 账户级 token 配额 (Bedrock 的实际限制)
      quota:
        rpm: 1000                       # requests per minute
        tpm-input: 2000000              # input tokens per minute
        tpm-output: 400000              # output tokens per minute
    account-b:
      region: "us-west-2"
      role-arn: "arn:aws:iam::222222222222:role/bedrock-access"
      quota:
        rpm: 500
        tpm-input: 1000000
        tpm-output: 200000
    account-c:
      region: "eu-west-1"
      role-arn: "arn:aws:iam::333333333333:role/bedrock-access"
      quota:
        rpm: 500
        tpm-input: 1000000
        tpm-output: 200000
```

#### 路由策略

| 策略 | 说明 | 适用场景 |
|------|------|---------|
| `fixed` | 固定路由到单账户（当前行为） | 简单场景，成本隔离 |
| `round-robin` | 轮询分发 | 均匀分散请求 |
| `weighted` | 按权重分发 | 不同账户配额不同 |
| `token-balanced` | 按已用 token 比例分发，优先选剩余配额最多的 | Token 配额管理 |
| `least-loaded` | 选当前 RPM 最低的账户 | 避免单账户限流 |
| `failover` | 主账户失败后切换到备用 | 高可用 |

#### 路由决策流程

```
请求到达
  │
  ├── 1. 查找 API Key 的 route 配置
  │     ├── route 是单账户名 → 直接路由（当前行为）
  │     └── route 是 pool 名 → 进入池路由
  │
  ├── 2. 检查 API Key 的 token 预算
  │     ├── 未超预算 → 继续
  │     └── 已超预算 → 返回 429 "Token budget exceeded"
  │
  ├── 3. 池路由策略选择账户
  │     ├── token-balanced: 查询各账户已用 token，选剩余最多的
  │     ├── weighted: 按权重随机选择
  │     └── round-robin: 轮询
  │
  ├── 4. 检查目标账户配额
  │     ├── 未超配额 → 发送请求
  │     └── 已超配额 → 标记该账户暂时不可用，回到 step 3 选下一个
  │
  └── 5. 所有账户都超配额 → 返回 429 "All accounts throttled"
```

#### 核心组件变更

```
routing/
├── RequestRouter.java          # 现有，扩展支持 pool 路由
├── RouteDecision.java          # 现有，不变
├── AccountPool.java            # 新增: 账户池管理
├── RoutingStrategy.java        # 新增: 路由策略接口
├── TokenBalancedStrategy.java  # 新增: 按 token 余量路由
├── WeightedStrategy.java       # 新增: 按权重路由
└── FailoverStrategy.java       # 新增: 主备切换

budget/
├── TokenBudgetService.java     # 新增: API Key 级别 token 预算管理
├── AccountQuotaTracker.java    # 新增: 账户级别配额追踪
└── BudgetRecord.java           # 新增: 预算记录
```

#### RequestRouter 扩展

```java
public Optional<RouteDecision> route(ApiKeyConfig keyConfig, String model) {
    String routeName = keyConfig.getRoute();

    // 检查 token 预算
    if (!budgetService.hasRemainingBudget(keyConfig)) {
        throw new BudgetExceededException(keyConfig.getName());
    }

    // 单账户路由（向后兼容）
    if (clients.containsKey(routeName)) {
        return routeToAccount(routeName, model);
    }

    // 池路由
    AccountPool pool = pools.get(routeName);
    if (pool == null) return Optional.empty();

    // 按策略选择账户，跳过超配额的
    for (String accountId : pool.selectAccounts()) {
        if (quotaTracker.hasCapacity(accountId)) {
            return routeToAccount(accountId, model);
        }
    }

    return Optional.empty(); // 所有账户都超配额
}
```

#### Token 预算追踪

利用现有的 `MeteringService` 和 `usage_records` 表，聚合查询即可：

```sql
-- 查询某 API Key 今日已用 input tokens
SELECT COALESCE(SUM(input_tokens), 0) as used
FROM usage_records
WHERE api_key = ? AND created_at >= CURRENT_DATE;

-- 查询某账户当前分钟的 RPM
SELECT COUNT(*) as rpm
FROM usage_records
WHERE account_id = ? AND created_at >= DATEADD('MINUTE', -1, CURRENT_TIMESTAMP);
```

#### 账户配额追踪

Bedrock 的限流是 per-account per-model 的。当收到 `ThrottlingException` 时：

```java
// 在 MessagesController.mapBedrockError() 中
if (cause instanceof ThrottlingException) {
    // 标记该账户暂时限流，下次路由时跳过
    quotaTracker.markThrottled(route.accountId(), Duration.ofSeconds(30));
    // 如果是池路由，可以自动重试到其他账户
    if (isPoolRoute) {
        return retryWithNextAccount(result, keyConfig, startTime);
    }
}
```

### 实施路径

| 阶段 | 内容 | 复杂度 |
|------|------|--------|
| Phase 1 | API Key token 预算（基于现有 metering 数据聚合） | 低 |
| Phase 2 | 账户池 + weighted/round-robin 路由 | 中 |
| Phase 3 | token-balanced 路由（需要实时 token 计数） | 中 |
| Phase 4 | ThrottlingException 自动重试 + failover | 中高 |
| Phase 5 | 账户配额实时追踪 + 预测性路由 | 高 |

Phase 1 最简单也最有价值——只需要在 `MessagesController` 里加一个预算检查，查询 `usage_records` 表的聚合数据。现有的 metering 基础设施已经在记录每个请求的 token 用量了。
