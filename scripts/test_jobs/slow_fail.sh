#!/bin/bash
# 失敗する長時間ジョブ（7秒後に失敗）

echo "Starting job that will fail..."
for i in {1..7}; do
    echo "Working on step $i..."
    sleep 1
done
echo "ERROR: Something went wrong!"
exit 1
