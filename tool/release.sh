#!/usr/bin/env bash
# GitHub Release 에 안드로이드 APK 를 올린다.
#
#   tool/release.sh            # pubspec 의 version 으로 태그·릴리스
#   tool/release.sh --dry-run  # 빌드까지만
#
# arm64 전용 APK 하나만 올린다. universal 은 90MB 인데 실제 설치 기기는 전부
# arm64 라 세 배 크기를 내려받을 이유가 없다 (v1.1.0 은 universal 이었다).
# 릴리스 노트는 에디터가 열리므로 그 자리에서 적는다.
set -euo pipefail

cd "$(dirname "$0")/.."
FLUTTER=${FLUTTER:-flutter}

version=$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' pubspec.yaml)
[[ -n "$version" ]] || { echo "pubspec.yaml 에서 version 을 못 읽었습니다" >&2; exit 1; }
tag="v$version"
apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
out="build/GotDoor-$version.apk"

dry_run=0; [[ "${1:-}" == "--dry-run" ]] && dry_run=1

if (( ! dry_run )) && [[ -n "$(git status --porcelain)" ]]; then
  echo "작업 트리가 깨끗하지 않습니다. 먼저 커밋하세요." >&2
  exit 1
fi

echo "== $tag 빌드 (arm64)"
"$FLUTTER" build apk --release --split-per-abi --target-platform android-arm64 \
  --android-skip-build-dependency-validation
cp "$apk" "$out"
echo "SHA-256 $(shasum -a 256 "$out" | cut -c1-64)"
echo "== $out ($(du -h "$out" | cut -f1))"

(( dry_run )) && exit 0

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "태그 $tag 가 이미 있습니다. pubspec 의 version 을 올리세요." >&2
  exit 1
fi
git tag -a "$tag" -m "GotDoor $version"
git push origin "$tag"
gh release create "$tag" "$out" --title "GotDoor $version" --notes-file <(
  printf 'Android APK (arm64-v8a). 설치는 APK 를 내려받아 여는 것으로 끝납니다.\n\n'
  printf '## 바뀐 것\n- \n\n'
  printf '## 서명\n디버그 키로 서명돼 있습니다. 같은 빌드 머신에서 만든 이전 설치 위에 덮어씌워집니다.\n\n'
  printf 'SHA-256 `%s`\n' "$(shasum -a 256 "$out" | cut -c1-64)"
) --draft
echo "== 초안을 만들었습니다. 노트를 채우고 공개하세요:"
gh release view "$tag" --json url --jq .url
