---
{
  "title": "サポートされているプレビューのタイプ",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "モバイルアプリ、macOSアプリ、およびコマンドラインプレビューのパッケージ化と互換性の要件。"
}
---
# サポートされているプレビュータイプ

プレビュータイプは、それを生成するビルドシステムとは独立して、パッケージ化される内容と実行可能な場所を決定します。各公開ワークフローには、独自の署名および資格要件があります。

## モバイルアプリ {#mobile-apps}

- **Android:** 署名付きアプリケーションAPK。受信側には互換性のあるAndroidデバイスまたはエミュレータが必要です。Android App Bundle（`.aab`）はプレビューインストールパッケージではありません。
- **Apple:** シミュレータ用のアプリケーションバンドル、または物理デバイス用のエクスポートされたIPA。デバイスビルドには、受信側のデバイスへのインストールを許可するプロビジョニングプロファイルが必要です。

<.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>、<.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link>、および<.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link>のガイドでは、各ワークフローが公開できる出力について説明しています。例えば、BazelおよびOnce公開は、対象となるAppleシミュレータおよびmacOSアプリケーションをサポートしますが、物理デバイス用ビルドはサポートしません。

## デスクトップアプリ {#desktop-apps}

ビルド済みのmacOSアプリケーションバンドルを共有します:

```bash
tuist share path/to/MyApp.app
```

署名および公証の要件は引き続き適用されます。デスクトップアプリケーションバンドルは、受信者がプレビューを実行するために使用できるTuist macOSアプリとは異なります。

## コマンドラインツール {#command-line-tools}

macOSまたはLinuxでスタンドアロンの実行可能ファイルを共有します:

```bash
tuist share path/to/my-tool
```

CLIにリソースバンドル、動的ライブラリ、またはヘルパー実行ファイルが必要な場合は、配布ディレクトリを作成し、そのディレクトリに対するエントリポイントを指定します:

```bash
tuist share path/to/distribution --executable bin/my-tool
```

配布ディレクトリ全体がアップロードされます。ツールに必要なライブラリ、リソース、およびヘルパーを含め、ビルドディレクトリの外部でも実行できるようにしてください。スクリプトにはshebangと、受信側のシステムにインストールされたインタプリタが必要です。

実行可能ファイル自体にはアイコンが含まれていません。`--icon`を使用してPNGを渡すと、プレビュー上にアイコンを表示できます。例えば、Linuxデスクトップアプリの場合:

```bash
tuist share path/to/distribution --executable bin/my-app --icon path/to/icon.png
```

## 複数のCLIターゲット {#multiple-cli-targets}

プレビューは、1つのコミットに対する同じCLIのビルドをグループ化します。各ビルドには、1つのオペレーティングシステムおよび1つ以上のCPUアーキテクチャ向けの配布物が含まれます。例えば、1つのプレビューにmacOS arm64、macOS x86_64、およびLinux x86_64の配布物を含めることができます。ユニバーサルmacOS実行可能ファイルは、1つのビルドで両方のMacアーキテクチャをカバーします。

各ターゲットを個別にビルドし、同じエントリポイントのベース名とトラックを使用して、同じGitチェックアウトから配布物を順次公開します:

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

これらのアップロードにより、ビルドが同じプレビューリンクに追加されます。プロジェクト、コミット、公開アカウント、CLI名、およびトラックは、すべてのアップロードで一貫させてください。Tuistは、受信者のオペレーティングシステムおよびCPUアーキテクチャに一致するビルドを選択します。

## クライアントとサーバーの互換性 {#client-and-server-compatibility}

デスクトップおよびコマンドラインのプレビューを実行するには、最新のTuist CLIを使用してください。Tuistをセルフホストしている場合は、これらのタイプを公開する前にサーバーを更新してください。モバイルプレビューは、古いクライアントでも引き続き動作します。

受信者のオペレーティングシステムおよびCPUアーキテクチャ向けにビルドしてください。Tuistはアプリのクロスコンパイルや依存関係のインストールを行いません。Linuxツールには互換性のあるシステムライブラリも必要です。

プレビューはサンドボックス内ではなく、ユーザーアカウントの権限で実行されます。信頼できる作者およびプルリクエストからのビルドのみを実行してください。

実行動作および引数の転送については<.localized_link href="/guides/features/previews/run/cli">CLIでプレビューを実行</.localized_link>を、アクセス、トラック、およびREADMEバッジについては<.localized_link href="/guides/features/previews#visibility">プレビューの概要</.localized_link>を参照してください。
