#!/bin/bash
# ビルドシミュレーション（20秒）

echo "=== Build Simulation ==="
echo ""

echo "[1/5] Compiling sources..."
sleep 4
echo "      ✓ 42 files compiled"

echo "[2/5] Running linter..."
sleep 3
echo "      ✓ No issues found"

echo "[3/5] Running tests..."
sleep 5
echo "      ✓ 128 tests passed"

echo "[4/5] Building assets..."
sleep 4
echo "      ✓ Assets bundled (2.3 MB)"

echo "[5/5] Creating package..."
sleep 4
echo "      ✓ Package created: build/app-1.0.0.tar.gz"

echo ""
echo "=== Build completed successfully ==="
exit 0
