# Protocol Translation Test Report

## Summary

- Items identified: 35 (5 modes, 22 data mappings, 18 error paths)
- Risk breakdown: 3 Critical, 4 High, 3 Medium, 25 Low
- Scenarios generated: 31
- Tests passed: 31
- Tests failed: 0

## Critical Findings Fixed Before Testing

| # | Item | Issue | Fix |
|---|------|-------|-----|
| 1 | E5/E6/E7 | All Bedrock errors mapped to HTTP 500 | Added `mapBedrockError()` with proper status code mapping (400/403/404/408/429/500/529) |
| 2 | E10 | Malformed JSON → unhandled exception | Added `JsonProcessingException` catch → 400 |
| 3 | E11 | Missing `model` field → NPE in router | Added null check → 400 with clear message |

## Test Coverage Matrix

| Item | Risk | Happy | Missing | Boundary | Error | Combo | Total |
|------|------|-------|---------|----------|-------|-------|-------|
| M1 (non-stream) | P0 | ✓ | — | — | — | — | 5 |
| M2 (stream) | P0 | ✓ | — | — | — | ✓ | 10 |
| E1 (no key) | P0 | — | — | — | ✓ | — | 1 |
| E2 (bad key) | P0 | — | — | — | ✓ | — | 1 |
| E5 (400) | P0 | — | — | — | ✓ | — | 2 |
| E10 (bad JSON) | P1 | — | — | — | ✓ | — | 1 |
| E11 (no model) | P1 | — | — | — | ✓ | — | 2 |
| D1 (model map) | P2 | ✓ | — | — | — | — | 1 |
| D3 (version) | P1 | ✓ | — | — | — | — | 1 |
| D4 (beta) | P1 | ✓ | — | — | — | — | 1 |
| D12 (multimodal) | P1 | ✓ | — | — | — | — | 1 |
| D18 (tools) | P1 | ✓ | — | — | — | — | 2 |
| D20 (thinking) | P1 | ✓ | — | — | — | ✓ | 6 |

## Known Gaps

- E13: Client disconnect during stream — not tested (requires infra)
- E16: Request body too large — not tested
- D22: Top-level `cache_control` — not tested (needs specific prompt size)
- R3: `amazon-bedrock-invocationMetrics` extra field in streaming — present but not stripped
- E6/E7: Bedrock 429/403 — cannot trigger on demand, verified via code review
