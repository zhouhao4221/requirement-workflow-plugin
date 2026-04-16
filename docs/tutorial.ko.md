# 튜토리얼

🌐 [English](tutorial.en.md) | [中文](tutorial.md) | [한국어](tutorial.ko.md)

이 튜토리얼은 플러그인 설치부터 요구사항 종료까지의 전체 플로우를 예제로 안내합니다.

> 예시 시나리오: 백엔드 프로젝트에서 "사용자 포인트 규칙 관리" 기능 개발.

---

## 1. 설치 & 초기화

> **두 단계 시작**: 플러그인 설치 후 Claude Code 세션을 열 때마다, 현재 레포의 초기화 상태와 브랜치 전략 설정 여부를 체크합니다. 둘 중 하나라도 빠져 있으면 세션 시작 시 안내 메시지가 출력됩니다. 아래 두 단계를 완료하면 메시지는 자동으로 사라집니다:
>
> 1. `/req:init <project-name>` — 요구사항 프로젝트 초기화
> 2. `/req:branch init` — 브랜치 전략 설정
>
> 이후 `/req:new` 로 첫 요구사항을 만들 수 있습니다.

### 1.1 플러그인 설치

```bash
# 1. 플러그인 레포를 marketplace 로 추가
claude plugins marketplace add https://github.com/zhouhao4221/devflow-claude

# 2. marketplace 에서 플러그인 설치
claude plugins install req@devflow

# 설치 확인
claude plugins list
```

### 1.2 요구사항 프로젝트 초기화

프로젝트 루트에서 Claude Code 를 실행한 뒤:

```
/req:init my-saas
```

수행 내용:
- 로컬 디렉터리 `docs/requirements/` 생성 (`active/`, `completed/`, `modules/`, `templates/`)
- 전역 캐시 `~/.claude-requirements/projects/my-saas/` 생성
- PRD 템플릿 `docs/requirements/PRD.md` 생성
- `.claude/settings.local.json` 에 프로젝트 이름과 역할 기록

### 1.3 CLAUDE.md 아키텍처 설명

초기화 시 프로젝트 CLAUDE.md 에 아키텍처 정보가 있는지 확인합니다. 없으면 프리셋 템플릿을 선택하도록 안내합니다:

```
📋 프로젝트 타입을 선택하여 CLAUDE.md 스니펫 생성:

  1. Go 백엔드 (Gin + GORM 계층 아키텍처)
  2. Java 백엔드 (Spring Boot 계층 아키텍처)
  3. 프론트엔드 프로젝트 (React/Vue + TypeScript)
  4. 커스텀 (빈 템플릿, 수동 입력)
  5. 건너뛰기
```

선택한 스니펫은 프로젝트 CLAUDE.md 에 추가되며 기술 스택, 계층 아키텍처 표, 코딩 규칙, 테스트 규칙 등을 포함합니다. `/req:dev` 와 `/req:test` 는 이 정보를 기반으로 플랜을 생성하고 테스트 파일을 찾습니다.

> **이후 수정**: 프로젝트 CLAUDE.md 의 "프로젝트 아키텍처" 섹션을 직접 편집하세요.

### 1.4 브랜치 전략 설정 (강력 권장)

```
/req:branch init
```

> 미설정 시 세션 시작 배너가 계속 안내합니다. 설정 완료 후 메시지는 자동으로 사라집니다. 설정 없이도 동작은 하며, 기본값 (`feat/` / `fix/` 하드코딩 prefix, PR 자동 생성 없음) 이 적용됩니다.

팀의 브랜치 전략 선택:
- **GitHub Flow** (권장): 모든 브랜치를 main 에서 분기, main 으로 머지
- **Git Flow**: feature 브랜치는 develop 에서 분기, develop 으로 머지
- **Trunk-Based**: 짧은 수명 브랜치, 메인 기반 개발

이후 호스팅 종류 선택:
- **GitHub**: `/req:pr` 시 `gh pr create` 커맨드 제안
- **Gitea**: `/req:pr` 시 Gitea REST API 를 호출하여 PR 자동 생성
- **기타**: `git merge` 커맨드만 표시

설정 후 `/req:dev`, `/req:commit`, `/req:done`, `/req:pr` 이 자동으로 전략을 따릅니다.

### 1.5 재초기화

기존 프로젝트에서 누락된 파일을 보충 (덮어쓰지 않음):

