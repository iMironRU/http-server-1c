#!/bin/bash
# release.sh — локальная сборка cfe + GitHub Release (macOS/Linux).
# Использование:
#   ./tools/release.sh <version> [<base-ut-path>]
# Пример:
#   ./tools/release.sh 0.2.0 /Users/mal/bases/dev_bsp_v2

set -euo pipefail

VERSION="${1:?Usage: $0 <version> [<base-ut-path>]}"
BASE_UT="${2:-/Users/mal/bases/dev_bsp_v2}"
EXT_NAME="http_HTTPСервер"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PLATFORM="${PLATFORM:-/opt/1cv8/8.3.27.2130/1cv8}"
test -x "$PLATFORM" || { echo "1cv8 не найден: $PLATFORM"; exit 1; }

[ -d "$BASE_UT" ] || { echo "База УТ не найдена: $BASE_UT"; exit 1; }
command -v gh >/dev/null || { echo "gh CLI не установлен"; exit 1; }

echo "▶ Проверка git"
if [ -n "$(git status --porcelain 2>&1)" ]; then
    echo "  ✗ Рабочая копия грязная:"
    git status --short
    exit 1
fi

echo "▶ Установка версии $VERSION в Configuration.xml"
CFG="src/cfe/Configuration.xml"
OLD_VER=$(grep -oE '<Version>[^<]+</Version>' "$CFG" | head -1 | sed 's/<[^>]*>//g')
sed -i '' "s|<Version>${OLD_VER}</Version>|<Version>${VERSION}</Version>|" "$CFG"
echo "  ✓ $OLD_VER → $VERSION"

echo "▶ LoadConfigFromFiles в $BASE_UT"
LOG=$(mktemp)
"$PLATFORM" DESIGNER "/F$BASE_UT" \
    /LoadConfigFromFiles "$REPO_ROOT/src/cfe" -Extension "$EXT_NAME" \
    /UpdateDBCfg /DisableStartupDialogs "/Out$LOG" >/dev/null
echo "  ✓ загружено"

echo "▶ DumpCfg"
OUT="build/${EXT_NAME}-${VERSION}.cfe"
mkdir -p build
LOG=$(mktemp)
"$PLATFORM" DESIGNER "/F$BASE_UT" \
    /DumpCfg "$REPO_ROOT/$OUT" -Extension "$EXT_NAME" \
    /DisableStartupDialogs "/Out$LOG" >/dev/null
SIZE=$(du -k "$OUT" | cut -f1)
echo "  ✓ $OUT (${SIZE} КБ)"

echo "▶ git commit + tag"
git add "$CFG"
git commit -m "release: $VERSION" >/dev/null
git tag "v$VERSION" -m "Release $VERSION"
git push origin HEAD
git push origin "v$VERSION"
echo "  ✓ тег v$VERSION запушен"

echo "▶ gh release create"
NOTES_FILE=$(mktemp)
{
    echo "## v$VERSION"
    echo
    git log "v${VERSION}~1..v${VERSION}" --oneline 2>/dev/null | sed 's/^/- /' || \
        git log -10 --oneline | sed 's/^/- /'
} > "$NOTES_FILE"

gh release create "v$VERSION" "$OUT" \
    --title "v$VERSION" \
    --notes-file "$NOTES_FILE"
echo "  ✓ Release v$VERSION опубликован"
echo
echo "Дальше — в Конфигураторе УТ замени константу http_URLGitHubРепозиторий"
echo "на 'iMironRU/http-server-1c' (если ещё не сделано), потом в обработке"
echo "http_СамодиагностикаHTTPСервера нажми 'Проверить обновление'."
