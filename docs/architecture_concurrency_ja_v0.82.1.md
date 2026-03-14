# rufio 並行実行アーキテクチャ

## 結論（Single Thread / Thread / Process / Event Loop）

rufio は **単一のメインプロセス**で動作し、UIは **シングルスレッドのイベントループ**で駆動されます。
ただし、実行中に以下を併用します。

- `Thread`: バックグラウンド実行、非同期スキャン、非同期ハイライト、Windows入力補助
- `Process`（子プロセス）: `Open3` / `IO.popen` / `system` による外部コマンド実行

つまり実態は、**「シングルスレッドUI + 補助スレッド + 外部プロセス」構成**です。

## 1. 起動とプロセス境界

- エントリポイントは [`bin/rufio`](../bin/rufio)
- 本体は [`Rufio::Application`](../lib/rufio/application.rb) が初期化し、[`TerminalUI#main_loop`](../lib/rufio/terminal_ui.rb) に入る
- アプリ自身は `fork`/常駐ワーカープロセスを持たない（コード上 `fork` 使用なし）

### 子プロセスを作る経路

- `Open3.capture3` / `Open3.popen3`
  - [`lib/rufio/background_command_executor.rb`](../lib/rufio/background_command_executor.rb)
  - [`lib/rufio/command_mode.rb`](../lib/rufio/command_mode.rb)
  - [`lib/rufio/script_runner.rb`](../lib/rufio/script_runner.rb)
  - [`lib/rufio/script_executor.rb`](../lib/rufio/script_executor.rb)
- `IO.popen`（`bat` 実行）
  - [`lib/rufio/syntax_highlighter.rb`](../lib/rufio/syntax_highlighter.rb)
- `system`（`tput`, `which` 等）
  - [`lib/rufio/terminal_ui.rb`](../lib/rufio/terminal_ui.rb)
  - [`lib/rufio/syntax_highlighter.rb`](../lib/rufio/syntax_highlighter.rb)

## 2. Event Loop（UIの中心）

メインループは [`TerminalUI#main_loop`](../lib/rufio/terminal_ui.rb) で実装されています。

- ループ周期の基準: 約30FPS（`min_sleep_interval = 0.0333`）
- フェーズ: `UPDATE -> DRAW -> RENDER -> SLEEP`
- 入力: ノンブロッキング
  - Unix: `IO.select(..., timeout=0)` + `STDIN.read_nonblock`
  - Windows: 補助入力スレッド + `Queue` 受信
- 定期監視
  - バックグラウンドコマンド完了チェック（約0.1秒周期）
  - 通知ランプ期限チェック
  - 非同期ハイライト完了フラグチェック

ポイントは「**UIスレッドはブロックしない**」ことで、重い処理は別スレッド/別プロセスへ逃がしています。

## 3. Thread モデル

### 3.1 常時/都度の補助スレッド

- バックグラウンドコマンド
  - [`BackgroundCommandExecutor`](../lib/rufio/background_command_executor.rb)
  - `Thread.new` で1ジョブ実行（同時1本に制限）
- スクリプトジョブ
  - [`ScriptRunner`](../lib/rufio/script_runner.rb)
  - [`CommandMode`](../lib/rufio/command_mode.rb)
  - ジョブごとに `Thread.new` で実行
- 非同期ディレクトリスキャン
  - [`NativeScannerRubyCore`](../lib/rufio/native_scanner.rb)
  - スキャンごとに1スレッド
- 並列スキャン
  - [`ParallelScanner`](../lib/rufio/parallel_scanner.rb)
  - `Queue` + ワーカースレッドプール（既定4）
- 非同期シンタックスハイライト
  - [`SyntaxHighlighter#highlight_async`](../lib/rufio/syntax_highlighter.rb)
  - `Thread` + `Mutex` + pendingガード
- Windows入力補助
  - [`TerminalUI#setup_terminal`](../lib/rufio/terminal_ui.rb)
  - `STDIN.read(1)` を読む専用スレッド

### 3.2 スレッド安全性の扱い

- `Mutex` で共有状態を保護（例: `NativeScannerRubyCore`, `SyntaxHighlighter`）
- `Queue` で producer/consumer 連携（`ParallelScanner`, Windows入力）
- UI反映はメインループでポーリング/フラグ監視し、描画系の責務を集中

## 4. Process モデル

外部コマンド実行は Ruby プロセス内で直接処理せず、子プロセスに委譲しています。

