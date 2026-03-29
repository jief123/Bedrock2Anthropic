# Reference Documents for Bedrock → Anthropic API Proxy

Downloaded: 2026-03-28

## Anthropic API 标准交付物

| 文件 | 说明 | 来源 |
|------|------|------|
| `../anthropic-openapi.yaml` | Anthropic 官方 OpenAPI 3.1.0 Spec (24952行) | https://app.stainless.com/api/spec/documented/anthropic/openapi |
| `../anthropic-sdk-python-api.md` | Python SDK 类型索引 | https://github.com/anthropics/anthropic-sdk-python/blob/main/api.md |
| `../anthropic-sdk-typescript-api.md` | TypeScript SDK 类型索引 | https://github.com/anthropics/anthropic-sdk-typescript/blob/main/api.md |

## Bedrock 侧文档 (Markdown 格式)

| 文件 | 说明 | 来源 |
|------|------|------|
| `bedrock-claude-messages-overview.md` | Messages API 概览 + Request/Response | AWS Docs |
| `bedrock-claude-tool-use.md` | Tool Use 完整文档 | AWS Docs |
| `bedrock-claude-extended-thinking.md` | Extended Thinking 完整文档 | AWS Docs |
| `bedrock-claude-adaptive-thinking.md` | Adaptive Thinking 文档 | AWS Docs |
| `bedrock-prompt-caching.md` | Prompt Caching 完整文档 | AWS Docs |

## 使用方式

1. `anthropic-openapi.yaml` 是构建 Proxy 的核心参考，可用于：
   - 自动生成 request/response 类型定义
   - API schema validation
   - Contract-first 开发

2. Bedrock 侧文档用于理解转换逻辑和差异点

3. 结合已有的对比文档 (`2026-03-27-anthropic-api-vs-bedrock-invoke-model-comparison.md`) 和事实检查报告 (`aidlc-docs/inception/requirements/fact-check-summary.md`) 使用
