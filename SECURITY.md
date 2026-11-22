# Security Policy / セキュリティポリシー

[English](#english) | [日本語](#日本語)

## English

### Supported versions

Only the latest released version receives security fixes. Please upgrade with `gem update rufio` before reporting.

### Reporting a vulnerability

Please **do not open a public issue** for security problems.

- Use GitHub's private reporting: [Security → Report a vulnerability](https://github.com/masisz/rufio/security/advisories/new)
- Or email masisz.1567@gmail.com

Include the rufio version, OS, steps to reproduce, and the impact you expect. This is a personal project, so responses are best-effort, but reports are taken seriously and fixes are noted in [CHANGELOG.md](./CHANGELOG.md) under `Security`.

### Threat model

rufio is a local TUI tool run by you, on files you can already access.

**In scope** (treated as vulnerabilities):
- Names or contents of files, directories, archives, or tool output causing unintended command execution (e.g. shell metacharacters in file names)
- Escape sequences in file contents or names that manipulate the terminal in harmful ways
- Unsafe handling of paths that lets an operation affect files outside what the user selected
- Secrets exposed through logs or temporary files

**Out of scope** (by design):
- Commands you type yourself in command mode (`:`, `!`) — they are executed as shell commands
- Code in your own configuration: `~/.rufio/commands.rb` and `~/.config/rufio/commands.rb` are **evaluated as Ruby**. Keep them writable only by you
- Scripts you register under script paths — they run with your privileges
- Vulnerabilities in external tools (rga, bat, zoxide, editors)

### Design practices

- Files and scripts are launched in array form (`system(*argv)`), never through a shell string; paths beginning with `-` are prefixed with `./`
- Search queries are passed to rga after `--`
- Everything drawn to the screen passes through one sanitizing step: control characters (C0 and C1, so `ESC`, `BEL` and the 8-bit `CSI`) are replaced with a space before a cell is stored, so an escape sequence in a file name, a file's contents, a spreadsheet cell, a database table name or a tool's output cannot reach the terminal
- Text copied to the clipboard has its trailing newline removed, and control characters other than newline and tab replaced, so a value cannot execute on paste
- SQLite databases are opened read-only, with `-safe` where the `sqlite3` command supports it, by absolute path, and only `SELECT` is issued; table names are quoted as identifiers
- YAML is loaded with `YAML.safe_load`
- Command execution logs are written with `0600` permissions
- Runtime dependencies are kept to the terminal libraries (`io-console`, `pastel`, `tty-cursor`, `tty-screen`) and the parsers the previews need (`csv`, `rubyzip`, `roo`, `nokogiri`, `pdf-reader`, `base64`). A parser only ever reads the file being previewed or searched
- Gems are published from tagged commits via RubyGems Trusted Publishing (no long-lived API key); CI runs the test suite before publishing

### Known limitations

- A preview reads the file it shows, so a parser bug in a bundled library (`roo` for spreadsheets, Ruby's `csv`) is reachable by moving the cursor onto a file. Previews are bounded (512 KiB of text, 1000 rows, 10 MiB for a spreadsheet) and a file that cannot be parsed falls back to the archive or binary view
- A SQLite preview runs the `sqlite3` command on the file. A view's body is SQL written by whoever made the file; it is executed read-only and in `-safe` mode where available, and the CLI refuses `writefile()`, `readfile()`, `edit()` and `load_extension()` outside a direct statement. A `sqlite3` older than 3.32 does not carry those refusals
- The optional native extension under `lib_zig` is not shipped in the gem and has not been independently audited

---

## 日本語

### サポート対象バージョン

セキュリティ修正は最新のリリースにのみ行います。報告の前に `gem update rufio` で更新してください。

### 脆弱性の報告

セキュリティ上の問題は**公開Issueに書かない**でください。

- GitHubの非公開報告: [Security → Report a vulnerability](https://github.com/masisz/rufio/security/advisories/new)
- またはメール: masisz.1567@gmail.com

rufioのバージョン、OS、再現手順、想定される影響を添えてください。個人プロジェクトのため対応はベストエフォートですが、報告は真剣に扱い、修正は [CHANGELOG.md](./CHANGELOG.md) の `Security` に記載します。

### 脅威モデル

rufioは、あなた自身がアクセスできるファイルに対して、ローカルで実行するTUIツールです。

**対象（脆弱性として扱う）**:
- ファイル名・ディレクトリ名・アーカイブ・ツール出力の内容によって、意図しないコマンドが実行されること（例: ファイル名中のシェルメタ文字）
- ファイル内容や名前に含まれるエスケープシーケンスによる、有害なターミナル操作
- パスの扱いの不備により、ユーザーが選択した範囲外のファイルに操作が及ぶこと
- ログや一時ファイルを通じた機密情報の漏えい

**対象外（設計上の仕様）**:
- コマンドモード（`:`、`!`）で自分で入力したコマンド — シェルコマンドとして実行されます
- 自分の設定ファイル内のコード — `~/.rufio/commands.rb` と `~/.config/rufio/commands.rb` は**Rubyとして評価**されます。書き込み権限は自分だけにしてください
- スクリプトパスに登録したスクリプト — あなたの権限で実行されます
- 外部ツール（rga、bat、zoxide、エディタ）自体の脆弱性

### 設計上の方針

- ファイルやスクリプトは配列形式（`system(*argv)`）で起動し、シェル文字列を介しません。`-` で始まるパスには `./` を付与します
- rga には `--` を挟んで検索語を渡します
- 画面に出す文字列はすべて 1 箇所で無害化します。制御文字（C0 と C1。`ESC`・`BEL`・8 ビットの `CSI` を含む）はバッファに入れる前に空白へ置き換えるため、ファイル名・ファイル内容・表のセル・データベースのテーブル名・ツールの出力に含まれるエスケープシーケンスがターミナルへ届きません
- クリップボードへコピーする文字列は、末尾の改行を落とし、改行とタブ以外の制御文字を置き換えます（貼り付けた瞬間に実行されるのを防ぐため）
- SQLite は読み取り専用で開き、`sqlite3` が対応していれば `-safe` を付け、絶対パスで渡し、`SELECT` のみを発行します。テーブル名は識別子としてクォートします
- YAML は `YAML.safe_load` で読み込みます
- コマンド実行ログは `0600` で保存します
- 実行時依存gemは、ターミナル操作（`io-console`、`pastel`、`tty-cursor`、`tty-screen`）と、プレビュー・検索に必要な解析ライブラリ（`csv`、`rubyzip`、`roo`、`nokogiri`、`pdf-reader`、`base64`）に限っています。解析ライブラリはプレビュー・検索の対象ファイルを読むためだけに使います
- gemはタグ付きコミットからRubyGemsのTrusted Publishingで公開します（長期APIキーなし）。公開前にCIでテストを実行します

### 既知の制約

- プレビューは対象ファイルを解析するため、同梱ライブラリ（表計算は `roo`、CSV は Ruby の `csv`）の解析不具合にはカーソルを合わせるだけで到達します。読み込み量には上限があり（テキスト 512 KiB、1000 行、表計算 10 MiB）、解析できないファイルはアーカイブ表示またはバイナリ表示に戻ります
- SQLite のプレビューは `sqlite3` コマンドをファイルに対して実行します。ビューの本体はファイル作成者が書いた SQL です。読み取り専用かつ（対応していれば）`-safe` で実行し、CLI 側も直接の文以外からの `writefile()`・`readfile()`・`edit()`・`load_extension()` を拒否します。3.32 より古い `sqlite3` にはこの拒否がありません
- `lib_zig` のネイティブ拡張（任意機能）はgemに同梱しておらず、第三者による監査も受けていません
