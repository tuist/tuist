---
{
  "title": "サポートされているプレビューの種類",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "モバイルアプリ、macOSアプリ、およびコマンドラインプレビューのパッケージ化と互換性の要件。"
}
---
# サポートされているプレビューのタイプ

プレビューのタイプは、それを生成するビルドシステムとは独立して、何をパッケージ化するか、どこで実行できるかを決定します。各公開ワークフローには、独自の署名と適格性の要件があります。

## モバイルアプリ {#mobile-apps}

- **Android:** 署名付きアプリケーション APK。受信者は互換性のある Android デバイスまたはエミュレータが必要です。Android App Bundle（`.aab`）はプレビューインストールパッケージではありません。
- **Apple:** シミュレータ用のアプリケーションバンドル、または物理デバイス用のエクスポートされた IPA。デバイスビルドには、受信者のデバイスへのインストールを許可するプロビジョニングプロファイルが必要です。

<.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>、<.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link>、および <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> のガイドでは、各ワークフローが公開できる出力について説明しています。例えば、Bazel と Once の公開は、対象となる Apple シミュレータおよび macOS アプリケーションをサポートしますが、物理デバイスビルドはサポートしません。

## デスクトップアプリ {#desktop-apps}

ビルド済みの macOS アプリケーションバンドルを共有します:

```bash
tuist share path/to/MyApp.app
```

署名と公証の要件は引き続き適用されます。デスクトップアプリケーションバンドルは、受信者がプレビューを実行するために使用できる Tuist macOS アプリとは異なります。

## コマンドラインツール {#command-line-tools}

macOS または Linux でスタンドアロンの実行可能ファイルを共有します:

```bash
tuist share path/to/my-tool
```

CLI がリソースバンドル、動的ライブラリ、またはヘルパー実行可能ファイルを必要とする場合は、配布用ディレクトリを用意し、そのディレクトリからの相対パスでエントリポイントを指定してください:

```bash
tuist share path/to/distribution --executable bin/my-tool
```

配布用ディレクトリ全体がアップロードされます。ツールが必要とするライブラリ、リソース、およびヘルパーを含め、ビルドディレクトリの外部でも実行できるようにしてください。スクリプトにはシバンと、受信者のシステムにインストールされたインタプリタが必要です。

## 複数の CLI ターゲット {#multiple-cli-targets}

プレビューは、1 つのコミットに対する同じ CLI のビルドをグループ化します。各ビルドには、1 つのオペレーティングシステムと 1 つ以上の CPU アーキテクチャ用の配布物が含まれます。例えば、1 つのプレビューに macOS arm64、macOS x86_64、および Linux x86_64 の配布物を含めることができます。ユニバーサル macOS 実行可能ファイルは、1 つのビルドで両方の Mac アーキテクチャをカバーします。

各ターゲットを個別にビルドし、同じエントリポイントのベース名とトラックを使用して、同じ Git チェックアウトから配布物を順次公開します:

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

これらのアップロードにより、ビルドが同じプレビューリンクに追加されます。プロジェクト、コミット、公開アカウント、CLI 名、およびトラックは、すべてのアップロードで一貫させてください。Tuist は、受信者のオペレーティングシステムと CPU アーキテクチャに一致するビルドを選択します。

## クライアントとサーバーの互換性 {#client-and-server-compatibility}

デスクトップおよびコマンドラインのプレビューを実行するには、最新の Tuist CLI を使用してください。Tuist をセルフホストしている場合は、これらのタイプを公開する前にサーバーを更新してください。モバイルプレビューは、古いクライアントでも引き続き動作します。

受信者のオペレーティングシステムと CPU アーキテクチャ向けにビルドしてください。Tuist はアプリのクロスコンパイルや依存関係のインストールを行いません。Linux ツールには互換性のあるシステムライブラリも必要です。

プレビューはサンドボックスではなく、ユーザーアカウントの権限で実行されます。信頼できる作者やプルリクエストからのビルドのみを実行してください。

実行時の動作と引数の転送については <.localized_link href="/guides/features/previews/run/cli">CLI でプレビューを実行</.localized_link> を、アクセス、トラック、および README バッジについては <.localized_link href="/guides/features/previews#visibility">プレビューの概要</.localized_link> を参照してください。