```
/req:init my-saas --reinit
```

용도:
- 플러그인 업그레이드 후 새 템플릿 파일 반영
- 누락된 디렉터리 보충 (예: `modules/`, `templates/`)
- CLAUDE.md 아키텍처 안내 재실행
- 삭제된 `PRD.md` 또는 모듈 문서 복구

### 1.6 캐시 재구축

전역 캐시가 손상되었거나 유실된 경우, 로컬 저장소로부터 재구축:

```
/req:cache rebuild
```

기타 캐시 작업:

```
/req:cache info          # 캐시 상태 확인
/req:cache clear         # 현재 프로젝트 캐시 삭제
/req:cache clear-all     # 모든 프로젝트 캐시 삭제
/req:cache export        # 캐시 데이터 내보내기
```

### 1.7 템플릿 동기화 (선택 사항)

플러그인이 새 템플릿을 배포한 경우:

```
/req:update-template
```

### 1.8 Gitea Token 설정 (Gitea 레포 필수)

`/req:branch init` 에서 Gitea 를 선택했다면, PR 자동 생성을 위해 API Token 이 필요합니다.

**Token 발급:**

1. Gitea 로그인 → 우측 상단 아바타 → **설정**
2. 좌측 메뉴 → **애플리케이션**
3. "Access Token 관리" → 이름 입력 (예: `claude-pr`)
4. 권한 범위 선택:

| 분류 | 권한 | 필수 | 비고 |
|------|------|------|------|
| issue | 읽기/쓰기 | ✅ | PR 은 issue 의 확장이므로 생성/조회에 필요 |
| repository | 읽기/쓰기 | ✅ | 레포 정보 읽기, 브랜치 목록, 코드 푸시 |
| user | 읽기 | 선택 | Token 유효성 검증용 |

5. **Token 생성** 클릭 → 복사 & 저장 (한 번만 표시됨)

**Token 설정:**

`.claude/settings.local.json` 의 `branchStrategy.giteaToken` 필드에 Token 작성:

```json
{
  "branchStrategy": {
    "repoType": "gitea",
    "giteaUrl": "https://your-gitea.com",
    "giteaToken": "your-token-here"
  }
}
```

> **보안 안내**: `settings.local.json` 은 Git 에 커밋하면 안 됩니다. `.gitignore` 에 포함되어 있는지 확인하세요.

**Token 검증:**

```bash
curl -s -H "Authorization: token your-token-here" \
  https://your-gitea.com/api/v1/user
```

유저 정보가 반환되면 Token 설정 성공.

---

## 2. 요구사항 생성

### 2.1 정식 요구사항 (REQ)

```
/req:new 사용자 포인트 규칙 관리 --type=백엔드
```

AI 가 섹션별로 안내합니다:

| 섹션 | 내용 | 작업 |
|------|------|------|
| I. 요구사항 설명 | 배경, 목표, 고객 시나리오, 가치 | 비즈니스 배경을 설명하면 AI 가 구조화 |
| II. 기능 리스트 | 체크 가능한 기능 목록 | 범위 확정 |
| III. 비즈니스 규칙 | 검증, 상태 전이, 권한 | 세부 내용 보완 |
| IV. 사용 시나리오 | 역할, 흐름, 예외 처리 | 대표 플로우 기술 |
| V. 인터페이스 요구 | API 능력, 입출력, 의미 | API 요구사항 확정 |
| VI. 테스트 포인트 | 검증 필요 시나리오 | 테스트 포커스 보완 |

`docs/requirements/active/REQ-001-user-points-rule-management.md` 가 생성됩니다.

### 2.2 빠른 수정 (QUICK)

작은 버그/작은 기능에 적합한 경량 플로우:

```
/req:new-quick 포인트 계산 정밀도 손실 수정
```

QUICK 템플릿은 더 간단합니다: 문제 기술 → 구현 플랜 → 검증 방식.

### 2.3 요구사항 분할 제안

단위가 적절한지 불확실할 때:

```
/req:split 사용자 포인트 시스템
```

AI 가 단위를 분석하고 분할 플랜을 제안합니다 (읽기 전용, 문서 생성 없음).

### 2.4 Git 이슈에서 요구사항 생성

팀이 Gitea / GitHub issue 를 요구사항 입구로 사용한다면:

