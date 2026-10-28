#!/usr/bin/env bash
# Maintain and verify a module's SHA256SUMS.txt.
#
#   scripts/checksums.sh generate <module-dir>   rewrite <module-dir>/SHA256SUMS.txt from the files on disk
#   scripts/checksums.sh verify   <module-dir>   check the files on disk against <module-dir>/SHA256SUMS.txt
#
# The manifest describes the release package, so it also lists the compiled
# .ex5 binaries. Those are published in GitHub Releases and are not committed to
# git. `verify` therefore accepts a missing .ex5 as long as its hash is recorded
# in BUILDINFO.json; every other listed file must exist and match, and every
# file on disk must be listed.
set -euo pipefail

mode="${1:-}"
module="${2:-}"
if [[ -z "$mode" || -z "$module" || ! -d "$module" ]]; then
  echo "usage: $0 generate|verify <module-dir>" >&2
  exit 2
fi
cd "$module"

case "$mode" in
  generate)
    find . -type f ! -name SHA256SUMS.txt ! -name '*.zip' -print0 \
      | sed -z 's|^\./||' \
      | LC_ALL=C sort -z \
      | xargs -0 sha256sum \
      | sed 's/^\([0-9a-f]\{64\}\) \*/\1  /' > SHA256SUMS.txt   # Windows coreutils marks binary mode with '*'
    echo "wrote $module/SHA256SUMS.txt ($(wc -l < SHA256SUMS.txt) entries)"
    ;;
  verify)
    status=0
    while read -r hash path; do
      path="${path#\*}"
      [[ -n "$path" ]] || continue
      if [[ -f "$path" ]]; then
        actual=$(sha256sum "$path" | cut -d' ' -f1)
        if [[ "$actual" != "$hash" ]]; then
          echo "MISMATCH     $path"
          status=1
        fi
      elif [[ "$path" == *.ex5 ]]; then
        if ! grep -q "\"sha256\": \"$hash\"" BUILDINFO.json; then
          echo "NO-BUILDINFO $path (binary hash not recorded in BUILDINFO.json)"
          status=1
        fi
      else
        echo "MISSING      $path"
        status=1
      fi
    done < SHA256SUMS.txt
    while IFS= read -r -d '' f; do
      f="${f#./}"
      if ! grep -q "  $f\$" SHA256SUMS.txt; then
        echo "UNLISTED     $f"
        status=1
      fi
    done < <(find . -type f ! -name SHA256SUMS.txt ! -name '*.zip' -print0)
    if [[ $status -eq 0 ]]; then
      echo "OK: $module/SHA256SUMS.txt verified ($(wc -l < SHA256SUMS.txt) entries)"
    fi
    exit $status
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
