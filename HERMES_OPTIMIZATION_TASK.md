# 에르메스(Hermes) 에이전트 최적화 작업 지시서

> **수신**: Hermes Agent
> **발신**: Orchestrator
> **브랜치**: `claude/optimize-hermes-agent-RMAsU`
> **목표**: 로컬 모델 + Claude + OpenAI(GPT-5.5) 멀티-백엔드에서 동작하는 Hermes 에이전트의 토큰 효율 및 하네스(harness) 구성 최적화

---

## 1. 미션 (Mission)

Hermes 에이전트가 **로컬 모델(llama.cpp / vLLM / Ollama 계열)**, **Anthropic Claude (Opus 4.7 / Sonnet 4.6 / Haiku 4.5)**, **OpenAI GPT-5.5** 세 종류 백엔드에서 일관된 품질로 동작하도록 하네스를 재설계하고, 각 백엔드별 토큰 사용량을 최소화한다.

핵심 원칙:
1. **백엔드 추상화** — 모델 교체 시 프롬프트/툴 정의를 중복 작성하지 않는다.
2. **토큰 절약 우선** — 동일 품질이면 더 적은 토큰을 쓰는 경로를 선택한다.
3. **하네스 결정성(determinism)** — 동일 입력 → 동일 동작. 무작위 시도 금지.

---

## 2. 작업 범위 (Scope)

### 2.1 백엔드 어댑터 계층 (Backend Adapter Layer)
- [ ] `LocalLLMAdapter`, `ClaudeAdapter`, `OpenAIAdapter` 인터페이스 통일
- [ ] 공통 `Message`, `ToolCall`, `ToolResult` 스키마 정의
- [ ] 각 백엔드별 토크나이저(tiktoken / Anthropic tokenizer / SentencePiece) 래핑
- [ ] 컨텍스트 윈도우 한계 자동 감지 (예: Opus 4.7 = 1M, GPT-5.5 = TBD, 로컬 = 모델별)

### 2.2 프롬프트 압축 (Prompt Compression)
- [ ] **시스템 프롬프트 정규화**: 중복 지시문 제거, 우선순위 기반 정렬
- [ ] **툴 스키마 슬리밍**: 사용 가능성 낮은 툴은 상황별로 마스킹(tool gating)
- [ ] **few-shot 예제 가지치기**: 임베딩 유사도 기반 top-k 선별
- [ ] **반복 컨텍스트 → 참조 ID화**: 동일 문서 재첨부 방지

### 2.3 캐싱 전략 (Caching Strategy)
- [ ] **Anthropic prompt caching**: `cache_control: {"type": "ephemeral"}`을 시스템 프롬프트 + 툴 정의 + 장기 컨텍스트에 적용
- [ ] **OpenAI prompt caching**: 1024 토큰 이상 prefix를 안정적으로 유지하여 자동 캐시 hit 유도
- [ ] **로컬 모델 KV-cache 재사용**: 세션 내 prefix 고정 → `--cache-type-k q8_0` 등 양자화된 KV 캐시 활용
- [ ] 캐시 hit rate 측정 메트릭 추가 (목표: ≥70%)

### 2.4 출력 토큰 최소화 (Output Token Minimization)
- [ ] 응답 포맷을 JSON/구조화 출력으로 강제 (산문 금지)
- [ ] `max_tokens` 단계별 상한 (계획 200 / 실행 800 / 요약 150)
- [ ] **streaming early-stop**: 종결 토큰 감지 시 즉시 중단
- [ ] 사고 연쇄(extended thinking)는 Claude만 활성화, 다른 백엔드는 단축 추론 사용

### 2.5 라우팅 정책 (Routing Policy)
- [ ] 작업 분류기: 단순 분류/추출 → 로컬 또는 Haiku, 복잡 추론 → Opus/GPT-5.5
- [ ] 비용 vs 지연 vs 품질의 3축 점수 기반 라우팅
- [ ] 폴백 체인: 로컬 실패 → Haiku → Sonnet → Opus

### 2.6 하네스 구성 파일 (Harness Config)
다음 형식으로 `hermes.harness.yaml`을 생성한다:

