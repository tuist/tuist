---
{
  "title": "イメージ",
  "titleTemplate": ":title · Runners · 機能 · ガイド · Tuist",
  "description": "Tuist Runnerにプリインストールされているもの：Xcode、シミュレーター、Metalツールチェーンを含むmacOSイメージと、Docker、Android SDKを含むUbuntuイメージ。"
}
---
# イメージ {#images}

Tuist Runners の各ジョブは、ランナーイメージから起動した新しい仮想マシンで開始されます。<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> がイメージを選択します。プラットフォーム、macOS 上の Xcode バージョン、Linux 上の Ubuntu リリースです。ジョブ終了時に VM は破棄されるため、ジョブ中にインストールされたものは次のジョブには残りません。

これらのイメージは、ワークフローにとって重要な点で GitHub ホスト型ランナーに従っています。同じユーザー、ホームおよびワークスペースのパス、`ImageOS`、パスワードなしの `sudo`、そして iOS、macOS、Linux のほとんどのワークフローが期待するツールです。GitHub のものより意図的に小さくしているため、プラットフォームごとの違いを以下に示します。

## イメージの選択 {#choosing-an-image}

- **Xcode、Apple SDK、またはシミュレーター:** プロジェクトのビルドに使用する Xcode バージョンに固定された macOS プロファイル。
- **Docker、Android ビルドとエミュレーター、またはその他の Linux ツール:** Ubuntu 24.04 上の Linux プロファイル。
- **Ubuntu 24.04 をまだサポートしていない依存関係:** Ubuntu 22.04 上の Linux プロファイル。

macOS ではイメージではなく Xcode を選びます。各 Xcode バージョンは独自のイメージであり、`26.4.1` に固定されたプロファイルは常に Xcode 26.4.1 でビルドされたイメージ上で実行されます。2 つの Xcode バージョンを実行するには、それぞれに対応するプロファイルを作成してください。

## macOS {#macos}

macOS ランナーは、**macOS 26 Tahoe** を実行する Apple silicon (arm64) 仮想マシンです。ランナー名には正確な macOS バージョンが含まれ（例: `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`）、ジョブの **Set up job** ステップに表示されます。

### Xcode {#xcode}

各イメージには **Xcode が 1 つだけ** 含まれており、`xcode-select` で選択されるため、`xcodebuild` および `xcrun` はセットアップ手順なしで使用できます。これが GitHub ホスト型イメージとの主な違いです。GitHub ホスト型イメージでは、ジョブ実行時に切り替えられる複数の Xcode バージョンが同梱されています。利用可能なバージョン:

{{runner_macos_xcode_versions}}

- **パス。** Xcode は `/Applications/Xcode_<version>.app` にあります。パッチコンポーネントを含むバージョンの場合、`/Applications/Xcode_<major>.<minor>.app` は同じバンドルを指すため、`Xcode_26.4.app` は `Xcode_26.4.1.app` に解決されます。GitHub スタイルのパスをハードコードしたり、それを使って `xcode-select -s` を呼び出したりするワークフローも引き続き動作します。
- **シミュレーター。** その Xcode に同梱されている iOS、tvOS、watchOS、visionOS のシミュレーターランタイムはイメージ内にダウンロードされているため、最初の `xcodebuild test` でそれらを取得する必要はありません。
- **Metal ツールチェーン。** Xcode 26 以降、Metal コンパイラは Xcode に同梱されず、別途ダウンロードする必要があります。すべてのイメージには、その Xcode に対応する Metal ツールチェーンが含まれており、ジョブが実行されるユーザー用にインストールされているため、`xcrun metal` や `.metal` ソースを含むプロジェクトは `xcodebuild -downloadComponent MetalToolchain` を実行せずにビルドできます。
- **ベータ版。** ベータプロファイル（例: `27.3-beta`）は、そのリリースの最新のベータ版を追跡します。Apple が新しいベータ版を提供すると、イメージは再ビルドされ、プロファイルはユーザー側の操作なしにそれに移行します。

### プリインストール済みソフトウェア {#macos-software}

