#!/usr/bin/env bash
#
# Builds and tests what `flight new` actually emits, for every tier.
#
# CI/verify-templates.sh checks the templates. This checks the *generated*
# project, which is a different artifact: the CLI renames the target, rewrites
# manifest strings, import statements, and paths, and any of that can be
# subtly wrong in a way the templates themselves would never reveal.
#
#   ./CI/verify-generated-projects.sh          # all tiers
#   ./CI/verify-generated-projects.sh basics   # one
#
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product flight >/dev/null
cli="$(swift build --product flight --show-bin-path)/flight"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

tiers=("$@")
[ ${#tiers[@]} -eq 0 ] && tiers=(skeleton basics demo)

status=0
for tier in "${tiers[@]}"; do
  echo "──────── $tier ────────"
  name="Generated${tier^}"
  "$cli" new "$name" --tier "$tier" --path "$scratch/$tier" >/dev/null

  # The generated project must contain no trace of the template's own target
  # name as an identifier — only in prose.
  if grep -rn '"App"\|import App\b\|Sources/App/\|AppTests' "$scratch/$tier" >/dev/null 2>&1; then
    echo "  ✘ generated project still refers to the template target 'App'"
    grep -rn '"App"\|import App\b\|Sources/App/\|AppTests' "$scratch/$tier" | head -3
    status=1
    continue
  fi

  if (cd "$scratch/$tier" && swift build 2>&1 | tail -2) \
     && (cd "$scratch/$tier" && swift test 2>&1 | tail -2); then
    echo "  ✔ $tier builds and tests as $name"
  else
    echo "  ✘ $tier FAILED"
    status=1
  fi
done

exit $status
