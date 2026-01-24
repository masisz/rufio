#!/bin/bash
# デプロイシミュレーション（25秒）

echo "=== Deploy Simulation ==="
echo ""

echo "[1/6] Connecting to server..."
sleep 3
echo "      ✓ Connected to production-01"

echo "[2/6] Backing up current version..."
sleep 4
echo "      ✓ Backup created: backup-20240124-153000.tar.gz"

echo "[3/6] Uploading new version..."
for i in {1..5}; do
    echo "      Uploading... $((i * 20))%"
    sleep 1
done
echo "      ✓ Upload complete"

echo "[4/6] Installing dependencies..."
sleep 4
echo "      ✓ Dependencies installed"

echo "[5/6] Running migrations..."
sleep 3
echo "      ✓ 3 migrations applied"

echo "[6/6] Restarting services..."
sleep 2
echo "      ✓ Services restarted"

echo ""
echo "=== Deploy completed successfully ==="
echo "URL: https://app.example.com"
exit 0