- シェルコマンド・スクリプト・rake は `Open3` 経由で実行
- タイムアウト付き実行では `Process.kill("TERM"/"KILL")` を使用
  - [`ScriptExecutor`](../lib/rufio/script_executor.rb)
- ハイライトは `bat` 子プロセスから出力取得

このため、重い外部処理があっても UI スレッド停止を避けやすい構造です。

## 5. Single Thread か？への回答

質問に対しては次の回答が正確です。

- UI制御: **シングルスレッド（イベントループ）**
- 並行処理: **マルチスレッドを使用**
- 実処理実行: **外部子プロセスを多用**
- アーキテクチャ全体: **単一メインプロセス + イベントループ + ワーカースレッド + 子プロセス**

## 6. 補足（運用上の含意）

- RubyスレッドはI/O待ちや外部プロセス待ちの分離には有効
- CPUバウンド処理をRubyスレッドで増やしても、処理系制約（GVL）で伸びにくい可能性がある
- 現状設計は「UI応答性優先」「外部コマンド委譲型」のTUIとして合理的

## 7. メモリモデル

rufio のメモリは、概ね次の4種類で構成されます。

- 固定サイズの描画バッファ（画面サイズ依存）
- ディレクトリ/プレビューなどの作業データ（操作対象依存）
- キャッシュ/履歴（セッション経過で増える可能性あり）
- 外部プロセス実行時の一時データ（子プロセス出力依存）

### 7.1 オブジェクトの寿命

- プロセス寿命で生存（起動時作成）
  - `TerminalUI`, `UIRenderer`, `KeybindHandler`, `JobManager` など
- 画面更新ごとに再生成される一時データ
  - 行描画文字列、差分描画バッファ
- ジョブ/コマンド実行中のみ生存
  - ワーカースレッド、`Open3` の入出力文字列、スキャナーインスタンス

### 7.2 固定上限に近い領域

- ダブルバッファ
  - [`Screen`](../lib/rufio/screen.rb): `@cells`（`height x width`）
  - [`Renderer`](../lib/rufio/renderer.rb): `@front`（`height` 行ぶんの表示文字列）
- これらは基本的に「端末サイズに比例」し、無制限には伸びない

### 7.3 変動するが上限管理される領域

- 通知
  - [`NotificationManager`](../lib/rufio/notification_manager.rb) は最大3件
- コマンド履歴（メモリ内）
  - [`CommandHistory`](../lib/rufio/command_history.rb) は `max_size`（既定1000）
- ディレクトリエントリ
  - [`DirectoryListing`](../lib/rufio/directory_listing.rb) は `refresh` ごとに `@entries` を再構築

### 7.4 増加しやすい領域（要注意）

- プレビューキャッシュ
  - [`UIRenderer`](../lib/rufio/ui_renderer.rb) の `@preview_cache` は閲覧ファイルパス単位で蓄積
  - `wrapped` / `highlighted_wrapped` も幅ごとに追加される
  - `clear_preview_cache` は実装されているが、通常フローからは呼ばれていない
- ジョブ一覧
  - [`JobManager`](../lib/rufio/job_manager.rb) の `@jobs` は追加され続ける
  - `clear_completed` はあるが、通常キー操作には接続されていない
- ジョブログ
  - [`TaskStatus`](../lib/rufio/task_status.rb) の `@logs` は配列で蓄積（上限なし）
  - 標準出力/標準エラーが大きいジョブはメモリ圧迫要因になる
- ログファイル（ディスク）
  - [`CommandLogger`](../lib/rufio/command_logger.rb) はログファイルを増やし続ける
  - `cleanup_old_logs` は実装済みだが、通常フローで自動実行はされない

### 7.5 外部プロセス実行時のメモリ特性

- `Open3.capture3` は stdout/stderr を文字列として一括保持するため、
  出力が大きいほど Ruby ヒープ使用量が一時的に増える
- ただし実処理は子プロセス側で実行されるため、計算本体のメモリは原則として別プロセスに分離される

### 7.6 Ruby/C 境界（Zig スキャナー）

- Zig経路では [`NativeScannerZigCore`](../lib/rufio/native_scanner_zig.rb) がハンドルを保持し、
  `close` で `core_async_destroy` を呼んで明示解放する
- `scan` 呼び出し側は `ensure` で `close` しており、通常経路でハンドルリークしにくい設計

### 7.7 まとめ

メモリモデルとしては、**描画バッファは安定**している一方で、**プレビューキャッシュ・ジョブ履歴・ジョブログ**は
セッションが長くなるほど増えうる構造です。長時間運用時のメモリ安定性は、この3点の上限管理の有無に最も左右されます。
