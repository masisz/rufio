#!/bin/bash
# とても長いジョブ（30秒）

echo "Starting very slow job..."
echo "This will take about 30 seconds."
echo ""

for i in {1..30}; do
    percent=$((i * 100 / 30))
    bar=""
    for j in $(seq 1 $((i / 3))); do bar="${bar}█"; done
    for j in $(seq 1 $((10 - i / 3))); do bar="${bar}░"; done
    printf "\r[%s] %d%% - %d/30 seconds" "$bar" "$percent" "$i"
    sleep 1
done

echo ""
echo "Very slow job completed!"
exit 0
