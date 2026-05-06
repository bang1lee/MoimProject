# Obsidian LLM Wiki 양방향 자동 동기화 셋업

이 레포(`bang1lee/MoimProject`)는 `bang1lee/obsidian-llm-wiki`의
`projects/MoimProject/` 폴더와 **양방향**으로 자동 동기화됩니다.

## 동작 방식

### 트리거
- `main` 브랜치 push → **forward만** (MoimProject → wiki)
- 매시간 (cron `15 * * * *`) → **양방향** (wiki edits 회수 + forward)
- Actions 탭에서 수동 실행 (`workflow_dispatch`) → 방향 선택 가능 (`forward`/`reverse`/`both`)

### 동기화 매핑
| 방향 | 원본 → 대상 | 범위 |
|---|---|---|
| **Forward** | MoimProject root → `wiki/projects/MoimProject/raw/` | 전체 레포 미러 (`.git`, `.github` 제외) |
| **Reverse** | `wiki/projects/MoimProject/raw/` → MoimProject root | 위와 동일 |

### 부수적 산출물 (forward sync 시 생성)
- `wiki/projects/MoimProject/MoimProject.md` — Obsidian 인덱스 노트 (frontmatter + 위키링크)
- `wiki/projects/MoimProject/notes/*.md` — HTML → pandoc 변환된 마크다운 노트
- `wiki/projects/MoimProject/assets/images/`, `assets/music/` — 에셋 사본 (Obsidian 임베드용)

### 루프 방지
봇이 만드는 commit 메시지에 `[skip ci]` 토큰을 넣어 push 트리거를 차단합니다.
즉, 한쪽 sync가 다른 쪽으로 push해도 그 push가 다시 워크플로우를 trigger하지 않습니다.

### 주의사항 ⚠️
- `notes/*.md`는 **forward sync 때마다 재생성**됩니다. wiki에서 직접 편집하지 마세요 — 덮어써집니다. (그 안에 별도 파일을 만들어 commentary를 쓰는 것은 OK)
- `raw/`와 루트 코드/에셋 파일은 양쪽 모두에서 편집 가능합니다.
- 동시 편집 충돌 시: 매시간 schedule run에서 reverse가 먼저 돌고 forward가 나중에 돌므로, **마지막 push가 살아남습니다**.

## 필요한 일회성 셋업: `WIKI_SYNC_TOKEN` 시크릿 등록

cross-repo push에는 기본 `GITHUB_TOKEN`으로는 권한이 부족합니다.
`bang1lee/obsidian-llm-wiki`에 쓰기 권한이 있는 토큰을 시크릿으로 등록해야 합니다.

### 1) Personal Access Token (Fine-grained, 권장) 발급

양방향 sync는 wiki 레포에 대한 쓰기 권한이 필요합니다. (MoimProject 자체는
워크플로우의 기본 `GITHUB_TOKEN`으로 push 가능 — `permissions: contents: write`로 설정됨)

1. https://github.com/settings/personal-access-tokens/new 접속
2. 설정값
   - **Token name**: `moim-wiki-bisync`
   - **Expiration**: 원하는 기간 (예: 1년)
   - **Repository access**: *Only select repositories* → `bang1lee/obsidian-llm-wiki` 선택
   - **Repository permissions**:
     - `Contents`: **Read and write**
     - `Metadata`: Read-only (자동)
3. *Generate token* → 표시된 토큰 값을 복사 (한 번만 보임)

### 2) 이 레포에 시크릿으로 등록

1. https://github.com/bang1lee/MoimProject/settings/secrets/actions 접속
2. *New repository secret*
   - **Name**: `WIKI_SYNC_TOKEN`
   - **Secret**: 위에서 복사한 토큰 값
3. *Add secret*

### 3) Wiki 레포 존재 확인

`bang1lee/obsidian-llm-wiki` 레포가 이미 존재하고 default branch에
최소 1커밋이 있어야 합니다 (빈 레포면 checkout이 실패할 수 있음).
없다면 GitHub에서 새 레포 생성 후 README 한 줄로 초기화하세요.

## 동기화 트리거 방법

- **자동 (forward only)**: `main`에 push하면 즉시 forward sync 실행
- **자동 (양방향)**: 매시간 :15분에 schedule run — wiki edits를 먼저 끌어오고 forward 진행
- **수동**: GitHub > Actions > *Sync MoimProject <-> Obsidian LLM Wiki* > *Run workflow*
  - `direction`: `both` / `forward` / `reverse` 선택
  - `message`: 커스텀 커밋 메시지 (선택)

## 트러블슈팅

| 에러 | 원인 | 해결 |
|---|---|---|
| `Repository not found` (checkout 단계) | 토큰에 wiki 레포 권한 없음 | PAT의 Repository access 재확인 |
| `Permission denied` (push 단계) | 토큰의 Contents 쓰기 권한 누락 | PAT 권한을 `Read and write`로 |
| `No changes to sync` | 동기화할 변경 없음 (정상) | — |
| 워크플로우 자체가 안 돌아감 | Actions 비활성화 | Settings > Actions > Allow all actions |

## 파일 구조 참고

```
.github/
├── SYNC_SETUP.md                    # 이 문서
├── scripts/
│   └── sync-to-wiki.sh              # 변환 + 미러 로직
└── workflows/
    └── sync-obsidian-wiki.yml       # Actions 워크플로우
```
