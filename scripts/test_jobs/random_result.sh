#!/bin/bash
# ランダムに成功・失敗するジョブ（5-15秒）

duration=$((RANDOM % 11 + 5))
result=$((RANDOM % 2))

echo "Random job started"
echo "Duration: ${duration} seconds"
echo "Will $([ $result -eq 0 ] && echo 'succeed' || echo 'fail')"
echo ""

for i in $(seq 1 $duration); do
    echo "Tick $i..."
    sleep 1
done

if [ $result -eq 0 ]; then
    echo "Success!"
    exit 0
else
    echo "Failed!"
    exit 1
fi
