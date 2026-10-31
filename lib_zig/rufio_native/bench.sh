#!/usr/bin/env bash
# rufio_search と ripgrep の速度比較（ウォームキャッシュ、各 10 回の中央値）
# 使い方: ./bench.sh [DIR] [QUERY...]
set -euo pipefail
cd "$(dirname "$0")"

DIR=${1:-$(cd ../.. && pwd)}
shift || true
QUERIES=("$@")
[ ${#QUERIES[@]} -eq 0 ] && QUERIES=(rb_define_method zzqxj_not_found "the" "日本語")
RUNS=${RUNS:-10}

[ -x ./rufio_search ] || make rufio_search >/dev/null

measure() {
  python3 - "$RUNS" "$@" <<'EOF'
import subprocess, sys, time, statistics
runs = int(sys.argv[1]); cmd = sys.argv[2:]
for _ in range(2):
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
times = []
for _ in range(runs):
    t = time.perf_counter()
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    times.append((time.perf_counter() - t) * 1000)
print(f"median {statistics.median(times):8.1f} ms   min {min(times):8.1f} ms")
EOF
}

echo "corpus: $DIR ($(find "$DIR" -type f | wc -l | tr -d ' ') files, $(du -sh "$DIR" | cut -f1))"
for q in "${QUERIES[@]}"; do
  hits=$(./rufio_search "$q" "$DIR" | wc -l | tr -d ' ')
  echo "== query: $q ($hits lines)"
  printf '  rufio_search : '; measure ./rufio_search "$q" "$DIR"
  printf '  rg -uu -i -F : '; measure rg -uu -i -F -n "$q" "$DIR"
done