- **Apple ツール:** Xcode（イメージごとに 1 つ）、シミュレーターランタイム、Metal ツールチェーン、`xcodes`、`xcbeautify`
- **Swift および iOS ツール:** SwiftLint、SwiftFormat、SwiftGen、LicensePlist、Mint、Carthage、CocoaPods、fastlane
- **デバイス:** `libimobiledevice`、`ideviceinstaller`、`ios-deploy`
- **言語とランタイム:** `rbenv` を介した Ruby（2.7 と最新の 2 つの 3.x リリース、最新がデフォルト）と Bundler、npm、Yarn、pnpm を備えた Node.js 24
- **パッケージおよびバージョンマネージャー:** Homebrew、mise
- **バージョン管理:** Git、Git LFS、Git Credential Manager、GitHub CLI (`gh`)
- **ユーティリティ:** `jq`、`yq`、`curl`、`wget`、`zip`/`unzip`、CMake、GCC、AWS CLI
- **CI エージェント:** GitHub Actions runner、Buildkite agent、Bitrise agent と CLI、GitLab job executor
- **その他:** Rosetta 2、有効化された `safaridriver`

ツールのバージョンはイメージビルド時に Homebrew から取得され、イメージは定期的に再ビルドされます。ランナー上の正確なバージョンを確認するには、ステップ内で出力してください。例: `swiftlint version` または `xcodebuild -version`。

### 環境 {#macos-environment}

- **ユーザーとパス。** ジョブは `runner` として実行され、ホームは `/Users/runner`、ワークスペースは `/Users/runner/work` です。これは GitHub ホスト型ランナーと同じパスであるため、これらをハードコードするアクションも動作します。
- **`sudo`。** パスワード不要です。VM はあなたのジョブ専用のものです。
- **Homebrew。** プレフィックス (`/opt/homebrew`) は `runner` が所有しているため、`brew install <formula>` は `sudo` なしで動作します。`HOMEBREW_NO_AUTO_UPDATE` が設定されています。
- **シェル。** ステップはログインシェルで実行されるため、Homebrew、`rbenv`、Node.js が `PATH` に含まれています。`LANG` は `en_US.UTF-8` です。
- **`ImageOS`** は `macos26` です。GitHub ホスト型ランナーと同様、これに基づいてプリビルド済みバイナリを選択するセットアップアクション用です。
- **証明書。** Apple の WWDR (G3) および Developer ID (G2) 中間証明書は、署名と公証のためにシステムの信頼ストアに含まれています。
- **プライバシー許可。** GitHub ホスト型イメージと同様に、2 つの macOS プライバシー承認が事前に付与されています。`create-dmg` や `osascript` が必要とする Apple Events を介した Finder のスクリプト実行、および UI テストで音声を録音するアプリが必要とする iOS シミュレーターのマイクへのアクセスです。`simctl privacy` など、シミュレーター内部の許可はジョブの責任範囲です。
- **ディスク。** 各ジョブは少なくとも 100 GB の空きディスク領域から開始されます。

### 含まれていないもの {#macos-not-included}

- **Tuist CLI。** プロジェクトがバージョンを制御できるように、ジョブ内でインストールしてください（例: mise を使用）。
- **他の Xcode バージョン。** `xcode-select` の代わりに、Xcode バージョンごとにプロファイルを使用してください。
- **Docker。** macOS ランナーには Docker デーモンがありません。Linux プロファイルを使用してください。<.localized_link href="/guides/features/runners/docker">Docker</.localized_link> を参照。
- **iOS ビルドではほとんど必要とされない、GitHub が macOS にバンドルするツールチェーン**（Java、Android SDK、.NET、Rust、Python のバージョン、ブラウザなど）は含まれていません。Homebrew、mise、またはセットアップアクションを使用して、ステップ内でインストールしてください。

## Linux {#linux}

Linux ランナーは、プロファイルによって選択される **Ubuntu 24.04** または **Ubuntu 22.04** 上で動作する x86_64 (amd64) 仮想マシンです。リリースの選択方法については <.localized_link href="/guides/features/runners/profiles#linux">プロファイル</.localized_link> を参照してください。