```
/req:new --from-issue=#12           # 정식 요구사항
/req:new-quick --from-issue=#5      # 빠른 수정
/req:do --from-issue=#42            # 문서 없이, issue 본문을 의도로 스마트 개발 실행
```

**AI 동작:**
1. `branchStrategy.repoType` 에 맞는 API 로 issue 조회 (Gitea → REST API + `giteaToken`; GitHub → `gh issue view`)
2. issue 제목을 요구사항 기본 제목으로, 본문을 "문제 & 현황" 의 초기 입력으로 사용
3. 문서 메타에 `issue: #N` 기록, 후속 자동 연동에 사용

**Gitea 레포 전제 조건**: `branchStrategy.giteaUrl` 과 `giteaToken` 설정 필요 (1.8 참조). AI 는 SSH remote 에서 HTTPS URL 을 **추측하지 않으며**, 설정을 통해서만 동작합니다.

#### issue ↔ 브랜치/커밋 자동 연동

issue 가 연결되면 전체 체인이 자동으로 issue 번호를 담고 갑니다:

| 단계 | 동작 |
|------|------|
| `/req:dev` 브랜치 생성 | 끝에 `-iN` 자동 추가 (예: `feat/REQ-001-user-points-i12`) |
| `/req:commit` 커밋 | commit message 끝에 `closes #N` 자동 추가 (PR 머지 시 Git 플랫폼이 issue 자동 종료) |
| `/req:done` 아카이브 | API 로 issue 를 바로 종료할지 질문 |
| `/req:do --from-issue` | `-iN` 이 붙은 브랜치 생성; 완료 시 issue 종료 여부 질문 |

**조회 우선순위**: 요구사항 문서 `issue` 필드 > 브랜치명 `-iN` 서픽스. 문서 없는 `/req:do` 라도 commit / done 이 브랜치명에서 issue 번호를 유추할 수 있습니다.

---

## 3. 리뷰 플로우

> QUICK 은 리뷰를 건너뛰고 바로 개발로 진행 가능합니다.

### 3.1 리뷰 제출

```
/req:review
```

상태가 초안 → 리뷰 대기 로 전환됩니다.

### 3.2 리뷰 결정

```
/req:review pass     # 승인 → 리뷰 통과
/req:review reject   # 반려 → 초안으로 복귀
```

반려 후 `/req:edit` 로 수정 후 재제출합니다.

---

## 4. 개발 단계

### 4.1 개발 시작

```
/req:dev
```

실행 흐름:

```
사전 체크 (REQ 는 리뷰 통과 필수)
    ↓
브랜치 관리 (feat/REQ-001-user-points-rule 자동 생성)
    ↓
CLAUDE.md 에서 프로젝트 아키텍처 로드 (계층 순서, 디렉터리 구조)
    ↓
요구사항 컨텍스트 로드 (섹션 I–VI)
    ↓
구현 플랜 생성 (Plan Mode)
    ├── 10.1 데이터 모델
    ├── 10.2 API 설계 (인터페이스 요구 + 레포 코드 기반)
    ├── 10.3 파일 변경 목록 (CLAUDE.md 계층별 나열)
    └── 10.4 구현 단계 (CLAUDE.md 계층 순서로 분해)
    ↓
플랜 확정 → 상태 개발 중 으로 전환
    ↓
CLAUDE.md 계층 순서로 단계별 구현
```

### 4.2 브랜치 관리

첫 번째 `/req:dev` 실행 시 AI 가 자동으로:

1. 워크스페이스가 깨끗한지 확인 (미커밋 변경이 있으면 중단)
2. 브랜치 전략 설정 로드 (`/req:branch init` 완료 시)
3. 요구사항 제목에서 영문 브랜치명 생성 후 확인 요청:
   ```
   개발 브랜치 생성: feat/REQ-001-user-points-rule
   기반 브랜치: main (branchStrategy.branchFrom 에서)
   ```
4. 확인 후 브랜치 생성하고 문서의 `branch` 필드에 기록

재실행 시 기록된 브랜치로 바로 전환합니다.

브랜치 네이밍 규칙 (prefix 는 전략 설정으로 커스텀 가능):
- REQ → `feat/REQ-XXX-<english-slug>[-iN]`
- QUICK → `fix/QUICK-XXX-<english-slug>[-iN]`
- `/req:do --from-issue` → `<prefix><slug>-iN` (prefix 는 AI 가 의도로부터 결정)
- 핫픽스 → `hotfix/<english-slug>` (`/req:branch hotfix` 로 생성)
- `-iN`: Git 플랫폼 issue 연결 시 자동 추가되는 선택적 서픽스 (예: `-i12`), 후속 커맨드의 연결 식별용 (2.4 참조)

