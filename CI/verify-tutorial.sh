#!/usr/bin/env bash
#
# Checks that TUTORIAL.md does not lie.
#
# The previous tutorial in this ecosystem drifted until seven of the nine
# files it told you to create no longer existed. Nothing caught that, because
# prose does not compile. This does the two checks that would have:
#
#   1. every templates/… path it links to exists
#   2. every type and function it names in a code block exists in the tier
#      that stage claims to build
#
set -euo pipefail
cd "$(dirname "$0")/.."

status=0

echo "── linked paths"
# Markdown links and inline references to templates/…
grep -oE 'templates/[A-Za-z0-9_/.-]+' TUTORIAL.md | sed 's/[.,)]*$//' | sort -u | while read -r path; do
  if [ ! -e "$path" ]; then
    echo "  ✘ MISSING  $path"
    exit 1
  fi
done || status=1
[ $status -eq 0 ] && echo "  ✔ all referenced paths exist"

echo "── declared symbols"
# Every `struct X`, `protocol X`, or `func x(` the tutorial shows should exist
# somewhere in the templates. A renamed API in the framework shows up here as
# a tutorial that still names the old one.
missing=0
python3 - <<'PY'
import re, pathlib, sys

tutorial = pathlib.Path("TUTORIAL.md").read_text()
sources = "\n".join(
    p.read_text() for p in pathlib.Path("templates").rglob("*.swift")
)

# Only symbols the tutorial presents as ours, in swift code fences.
blocks = re.findall(r'```swift\n(.*?)```', tutorial, re.S)
symbols = set()
for block in blocks:
    symbols |= set(re.findall(r'\b(?:struct|protocol|final class|enum)\s+([A-Z][A-Za-z0-9_]*)', block))
    symbols |= set(re.findall(r'\bfunc\s+([a-z][A-Za-z0-9_]*)\s*\(', block))

# Names that belong to the framework or to Swift, not to the templates.
external = {
    "Main", "AppModule", "TestModule", "InMemoryUsers",
    "main", "configure", "validate", "up", "down",
}
missing = sorted(s for s in symbols - external if s not in sources)
for name in missing:
    print(f"  ✘ tutorial names '{name}', which no template defines")
sys.exit(1 if missing else 0)
PY
if [ $? -eq 0 ]; then echo "  ✔ every symbol shown is defined in a template"; else status=1; fi
echo "── constructed types"
# The check above only looks at what the tutorial *declares*. It never looked
# at what the tutorial *calls*, which is how a snippet registering
# `PostgresJobCoordinator(...)` shipped while no template could resolve that
# type: a reader copying it got "cannot find PostgresJobCoordinator in scope".
#
# Every framework type the tutorial constructs must appear somewhere in the
# templates — defined there, or used there, which means the package providing
# it is a real dependency of a real project.
python3 - <<'PYCHECK'
import re, pathlib, sys

tutorial = pathlib.Path("TUTORIAL.md").read_text()
haystack = "\n".join(p.read_text() for p in pathlib.Path("templates").rglob("*.swift"))
haystack += "\n" + "\n".join(p.read_text() for p in pathlib.Path("templates").rglob("Package.swift"))

# Swift and Foundation types a reader already has.
stdlib = {
    "Data", "Date", "UUID", "String", "Int", "Double", "Bool", "URL", "Set",
    "Array", "Dictionary", "Duration", "Task", "Error", "Result", "Optional",
    "Logger", "Configuration", "DateComponents", "TimeZone", "Calendar",
    "JSONEncoder", "JSONDecoder", "ByteBuffer", "Character", "Issue",
}

used = set()
for block in re.findall(r'```swift\n(.*?)```', tutorial, re.S):
    for name in re.findall(r'(?<![@.\w])\b([A-Z][A-Za-z0-9_]*)\s*\(', block):
        used.add(name)

missing = sorted(n for n in used - stdlib if n not in haystack)
for name in missing:
    print(f"  ✘ tutorial constructs '{name}', which no template can resolve")
sys.exit(1 if missing else 0)
PYCHECK
if [ $? -eq 0 ]; then echo "  ✔ every constructed type is resolvable"; else status=1; fi


echo "── checkpoint commands"
# Each part must end at a tier, and say so.
for tier in skeleton basics demo; do
  if ! grep -q "You have now built \[\`templates/$tier\`\]" TUTORIAL.md; then
    echo "  ✘ no closing checkpoint for the $tier tier"
    status=1
  fi
done
[ $status -eq 0 ] && echo "  ✔ every part closes on a tier"

exit $status
