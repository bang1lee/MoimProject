# Obsidian LLM Wiki 자동 동기화 셋업

이 레포(`bang1lee/MoimProject`)는 `bang1lee/obsidian-llm-wiki`의
`projects/MoimProject/` 폴더로 콘텐츠를 자동 동기화합니다.

## 동작 방식

- 트리거: `main` 브랜치 push, 또는 Actions 탭에서 수동 실행 (`workflow_dispatch`)
- 동기화 위치: `bang1lee/obsidian-llm-wiki/projects/MoimProject/`
- 생성 결과:
  - `MoimProject.md` — Obsidian 인덱스 노트 (frontmatter + 위키링크)
  - `notes/*.md` — 각 HTML 페이지를 pandoc으로 변환한 마크다운 노트
  - `raw/` — 원본 레포 전체 미러
  - `assets/images/`, `assets/music/` — 에셋 사본

## 필요한 일회성 셋업: `WIKI_SYNC_TOKEN` 시크릿 등록

cross-repo push에는 기본 `GITHUB_TOKEN`으로는 권한이 부족합니다.
`bang1lee/obsidian-llm-wiki`에 쓰기 권한이 있는 토큰을 시크릿으로 등록해야 합니다.

### 1) Personal Access Token (Fine-grained, 권장) 발급

1. https://github.com/settings/personal-access-tokens/new 접속
2. 설정값
   - **Token name**: `moim-to-wiki-sync`
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

- **자동**: `main`에 push하면 자동 실행
- **수동**: GitHub > Actions > *Sync to Obsidian LLM Wiki* > *Run workflow*
  - 옵션으로 커스텀 커밋 메시지를 지정 가능

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