### 4.2.1 브랜치 전략 커맨드

```
/req:branch              # 현재 전략 및 브랜치 상태 확인
/req:branch init         # 인터랙티브 브랜치 전략 + 레포 타입 설정
/req:branch status       # 전략 설정 및 요구사항별 브랜치 상태 확인
/req:branch hotfix 설명  # 메인 브랜치에서 핫픽스 브랜치 생성
```

### 4.2.2 PR 생성

개발 완료 후 PR 생성:

```
/req:pr              # 현재 브랜치에서 요구사항 자동 매칭하여 PR 생성
/req:pr REQ-001      # 특정 요구사항으로 PR 생성
```

`/req:branch init` 에서 설정한 레포 타입에 따라:
- **Gitea**: Gitea REST API 로 PR 자동 생성 (`giteaToken` 필요, 1.8 참조)
- **GitHub**: `gh` CLI 로 PR 생성
- **기타**: 브랜치 리모트 푸시 후 머지 커맨드 표시

Git Flow 의 hotfix 브랜치는 자동으로 두 PR 을 생성합니다 (→ main + → develop).

### 4.2.3 PR 리뷰 & 머지

AI 코드 리뷰와 머지 사용:

```
/req:review-pr              # PR 상태 확인
/req:review-pr review       # AI 코드 리뷰
/req:review-pr merge        # PR 머지
```

**리뷰 플로우:**
1. AI 가 PR diff 를 가져와 파일별로 리뷰 (정확성, 보안, 규칙, 요구사항 일치 여부)
2. 문제는 3단계로 분류: 🔴 블로커 (필수 수정), 🟡 제안, 🔵 정보
3. 리뷰 리포트는 PR 코멘트로 자동 제출 (Gitea/GitHub 웹에서 확인 가능)
4. 블로커 없음 → `merge` 실행 가능

**머지 방식**: `branchStrategy.mergeMethod` 설정에서 읽기 (기본값 `merge`), `merge` / `squash` / `rebase` 지원.

### 4.2.4 스마트 개발 (`/req:do`)

최적화, 리팩토링, 업그레이드 등 요구사항 문서가 필요 없는 작업에:

```
/req:do 주문 조회 성능 최적화
/req:do 사용자 서비스 레이어 리팩토링
/req:do Go 1.23 업그레이드
/req:do 에러 코드 포맷 통일
```

AI 자동 처리:
1. **의도 분석** — 타입 (최적화/리팩토링/업그레이드/규칙/소기능/수정) 과 규모 판단
2. **코드 검색** — 관련 파일 위치 파악, 수정 플랜 생성
3. **플랜 확인** — 사용자 확인 후 브랜치 생성 (`improve/` / `feat/` / `fix/` 는 타입으로 자동 선택)
4. **수정 실행** — 플랜대로 코드 수정

규모가 커지면 `/req:new-quick` 이나 `/req:new` 로 전환을 제안합니다.

**`/req:fix` 와의 차이:**
- `/req:fix` — 버그 수정 전용, AI 가 근본 원인 분석
- `/req:do` — 버그가 아닌 경우 (최적화/리팩토링/업그레이드), AI 가 의도 분석 후 플로우 선택

### 4.3 개발 이어가기

중단 후 재진입 시 진행 상태를 복원:

```
/req:dev REQ-001
```

`--reset` 추가로 구현 플랜 재생성:

```
/req:dev REQ-001 --reset
```

### 4.4 규범 커밋

개발 중 규범 커밋 사용, 요구사항 번호 자동 연결:

```
/req:commit
```

AI 가 변경 내용을 분석하여 Conventional Commits 형식 메시지 생성:

```
feat: 포인트 규칙 CRUD API 구현 (REQ-001)
```

---

## 5. 테스트 단계

### 5.1 종합 테스트

```
/req:test
```

회귀 테스트 + 신규 기능 테스트 포함, 상태가 테스트 중 으로 전환됩니다.

### 5.2 단계별 테스트

```
/req:test_regression    # 기존 자동화 테스트 실행, 회귀 리포트 생성
/req:test_new           # 신규 기능용 테스트 케이스 작성 (UT/API/E2E)
```

