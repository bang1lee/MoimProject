#!/usr/bin/env bash
# Sync MoimProject content into the Obsidian LLM Wiki repo.
# Mirrors raw files and generates Obsidian-friendly markdown notes.

set -euo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${WIKI_DIR:?WIKI_DIR is required}"
: "${TARGET_SUBDIR:?TARGET_SUBDIR is required}"

SOURCE_REPO="${SOURCE_REPO:-bang1lee/MoimProject}"
SOURCE_SHA="${SOURCE_SHA:-unknown}"
SOURCE_REF="${SOURCE_REF:-main}"

TARGET_DIR="${WIKI_DIR}/${TARGET_SUBDIR}"
RAW_DIR="${TARGET_DIR}/raw"
NOTES_DIR="${TARGET_DIR}/notes"
ASSETS_DIR="${TARGET_DIR}/assets"

now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
short_sha="${SOURCE_SHA:0:7}"

mkdir -p "${TARGET_DIR}" "${RAW_DIR}" "${NOTES_DIR}" "${ASSETS_DIR}"

echo "==> Mirroring raw files into ${RAW_DIR}"
rsync -a --delete \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='.DS_Store' \
  --exclude='node_modules/' \
  "${SOURCE_DIR}/" "${RAW_DIR}/"

echo "==> Mirroring assets (images/, music/) into ${ASSETS_DIR}"
rsync -a --delete \
  --exclude='.DS_Store' \
  "${SOURCE_DIR}/images/" "${ASSETS_DIR}/images/" 2>/dev/null || true
rsync -a --delete \
  --exclude='.DS_Store' \
  "${SOURCE_DIR}/music/" "${ASSETS_DIR}/music/" 2>/dev/null || true

# Extract <title> from HTML for note frontmatter
extract_title() {
  local file="$1" fallback="$2"
  local title
  title=$(awk 'BEGIN{IGNORECASE=1} /<title>/{ sub(/.*<title[^>]*>/,""); sub(/<\/title>.*/,""); print; exit }' "$file" 2>/dev/null || true)
  if [ -z "${title}" ]; then
    title="${fallback}"
  fi
  printf '%s' "${title}"
}

# Convert one HTML file into a markdown note with frontmatter
html_to_note() {
  local html="$1" out="$2" rel_html="$3"
  local name title
  name="$(basename "${html}" .html)"
  title="$(extract_title "${html}" "${name}")"

  {
    echo "---"
    echo "title: \"${title//\"/\\\"}\""
    echo "tags: [project, moim, auto-sync]"
    echo "source_repo: ${SOURCE_REPO}"
    echo "source_html: ${rel_html}"
    echo "source_commit: ${SOURCE_SHA}"
    echo "synced_at: ${now_utc}"
    echo "---"
    echo
    echo "# ${title}"
    echo
    echo "> 자동 동기화된 노트 — 원본 HTML: \`${rel_html}\`"
    echo
  } > "${out}"

  if pandoc -f html -t gfm --wrap=none "${html}" >> "${out}" 2>/dev/null; then
    echo "  - converted: ${html} -> ${out}"
  else
    {
      echo
      echo "_(HTML → Markdown 변환 실패. raw 파일을 직접 참고하세요.)_"
    } >> "${out}"
    echo "  - fallback (no conversion): ${html}"
  fi
}

echo "==> Generating Obsidian notes for HTML pages"
# Clear stale generated notes (but keep the dir)
find "${NOTES_DIR}" -type f -name '*.md' -delete

shopt -s nullglob
project_links=()
for html in "${SOURCE_DIR}/projects/"*.html; do
  name="$(basename "${html}" .html)"
  out="${NOTES_DIR}/${name}.md"
  html_to_note "${html}" "${out}" "../raw/projects/${name}.html"
  title="$(extract_title "${html}" "${name}")"
  # Escape pipes in title so Obsidian wikilink alias parses correctly
  safe_title="${title//|/\\|}"
  project_links+=("- [[notes/${name}|${safe_title}]]")
done

# Hub page
hub_link=""
if [ -f "${SOURCE_DIR}/index.html" ]; then
  out="${NOTES_DIR}/hub.md"
  html_to_note "${SOURCE_DIR}/index.html" "${out}" "../raw/index.html"
  hub_link="- [[notes/hub|Portfolio Hub]]"
fi
shopt -u nullglob

echo "==> Writing index note: ${TARGET_DIR}/MoimProject.md"
INDEX_FILE="${TARGET_DIR}/MoimProject.md"
{
  echo "---"
  echo "title: MoimProject"
  echo "tags: [project, portfolio, moim, index, auto-sync]"
  echo "source_repo: ${SOURCE_REPO}"
  echo "source_branch: ${SOURCE_REF}"
  echo "source_commit: ${SOURCE_SHA}"
  echo "synced_at: ${now_utc}"
  echo "---"
  echo
  echo "# MoimProject"
  echo
  echo "포트폴리오 허브 레포 자동 동기화 인덱스."
  echo
  echo "- 원본: [\`${SOURCE_REPO}\`](https://github.com/${SOURCE_REPO})"
  echo "- 커밋: [\`${short_sha}\`](https://github.com/${SOURCE_REPO}/commit/${SOURCE_SHA})"
  echo "- 브랜치: \`${SOURCE_REF}\`"
  echo "- 동기화 시각: \`${now_utc}\`"
  echo
  echo "## Hub"
  echo
  if [ -n "${hub_link}" ]; then
    echo "${hub_link}"
  else
    echo "_(index.html 없음)_"
  fi
  echo
  echo "## Projects"
  echo
  if [ ${#project_links[@]} -eq 0 ]; then
    echo "_(projects/ 폴더에 HTML 파일이 없습니다)_"
  else
    printf '%s\n' "${project_links[@]}"
  fi
  echo
  echo "## Assets"
  echo
  echo "- 이미지: \`assets/images/\`"
  echo "- 음원: \`assets/music/\`"
  echo
  echo "## Raw Mirror"
  echo
  echo "원본 파일 전체 미러: \`raw/\`"
  echo
  echo "---"
  echo
  echo "_이 문서는 \`.github/workflows/sync-obsidian-wiki.yml\` 워크플로우가 자동 생성합니다. 직접 수정하지 마세요._"
} > "${INDEX_FILE}"

echo "==> Sync complete. Target: ${TARGET_DIR}"
