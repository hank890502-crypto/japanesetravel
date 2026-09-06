#!/bin/zsh
# 在 Mac 上對一張菜單照片跑 App 同樣的 OCR + 版面分析。
#   用法：tools/ocr-debug.sh samples/menu1.jpg
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/JapanTravelAssistant"
BUILD="${TMPDIR:-/tmp}/ocr-debug-build"
mkdir -p "$BUILD"
cp "$ROOT/tools/ocr-debug.swift" "$BUILD/main.swift"
swiftc -O -o "$BUILD/ocr-debug" \
  "$BUILD/main.swift" \
  "$SRC/Core/Models/RecognizedTextBlock.swift" \
  "$SRC/Core/Utilities/PriceParser.swift" \
  "$SRC/Core/Utilities/MenuLayoutAnalyzer.swift" \
  "$SRC/Core/Utilities/MenuTranscriptParser.swift" \
  "$SRC/Core/Utilities/KanjiNumberParser.swift" \
  "$SRC/Core/Utilities/PriceFormatter.swift" \
  "$SRC/Core/Models/MenuCandidate.swift" \
  "$SRC/Core/Extensions/String+Extensions.swift" 2>&1 | grep -v "warning:" || true
"$BUILD/ocr-debug" "$@"