---

## 6. 완료 및 아카이브

```
/req:done
```

플로우:
1. 테스트 완료 상태 확인
2. 완료 요약 표시 (기능 포인트, 테스트 포인트, 파일 통계, 타임라인)
3. 확인 후 아카이브: `active/REQ-001-*.md` → `completed/`
4. PRD 인덱스 업데이트
5. 개발 브랜치 머지 리마인드

---

## 7. 조회 & 관리

### 7.1 요구사항 리스트

```
/req                              # 전체 리스트
/req --type=백엔드                 # 타입 필터
/req --module=사용자               # 모듈 필터
/req --type=프론트엔드 --module=사용자
```

### 7.2 상세 조회

```
/req:show REQ-001     # 전체 내용 읽기 (읽기 전용)
/req:status REQ-001   # 상태와 진척도
```

### 7.3 편집

```
/req:edit REQ-001
```

---

## 8. 모듈 관리

모듈은 기능 도메인별 문서로, AI 가 컨텍스트를 이해하는 데 도움을 줍니다.

```
/req:modules                  # 모든 모듈 리스트
/req:modules new 사용자        # 사용자 모듈 문서 생성
/req:modules show 사용자       # 모듈 상세 조회
```

모듈 문서 내용: 책임 범위, 핵심 기능, 데이터 모델, API 개요, 주요 파일 경로.

---

## 9. PRD 관리

PRD 는 프로젝트 단위 문서로 프로젝트당 한 개입니다.

```
/req:prd                      # PRD 상태 개요, 섹션 채움 분석
/req:prd-edit                 # PRD 편집, AI 보조
/req:prd-edit 제품 개요       # 특정 섹션 편집
```

PRD 의 "요구사항 추적" 섹션은 자동 유지보수됩니다:
- `/req:new` 시 행 추가
- `/req:done` 시 상태 및 완료일 업데이트

---

## 10. 버전 관리

### 10.1 릴리즈 노트 생성

```
/req:changelog v1.2.0                          # 범위 자동 감지
/req:changelog v1.2.0 --from=v1.1.0 --to=HEAD  # 범위 지정
```

AI 가 Git 커밋 기록을 분류하여 구조화된 Changelog 를 생성합니다.

### 10.2 빠른 수정 승격

QUICK 진행 중 범위가 커지면 정식 요구사항으로 승격:

```
/req:upgrade QUICK-003
```

---

## 11. 크로스 레포 협업

프론트엔드/백엔드 레포가 분리된 프로젝트에 적합.

### 메인 레포 (백엔드)

```
# 프로젝트 초기화
/req:init my-saas

# 요구사항 정상 생성 및 관리
/req:new 사용자 포인트-백엔드 --type=백엔드
```

### 연결된 레포 (프론트엔드)

```
# 같은 프로젝트에 바인딩
/req:use my-saas

# 요구사항 조회 가능 (읽기 전용)
/req
/req:show REQ-001

# 요구사항 기반 개발 가능 (캐시에서 읽기)
/req:dev REQ-002
```

연결된 레포의 역할은 `readonly`:
- 요구사항 조회 및 읽기 가능
- 완료된 요구사항 기반 개발 가능
- 요구사항 생성/편집/상태 변경 불가

### 11.1 스펙 문서 공유

메인 레포는 스펙 문서 (데이터 타입 정의, API 계약, 에러 코드 등) 를 만들 수 있고, 읽기 전용 레포는 실시간으로 조회 가능합니다:

**메인 레포 (백엔드):**

```
/req:specs new 주문 데이터 타입     # 스펙 문서 생성
/req:specs edit order-types         # 편집
/req:specs                          # 모든 스펙 리스트
```

**읽기 전용 레포 (프론트엔드):**

```
/req:specs                          # 스펙 리스트 조회
/req:specs show order-types         # 주문 데이터 타입 정의 조회
```

스펙 문서는 `docs/requirements/specs/` 에 저장되며 캐시로 자동 동기화됩니다. 백엔드 수정 후 프론트엔드가 다음에 조회하면 최신 버전을 보게 됩니다.

주요 용도:
- 백엔드 데이터 타입 정의 → 프론트엔드 필드 정의 참조
- 공통 에러 코드 규칙 → 프론트/백엔드 각각 구현
- API 계약 → 프론트/백엔드 일관성 유지

---

## 12. 전체 플로우 다이어그램