```yaml
hermes:
  default_backend: claude
  backends:
    local:
      provider: ollama
      model: qwen2.5:32b-instruct-q4_K_M
      context_window: 32768
      kv_cache_quant: q8_0
    claude:
      model: claude-sonnet-4-6
      max_tokens: 4096
      cache_control: ephemeral
      extended_thinking: false
    openai:
      model: gpt-5.5
      max_tokens: 4096
      reasoning_effort: medium

  routing:
    classify: local
    plan: claude:opus-4-7
    execute: claude:sonnet-4-6
    summarize: local

  budgets:
    per_turn_input_tokens: 8000
    per_turn_output_tokens: 1000
    session_total_usd: 1.50

  compression:
    tool_gating: true
    fewshot_top_k: 3
    dedupe_attachments: true
```

---

## 3. 산출물 (Deliverables)

1. **`hermes/adapters/`** — 3개 백엔드 어댑터 구현
2. **`hermes/harness/config.py`** — YAML 로더 + 검증
3. **`hermes/router.py`** — 라우팅 정책 엔진
4. **`hermes/cache/`** — 백엔드별 캐싱 래퍼
5. **`hermes.harness.yaml`** — 기본 설정
6. **`tests/`** — 백엔드 모킹 + 토큰 카운팅 회귀 테스트
7. **`benchmarks/token_report.md`** — 최적화 전/후 토큰 사용량 비교표

---

## 4. 토큰 최적화 KPI

| 항목 | 현재 (baseline) | 목표 |
| --- | --- | --- |
| 평균 입력 토큰/턴 | 측정 필요 | **−40%** |
| 평균 출력 토큰/턴 | 측정 필요 | **−25%** |
| Claude 캐시 hit rate | 0% | **≥70%** |
| OpenAI 캐시 hit rate | 0% | **≥60%** |
| 로컬 KV 재사용률 | 미적용 | **≥80%** |
| 턴당 평균 비용 (USD) | 측정 필요 | **−50%** |
| p50 응답 지연 | 측정 필요 | **±10% 이내 유지** |

---

## 5. 작업 순서 (Execution Order)

1. **측정**: 현 상태 baseline 토큰/비용/지연 측정 → `benchmarks/baseline.json`
2. **추상화**: 공통 어댑터 인터페이스 확정 후 3개 백엔드 구현
3. **캐싱**: Claude → OpenAI → 로컬 순서로 캐싱 적용
4. **압축**: 시스템 프롬프트, 툴 스키마, few-shot 가지치기
5. **라우팅**: 분류기 + 폴백 체인 도입
6. **검증**: 회귀 테스트 + KPI 비교 리포트 작성
7. **문서화**: `README.md`에 백엔드 전환 방법 1페이지 분량 추가

---

## 6. 제약 사항 (Constraints)

- **하위 호환성 유지**: 기존 호출 시그니처를 깨지 않는다. 필요한 경우 어댑터 내부에서만 변환.
- **시크릿 분리**: API 키는 환경 변수(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)로만 로드. 코드/설정에 하드코딩 금지.
- **결정론적 실행**: temperature 기본 0, 라우팅도 입력 해시 기반 결정성 보장.
- **로깅 PII 마스킹**: 토큰 카운트 로그에 사용자 입력 원문을 남기지 않는다.
- **모델 ID 정확도**: Anthropic 모델 ID는 `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`을 사용.

---

## 7. 검증 체크리스트 (Done Definition)

- [ ] 3개 백엔드 모두에서 동일 시나리오 통과
- [ ] baseline 대비 토큰/비용 KPI 모두 충족
- [ ] 회귀 테스트 100% 통과
- [ ] `hermes.harness.yaml` 단일 파일 변경만으로 백엔드 전환 가능
- [ ] 캐시 hit rate 메트릭이 로그/대시보드에 노출
- [ ] 폴백 체인 시나리오 통합 테스트 존재
- [ ] `benchmarks/token_report.md` 최신화

---

## 8. 보고 형식 (Reporting)

작업 완료 시 다음을 PR 본문에 포함한다:

```
## Summary
- 변경된 어댑터/모듈 목록
- 적용된 토큰 최적화 기법

## Token Report
| Backend | Before | After | Δ |
| --- | --- | --- | --- |
| Claude Sonnet 4.6 | ... | ... | ... |
| OpenAI GPT-5.5 | ... | ... | ... |
| Local (Qwen2.5-32B) | ... | ... | ... |

## Test plan
- [ ] 단위 테스트
- [ ] 통합 테스트 (3 백엔드)
- [ ] KPI 검증
```

---

**Hermes, 위 사양대로 진행하라. 불명확한 항목은 작업 시작 전에 질문으로 회수한다.**
