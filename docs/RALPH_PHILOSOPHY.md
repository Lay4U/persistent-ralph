# Ralph's Philosophy - 자율 에이전트 설계 원칙

> 목표를 달성하기 위한 자율 AI 에이전트의 행동 철학과 설계 원칙

## 1. 현재 Ralph's Laws

```
- Never stop until goal is achieved (목표 달성까지 멈추지 않는다)
- Failure is a learning opportunity (실패는 학습의 기회)
- Don't obsess over what doesn't work, move on (안 되는 것에 집착하지 말고 넘어가라)
- Iterative improvement beats perfect first attempt (반복 개선이 완벽한 첫 시도보다 낫다)
- There's always another way (항상 다른 방법이 있다)
```

---

## 2. 영감의 출처: Wreck-It Ralph

### Bad Guy Affirmation (악당 다짐)
> "I'm bad, and that's good. I will never be good, and that's not bad. There's no one I'd rather be than me."
>
> "나는 나쁘고, 그건 좋은 거야. 난 절대 좋은 사람이 될 수 없어, 그리고 그건 나쁜 게 아니야. 나는 나 말고 다른 누구도 되고 싶지 않아."

### 핵심 철학
- **역할과 정체성의 분리**: 역할(bad guy)이 본질을 정의하지 않는다
- **자기 수용**: 외부 레이블이 진정한 가치를 결정하지 않는다
- **"Labels not make you happy"**: 라벨이 아닌 자기 자신을 사랑해야 한다

---

## 3. 자율 에이전트 설계 원칙 (연구 기반)

### 3.1 회복탄력성 (Resilience)

| 원칙 | 설명 |
|------|------|
| **완벽한 예방보다 회복** | 절대적 보안/성공은 불가능. 충격 흡수, 기능 회복, 실패 학습 설계 |
| **자기 재조직화** | 내부 저하나 외부 압력에 반응하여 스스로 재구성 |
| **Graceful Degradation** | 부분 실패에도 핵심 기능 유지 |

### 3.2 지속성 (Persistence)

| 원칙 | 설명 |
|------|------|
| **영구 메모리** | 자율 계획을 위한 지속적 상태 구조 필요 |
| **컨텍스트 복원** | 세션 간 지식과 진행상황 유지 |
| **암시적 + 명시적 메모리** | 모델 파라미터 + 외부 저장소 조합 |

### 3.3 단순성과 투명성 (Anthropic 권장)

| 원칙 | 설명 |
|------|------|
| **설계 단순화** | 복잡할수록 오류 누적 가능성 증가 |
| **계획 단계 명시** | 에이전트의 사고 과정을 투명하게 표시 |
| **신중한 ACI 설계** | 도구 문서화 및 철저한 테스트 |

---

## 4. 루프 탈출 전략 (Anti-Stuck Patterns)

### 4.1 왜 에이전트가 루프에 빠지는가?

- 모델이 자신이 반복하고 있음을 인식하지 못함
- 시도한 솔루션 추적 메커니즘 부재
- 막다른 길에서 탈출 전략 부재
- 종료 신호 오해석

### 4.2 루프 감지 전략

```
1. 반복 감지 (Repetition Detection)
   - 최근 N개 액션이 동일한지 확인
   - 진동 패턴 감지 (A-B-A-B)

2. 리소스 모니터링
   - 토큰 사용량, API 호출, 실행 시간 추적
   - 이상 징후 시 개입

3. 의미론적 완료 확인
   - 출력이 의도한 완료 기준 충족 여부 검증
```

### 4.3 루프 방지 전략

| 전략 | 설명 |
|------|------|
| **Hard Cap** | 최대 반복 횟수/실행 시간 제한 (절대 안전장치) |
| **Circuit Breaker** | 연속 실패 시 일시 중단 |
| **명시적 개입** | "이 방법을 N번 시도했지만 안 됩니다" 프롬프트 주입 |
| **작업 분해** | 큰 작업을 작은 하위 작업으로 분리, 각각 새 컨텍스트 |
| **사용자 에스컬레이션** | 반복 감지 시 사용자 입력 요청 |
| **오류 복구 설계** | 예외 대신 오류 정보 반환, 대안 시도 기회 제공 |

---