```
                    요구사항 생성
                /req:new <제목>
                      │
                      ▼
               ┌─────────────┐
               │  📝 초안     │ ← /req:edit
               └──────┬──────┘
                      │ /req:review
                      ▼
               ┌─────────────┐
               │ 👀 리뷰 대기 │
               └──────┬──────┘
                      │ /req:review pass
                      ▼
               ┌─────────────┐
               │ ✅ 리뷰 통과 │
               └──────┬──────┘
                      │ /req:dev (브랜치 자동 생성)
                      ▼
               ┌─────────────┐
               │  🔨 개발 중  │ ← /req:commit
               │             │ ← /req:pr
               │             │ ← /req:review-pr review
               │             │ ← /req:review-pr merge
               └──────┬──────┘
                      │ /req:test
                      ▼
               ┌─────────────┐
               │ 🧪 테스트 중 │
               └──────┬──────┘
                      │ /req:done (머지 리마인드)
                      ▼
               ┌─────────────┐
               │  🎉 완료     │ → completed/ 로 아카이브
               └─────────────┘
```

---

## 13. 자연어 & 원클릭 모드

### 13.1 자연어 지시

슬래시 커맨드를 외울 필요 없이, 자연어로 의도를 설명하면 플러그인이 자동 매핑합니다.

**요구사항 문서**

```
요구사항 생성: 사용자 포인트 관리             → /req:new 사용자 포인트 관리
백엔드 요구사항 추가, 주문 내보내기           → /req:new 주문 내보내기 --type=백엔드
025 요구사항 수정, 내보내기 기능 추가         → /req:edit REQ-025
```

**수정 & 개발 (문서 없음)**

```
로그인 타임아웃 버그 고쳐                     → /req:fix 로그인 타임아웃
#42 버그 수정                                 → /req:fix --from-issue=#42
주문 쿼리 성능 최적화                         → /req:do 주문 쿼리 성능 최적화
사용자 서비스 레이어 리팩토링                 → /req:do 사용자 서비스 레이어 리팩토링
Go 1.23 으로 업그레이드                       → /req:do Go 1.23 으로 업그레이드
페이지네이션 기본값 빠르게 수정               → /req:new-quick 페이지네이션 기본값
```

**상태 전이** (번호 필수)

```
025 개발 시작                                 → /req:dev REQ-025
025 테스트 시작                               → /req:test REQ-025
025 리뷰 통과                                 → /req:review pass
025 리뷰 반려                                 → /req:review reject
025 완료 / 025 끝났어                          → /req:done REQ-025
```

**버전 & PR**

```
규범 커밋                                     → /req:commit
PR 생성                                       → /req:pr
PR 리뷰                                       → /req:review-pr review
PR 코멘트 조회                                → /req:review-pr fetch-comments
PR 머지                                       → /req:review-pr merge
```

**Git 플랫폼 URL 직접 붙여넣기** (issue / PR 자동 인식)

```
owner/repo/issues/169 수정                    → /req:fix --from-issue=#169
owner/repo/issues/12 로 요구사항 생성         → /req:new --from-issue=#12
owner/repo/pulls/158 리뷰                     → /req:review-pr review (PR 브랜치로 먼저 전환 필요)
```

동사 없이 URL 만 붙여넣으면 작업 선택 메뉴가 표시됩니다.

**번호 파싱 규칙**

| 입력 | 파싱 결과 |
|------|-----------|
| `REQ-025` / `REQ025` | REQ-025 |
| `QUICK-003` / `QUICK003` | QUICK-003 |
| 숫자 `025` / `25` | REQ-025 (3 자리로 zero-padding) |
| `#42` / `issue 42` | `--from-issue=#42` |

**트리거되지 않는 경우**

- 조회 / 표시: "025 보여줘" 는 `/req:show` 로 라우팅
- 논의 / 질문: "이 버그 어떻게 고쳐?", "리팩토링해야 하나?"
- 필수 정보 누락: 번호 없는 "요구사항 수정", 대상 없는 "최적화", 번호 없는 "완료"
- 슬래시 커맨드로 시작하는 메시지 (`/req:`, `/pm:`, `/api:`)
- 다른 레포를 가리키는 URL (`git remote` 와 불일치)

### 13.2 원클릭 수정 (`--auto`)

`/req:fix --auto` 는 모든 확인 인터랙션을 건너뛰고 commit → push → PR 까지 자동 연결합니다.

