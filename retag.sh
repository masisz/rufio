#!/bin/zsh

# 使い方: ./retag.sh v0.31.0

# 引数チェック
if [ $# -eq 0 ]; then
  echo "使い方: $0 <タグ名>"
  echo "例: $0 v0.31.0"
  exit 1
fi

TAG_NAME=$1

echo "=== タグ再作成スクリプト ==="
echo "タグ: $TAG_NAME"
echo ""

# 1. ローカルのタグを削除
echo "1. ローカルタグを削除中..."
if git tag -d $TAG_NAME; then
  echo "✓ ローカルタグを削除しました"
else
  echo "⚠ ローカルタグが存在しないか、削除に失敗しました"
fi
echo ""

# 2. リモートのタグを削除
echo "2. リモートタグを削除中..."
if git push origin :refs/tags/$TAG_NAME; then
  echo "✓ リモートタグを削除しました"
else
  echo "⚠ リモートタグの削除に失敗しました（存在しない可能性があります）"
fi
echo ""

# 3. タグを再作成
echo "3. タグを再作成中..."
if git tag $TAG_NAME; then
  echo "✓ タグを再作成しました"
else
  echo "✗ タグの再作成に失敗しました"
  exit 1
fi
echo ""

# 4. タグをプッシュ
echo "4. タグをプッシュ中..."
if git push origin $TAG_NAME; then
  echo "✓ タグをプッシュしました"
  echo ""
  echo "🎉 完了！GitHub Actionsが実行されます。"
else
  echo "✗ タグのプッシュに失敗しました"
  exit 1
fi