## 5. 재시도 전략 (Retry Patterns)

### 5.1 지수 백오프 (Exponential Backoff)

```
시도 1: 1초 대기
시도 2: 2초 대기
시도 3: 4초 대기
시도 4: 8초 대기
...
```

**왜 필요한가?**
- 즉시 재시도는 "thundering herd" 문제 유발
- 시스템에 복구 시간 제공
- 리소스 소모 방지

### 5.2 Jitter (랜덤 지연)

- 여러 클라이언트의 동기화된 재시도 방지
- 부하 분산 효과

### 5.3 최대 재시도 제한

```
- 무한 재시도 금지
- 최대 지연 시간 상한 설정
- 최대 재시도 후 실패 처리
```

---

## 6. 개선된 Ralph's Laws 제안

### 현재 버전
```
1. Never stop until goal is achieved
2. Failure is a learning opportunity
3. Don't obsess over what doesn't work, move on
4. Iterative improvement beats perfect first attempt
5. There's always another way
```

### 개선 제안

```markdown
## Ralph's Laws v2.0

### 핵심 원칙 (Core Principles)
1. **Never stop until goal is achieved**
   - 목표 달성까지 멈추지 않는다
   - 단, 안전장치(Circuit Breaker)를 존중한다

2. **Failure is data, not defeat**
   - 실패는 패배가 아닌 데이터
   - 실패 원인을 experiments.md에 기록한다

3. **Pivot, don't persist on dead ends**
   - 막다른 길에서는 집착하지 말고 방향을 전환
   - 3회 연속 같은 오류면 다른 접근법 시도

4. **Progress over perfection**
   - 완벽보다 진전
   - 작은 커밋이 큰 완성보다 가치있다

5. **There's always another way**
   - 항상 다른 방법이 존재한다
   - 막혔을 때: 분해 → 검색 → 실험 → 질문

### 운영 원칙 (Operational Principles)
6. **Record everything**
   - 모든 시도와 결과를 기록한다
   - 미래의 자신을 위한 문서화

7. **Small commits, frequent progress**
   - 작은 단위로 자주 커밋
   - 진행상황의 가시화

8. **Know when to escalate**
   - 언제 도움을 요청할지 안다
   - 5회 연속 무진전 → 사용자에게 보고

9. **Respect the guardrails**
   - 안전장치를 존중한다
   - Circuit Breaker, Rate Limit은 보호 장치

10. **Leave context for future self**
    - 미래의 자신을 위한 컨텍스트 남기기
    - 세션 종료 전 상태 정리
```

---

## 7. 구현 권장사항

### 7.1 감지 메커니즘
- [ ] 반복 패턴 감지 (현재: Circuit Breaker 있음)
- [ ] 진동 패턴 감지 (A-B-A-B) 추가
- [ ] 의미론적 진행도 측정

### 7.2 복구 메커니즘
- [ ] 자동 작업 분해
- [ ] 대안 접근법 제안
- [ ] 프롬프트 기반 개입 ("이 방법이 안 됩니다")

### 7.3 기록 메커니즘
- [x] experiments.md 자동 기록
- [ ] 실패 원인 분류
- [ ] 성공 패턴 학습

---

## 참고 자료

### 영화
- [Wreck-It Ralph Bad-Anon](https://wreckitralph.fandom.com/wiki/Bad-Anon)
- [My Geek Wisdom - Bad Guy Affirmation](https://mygeekwisdom.com/2013/09/14/im-bad-and-thats-good-i-will-never-be-good-and-thats-not-bad-theres-no-one-id-rather-be-than-me/)

### 기술 문서
- [Anthropic - Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)
- [Google Cloud - Agentic AI Design Patterns](https://docs.cloud.google.com/architecture/choose-design-pattern-agentic-ai-system)
- [Why Agents Get Stuck in Loops](https://dev.to/gantz/why-agents-get-stuck-in-loops-and-how-to-prevent-it-nob)
- [Portkey - Retries, Fallbacks, Circuit Breakers](https://portkey.ai/blog/retries-fallbacks-and-circuit-breakers-in-llm-apps/)
- [Invariant - Loop Detection](https://explorer.invariantlabs.ai/docs/guardrails/loops/)

---

*Last Updated: 2026-01-18*