**트리거 방식**

```
/req:fix 로그인 타임아웃 --auto                # 명시적
Excel 내보내기 인코딩 수정, 확인 불필요        # 자연어
로그인 타임아웃 원클릭 수정                    # 자연어
바로 고치고 PR 올려                            # 자연어
#42 자동 수정                                  # 자연어 + issue
```

자연어 트리거: `원클릭 수정` / `자동 수정` / `고치고 바로 PR` / `확인 불필요` / `묻지 마` / `끝까지 돌려` / 중국어 표현 등.

**자동으로 건너뛰는 항목**

| 확인 포인트 | 건너뛰는 방식 |
|-------------|---------------|
| 수정 플랜 확인 | 커맨드에 내장 |
| `git commit` 직전 네이티브 확인 다이얼로그 | `.claude/.req-auto` 마커 (Hook 통과) |
| `/req:commit` 인터랙티브 타입 선택 | AI 가 "수정" 으로 자동 추론 |
| `--from-issue` 의 issue 종료 확인 | 기본적으로 종료 |
| `/req:pr` 생성 후 브랜치 정리 확인 | 기본적으로 유지 |
| commit → push → PR 수동 연결 | 자동 실행 |

**건너뛸 수 없는 항목** (Claude Code harness 레벨, 로컬에서 설정 필요)

- 처음 Bash / Write / Edit 툴을 호출할 때의 권한 확인
- Plan Mode approval (Plan Mode 활성화 시)

**건너뛰지 않는 항목** (안전 레드라인)

- 보호 브랜치 (`main` / `master` / `develop`) 에서의 커밋 — 개발 브랜치로 먼저 전환 필요
- AI 의 실제 코드 분석 및 수정 (핵심 실행, 확인이 아님)

**내부 메커니즘**

`--auto` 시작 시 `.claude/.req-auto` 마커 파일을 생성 (mtime 10 분 TTL). PreToolUse confirm hook 은 유효한 마커를 감지하면 바로 통과시키고, `git commit` 확인 다이얼로그를 수동 확인하지 않아도 됩니다. 플로우 종료 시 마커 삭제; 비정상 종료 시 TTL 이 자동으로 만료되어 마커가 통과를 허용하지 않게 됩니다.

`.claude/.req-auto` 는 `.gitignore` 에 포함되어 있어 커밋되지 않습니다.

**대표 워크플로우**

```
사용자: Excel 내보내기 인코딩 수정, 확인 불필요
   ↓
AI:    🧠 인식: /req:fix Excel 내보내기 인코딩 --auto
       ⚙️ --auto 로 건너뛰는 항목: [능력 리스트]
       🔒 건너뛸 수 없음: [harness 권한]
       🛑 건너뛰지 않음: [보호 브랜치, 실제 코드 수정]
       실행할까요?
   ↓
진단 → 코드 수정 → git commit → git push → PR 생성
```

---

## 커맨드 치트 시트

| 시나리오 | 커맨드 |
|----------|--------|
| 요구사항 브라우징 | `/req` |
| 정식 요구사항 생성 | `/req:new <제목> --type=백엔드` |
| 빠른 수정 (문서 있음) | `/req:new-quick <제목>` |
| 라이트 수정 (문서 없음) | `/req:fix <설명>` |
| 스마트 개발 (최적화/리팩토링) | `/req:do <설명>` |
| 편집 | `/req:edit` |
| 리뷰 제출 | `/req:review` |
| 리뷰 승인 | `/req:review pass` |
| 개발 시작 | `/req:dev` |
| 커밋 | `/req:commit` |
| PR 생성 | `/req:pr` |
| AI 코드 리뷰 | `/req:review-pr review` |
| PR 머지 | `/req:review-pr merge` |
| 테스트 실행 | `/req:test` |
| 아카이브 | `/req:done` |
| PRD 조회 | `/req:prd` |
| Changelog 생성 | `/req:changelog v1.0.0` |
| 브랜치 전략 설정 | `/req:branch init` |
| 브랜치 상태 조회 | `/req:branch status` |
| 핫픽스 | `/req:branch hotfix <설명>` |
| 재초기화 | `/req:init my-project --reinit` |
| 캐시 재구축 | `/req:cache rebuild` |
| 스펙 문서 조회 | `/req:specs show <이름>` |
| 스펙 문서 생성 | `/req:specs new <이름>` |