### プリインストール済みソフトウェア {#linux-software}

- **ビルドツールチェーン：** `build-essential`（GCC、G++、make）、autoconf、automake、libtool、`pkg-config`、CMake、Ninja、m4、bison、flex、gettext
- **開発用ヘッダー：** OpenSSL、libffi、zlib、bzip2、readline、SQLite、ncurses、libxml2、libxslt、libyaml、libcurl、uuid
- **Python：** `pip` および `venv` を備えた Python 3（Ubuntu リリースのバージョン）
- **コンテナ：** Buildx と Compose を備えた Docker CLI；デーモンはジョブと同時に実行されます（<.localized_link href="/guides/features/runners/docker">Docker</.localized_link> を参照）
- **Kubernetes：** `kubectl`、Helm
- **Android：** Android SDK は `/usr/local/lib/android/sdk` にあり、コマンドラインツール、プラットフォームツール、および API 34 以降のすべてのプラットフォームおよびビルドツールのリリースが含まれ、ライセンスは承認済みです
- **バージョン管理：** Git、Git LFS、OpenSSH クライアント、GitHub CLI（`gh`）
- **データベースクライアント：** PostgreSQL、MariaDB、Redis（`redis-cli`）、SQLite
- **アーカイブ：** `tar`、`zip`/`unzip`、`xz`、`bzip2`、`p7zip`、`zstd`
- **ユーティリティ：** `curl`、`wget`、`jq`、ripgrep、`fd`、`tree`、`less`、`vim`、HTTPie、`netcat`、`dig`、`ip`、`ping`、`file`
- **CI エージェント：** GitHub Actions ランナー、Buildkite エージェント、Bitrise エージェントと CLI、GitLab ジョブエグゼキューター

### 環境 {#linux-environment}

- **ユーザーとパス。** ジョブは `runner`（UID 1000）として実行され、ホームは `/home/runner`、`docker` グループに所属し、パスワード不要の `sudo` を使用できます。
- **`ImageOS`** は `ubuntu24` または `ubuntu22` で、GitHub ホスト型ランナーと一致します。
- **Android。** `ANDROID_HOME` と `ANDROID_SDK_ROOT` は SDK を指しています。エミュレーターはプリインストールされていません。<.localized_link href="/guides/features/runners#android-emulators">Android エミュレーター</.localized_link> を参照してください。
- **ロケール。** `LANG` と `LC_ALL` は `C.UTF-8` で、`DEBIAN_FRONTEND` は `noninteractive` であるため、`sudo apt-get install` はプロンプトを表示しません。

### 含まれていないもの {#linux-not-included}

Linux イメージは、GitHub がプリインストールするすべての言語ツールチェーンではなく、ビルドの基本的な部分をカバーしています。ジョブが必要とするものは、通常のセットアップアクション（`actions/setup-java`、`actions/setup-node`、`actions/setup-go`、`ruby/setup-ruby`）、mise、または `apt-get` を使用してインストールしてください：

- Java、Node.js、Go、Ruby、.NET、Rust などの **言語ランタイム**。
- **Android NDK。** 必要なバージョンを `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"` でインストールしてください。`ANDROID_NDK_HOME` は設定されていないままなので、存在しない NDK を指すのではなく、ビルドが明確に失敗します。
- `kubectl`、Helm、`gh` 以外の **ブラウザ** およびクラウド CLI。

毎回インストールする代わりに、ジョブ間でツールチェーンを維持するには、<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> に配置してください。

## イメージの更新 {#image-updates}

イメージは、Apple が新しい Xcode またはベータ版を提供したとき、CI エージェントが更新されたとき、およびイメージ自体に変更があったときに再構築されます。ジョブは常に完全でテスト済みのイメージ上で実行されます。新しいイメージはフリートに段階的に展開され、ジョブの実行中に変更されることはありません。

ワークフローが依存しているツールが見つからない場合は、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) で質問してください。
