---
{
  "title": "v3からv4へ",
  "titleTemplate": ":title · マイグレーション · リファレンス · Tuist",
  "description": "このページでは、Tuist CLIをバージョン3からバージョン4にマイグレーションする方法を説明します。"
}
---
# Tuist v3 から v4 へ {#from-tuist-v3-to-v4}

[Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) のリリースにあたり、長期的な使いやすさと保守性の向上を目指して、いくつかの破壊的変更を導入しました。このドキュメントでは、Tuist 3 から Tuist 4 へアップグレードするためにプロジェクトに必要な変更点を説明します。

### `tuistenv` を介したバージョン管理の廃止 {#dropped-version-management-through-tuistenv}

Tuist 4 より前は、インストールスクリプトが `tuistenv` というツールをインストールし、インストール時に `tuist` にリネームしていました。このツールは Tuist のバージョンをインストールおよび有効化し、環境間での決定性を保証していました。Tuist の機能範囲を縮小することを目的として、`tuistenv` を廃止し、同じ役割を果たしながらより柔軟でさまざまなツールで使用できる [Mise](https://mise.jdx.dev/) を採用することにしました。`tuistenv` を使用していた場合は、`curl -Ls https://uninstall.tuist.io | bash` を実行して現在の Tuist バージョンをアンインストールし、任意のインストール方法で再インストールする必要があります。Mise は環境間で決定論的にバージョンをインストールおよび有効化できるため、その使用を強く推奨します。

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **CI 環境および Xcode プロジェクトにおける Mise**
>
> Mise がもたらす全般的な決定性を受け入れる場合は、[CI 環境](https://mise.jdx.dev/continuous-integration.html) および [Xcode プロジェクト](https://mise.jdx.dev/ide-integration.html#xcode) で Mise を使用する方法に関するドキュメントを確認することをお勧めします。


> [!NOTE]
> **Homebrew に対応**
>
> macOS で人気のあるパッケージマネージャーである Homebrew を使用して Tuist をインストールすることもできます。Homebrew を使用した Tuist のインストール手順は、<.localized_link href="/guides/install-tuist#alternative-homebrew">インストールガイド</.localized_link> で確認できます。


### `init` モデルからの `ProjectDescription` コンストラクタの削除 {#dropped-init-constructors-from-projectdescription-models}

API の可読性と表現力を向上させることを目的として、すべての `ProjectDescription` モデルから `init` コンストラクタを削除することにしました。各モデルには、インスタンスを作成するために使用できる静的コンストラクタが用意されています。`init` コンストラクタを使用していた場合は、代わりに静的コンストラクタを使用するようにプロジェクトを更新する必要があります。

> [!TIP]
> **命名規則**
>
> 私たちが従っている命名規則では、モデル名を静的コンストラクタの名前として使用します。例えば、`Target` モデルの静的コンストラクタは `Target.target` です。


### `--no-cache` を `--no-binary-cache` に改名 {#renamed-nocache-to-nobinarycache}

`--no-cache` フラグの意味があいまいだったため、バイナリキャッシュを指すことを明確にするために `--no-binary-cache` に改名しました。`--no-cache` フラグを使用していた場合は、代わりに `--no-binary-cache` フラグを使用するようにプロジェクトを更新する必要があります。

### `tuist fetch` を `tuist install` に改名 {#renamed-tuist-fetch-to-tuist-install}

業界の慣習に合わせて、`tuist fetch` コマンドを `tuist install` に改名しました。`tuist fetch` コマンドを使用していた場合は、代わりに `tuist install` コマンドを使用するようにプロジェクトを更新する必要があります。

### [依存関係の DSL として `Package.swift` を採用](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4 より前は、`Dependencies.swift` ファイルで依存関係を定義できました。この独自形式により、[Dependabot](https://github.com/dependabot) や [Renovatebot](https://github.com/renovatebot/renovate) などのツールによる依存関係の自動更新サポートが失われていました。さらに、ユーザーにとって不要な間接層が生じていました。そのため、Tuist では依存関係を定義する方法として `Package.swift` のみを採用することにしました。`Dependencies.swift` ファイルを使用していた場合は、`Tuist/Dependencies.swift` の内容をルートの `Package.swift` に移動し、`#if TUIST` ディレクティブを使用して統合を設定する必要があります。Swift Package 依存関係の統合方法の詳細については、<.localized_link href="/guides/features/projects/dependencies#swift-packages">こちら</.localized_link> を参照してください。

### `tuist cache warm` を `tuist cache` に改名 {#renamed-tuist-cache-warm-to-tuist-cache}

簡潔さのため、`tuist cache warm` コマンドを `tuist cache` に改名しました。`tuist cache warm` コマンドを使用していた場合は、代わりに `tuist cache` コマンドを使用するようにプロジェクトを更新する必要があります。


### `tuist cache print-hashes` を `tuist cache --print-hashes` に改名 {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` コマンドを `tuist cache --print-hashes` に改名し、それが `tuist cache` コマンドのフラグであることを明確にしました。`tuist cache print-hashes` コマンドを使用していた場合は、代わりに `tuist cache --print-hashes` フラグを使用するようにプロジェクトを更新する必要があります。

### キャッシングプロファイルの削除 {#removed-caching-profiles}

Tuist 4 より前は、`Tuist/Config.swift` でキャッシュの設定を含むキャッシングプロファイルを定義できました。この機能は、プロジェクト生成に使用したものとは異なるプロファイルを生成プロセスで使用した場合に混乱を招く可能性があるため、削除することにしました。さらに、デバッグプロファイルを使用してアプリのリリースビルドを行うなど、予期しない結果につながる可能性がありました。代わりに、プロジェクト生成時に使用する構成を指定できる `--configuration` オプションを導入しました。キャッシングプロファイルを使用していた場合は、代わりに `--configuration` オプションを使用するようにプロジェクトを更新する必要があります。

### 引数の採用に伴う `--skip-cache` の削除 {#removed-skipcache-in-favor-of-arguments}

バイナリキャッシュをスキップするターゲットを引数で制御できるようにするため、`generate` コマンドから `--skip-cache` フラグを削除しました。`--skip-cache` フラグを使用していた場合は、代わりに引数を使用するようにプロジェクトを更新する必要があります。

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [署名機能の削除](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

署名は、[Fastlane](https://fastlane.tools/) や Xcode 自体といったコミュニティツールによってすでに解決されており、それらのほうがはるかに優れています。署名は Tuist にとって過剰な目標であり、プロジェクトのコア機能に集中するほうが良いと考えました。リポジトリ内の証明書とプロファイルを暗号化し、生成時に適切な場所にインストールする Tuist の署名機能を使用していた場合は、プロジェクト生成前に実行される独自のスクリプトでそのロジックを再現することをお勧めします。具体的には以下のとおりです。
  - ファイルシステムまたは環境変数に保存されたキーを使用して証明書とプロファイルを復号し、証明書をキーチェーンに、プロビジョニングプロファイルを `~/Library/MobileDevice/Provisioning\ Profiles` ディレクトリにインストールするスクリプト。
  - 既存のプロファイルと証明書を取得して暗号化するスクリプト。

> [!TIP]
> **署名の要件**
>
> 署名には、キーチェーンに適切な証明書が存在し、プロビジョニングプロファイルが `~/Library/MobileDevice/Provisioning\ Profiles` ディレクトリに存在している必要があります。`security` コマンドラインツールを使用して証明書をキーチェーンにインストールし、`cp` コマンドを使用してプロビジョニングプロファイルを適切なディレクトリにコピーできます。


### `Dependencies.swift` を介した Carthage 統合の削除 {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4 より前は、Carthage の依存関係を `Dependencies.swift` ファイルで定義でき、ユーザーは `tuist fetch` を実行してそれらを取得できました。また、Swift Package Manager が依存関係管理の優先手段となる将来を考慮すると、これは Tuist にとって過剰な目標であると考えました。Carthage の依存関係を使用していた場合は、`Carthage` を直接使用して事前コンパイル済みのフレームワークと XCFramework を Carthage の標準ディレクトリに取得し、`TargetDependency.xcframework` および `TargetDependency.framework` ケースを使用してターゲットからそれらのバイナリを参照する必要があります。

> [!NOTE]
> **Carthage は引き続きサポートされています**
>
> 一部のユーザーは、Carthage のサポートが削除されたものと誤解していました。そうではありません。Tuist と Carthage の出力との間の契約は、システムに保存されたフレームワークと XCFramework です。変更されたのは、依存関係の取得を担当する主体だけです。以前は Carthage を介して Tuist が行っていたものが、現在は Carthage 自体が行います。


### `TargetDependency.packagePlugin` API の削除 {#dropped-the-targetdependencypackageplugin-api}

Tuist 4 より前は、`TargetDependency.packagePlugin` ケースを使用してパッケージプラグインの依存関係を定義できました。Swift Package Manager が新しいパッケージタイプを導入したのを受け、より柔軟で将来を見据えた API に改善することを決定しました。`TargetDependency.packagePlugin` を使用していた場合は、代わりに `TargetDependency.package` を使用し、使用するパッケージのタイプを引数として渡す必要があります。

### [非推奨 API の削除](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Tuist 3 で非推奨とマークされていた API を削除しました。非推奨 API のいずれかを使用していた場合は、新しい API を使用するようにプロジェクトを更新する必要があります。
