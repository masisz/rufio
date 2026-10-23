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
- Vulnerabilities in external tools (fzf, rga, bat, zoxide, editors)

### Design practices

- Files and scripts are launched in array form (`system(*argv)`), never through a shell string; paths beginning with `-` are prefixed with `./`
- Search queries are passed to rga after `--`
- YAML is loaded with `YAML.safe_load`
- Command execution logs are written with `0600` permissions
- Runtime dependencies are limited to `io-console`, `pastel`, `tty-cursor`, `tty-screen`
- Gems are published from tagged commits via RubyGems Trusted Publishing (no long-lived API key); CI runs the test suite before publishing

### Known limitations

- Text previews only detect binary files (by control-character ratio); terminal escape sequences inside otherwise-textual files are not explicitly stripped. Avoid previewing untrusted files in a terminal you do not trust
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
- 外部ツール（fzf、rga、bat、zoxide、エディタ）自体の脆弱性

### 設計上の方針

- ファイルやスクリプトは配列形式（`system(*argv)`）で起動し、シェル文字列を介しません。`-` で始まるパスには `./` を付与します
- rga には `--` を挟んで検索語を渡します
- YAML は `YAML.safe_load` で読み込みます
- コマンド実行ログは `0600` で保存します
- 実行時依存gemは `io-console`、`pastel`、`tty-cursor`、`tty-screen` のみです
- gemはタグ付きコミットからRubyGemsのTrusted Publishingで公開します（長期APIキーなし）。公開前にCIでテストを実行します

### 既知の制約

- テキストのプレビューはバイナリ判定（制御文字の比率）のみで、テキストとして扱われるファイル内のエスケープシーケンスは明示的に除去していません。信頼できないファイルを、信頼できないターミナルでプレビューするのは避けてください
- `lib_zig` のネイティブ拡張（任意機能）はgemに同梱しておらず、第三者による監査も受けていません
