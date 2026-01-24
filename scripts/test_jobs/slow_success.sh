#!/bin/bash
# 成功する長時間ジョブ（10秒）

echo "Starting slow job..."
for i in {1..10}; do
    echo "Processing step $i/10..."
    sleep 1
done
echo "Job completed successfully!"
exit 0
