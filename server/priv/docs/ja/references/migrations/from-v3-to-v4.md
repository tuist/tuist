---
{
  "title": "v3 から v4 へ",
  "titleTemplate": ":title · マイグレーション · リファレンス · Tuist",
  "description": "このページでは、Tuist CLI をバージョン 3 からバージョン 4 に移行する方法を説明します。"
}
---
# Tuist v3 から v4 へ {#from-tuist-v3-to-v4}

[Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) のリリースにあたり、プロジェクトの長期的な使いやすさと保守性を高めるため、いくつかの破壊的変更を導入しました。このドキュメントでは、Tuist 3 から Tuist 4 へアップグレードするためにプロジェクトに対して行う必要がある変更点を説明します。

## `tuistenv` を介したバージョン管理の廃止 {#dropped-version-management-through-tuistenv}

Tuist 4 より前は、インストールスクリプトが `tuistenv` というツールをインストールし、インストール時に `tuist` にリネームしていました。このツールは Tuist のバージョンのインストールとアクティベーションを担当し、環境間での決定性を保証していました。Tuist の機能範囲を縮小する目的で、私たちは `tuistenv` を廃止し、同じ役割を果たしつつより柔軟でさまざまなツールで使用できる [Mise](https://mise.jdx.dev/) を採用することにしました。`tuistenv` を使用していた場合は、`curl -Ls https://uninstall.tuist.io | bash` を実行して現在のバージョンの Tuist をアンインストールし、その後、希望するインストール方法で再インストールする必要があります。Mise は環境間で決定論的にバージョンをインストールおよびアクティブ化できるため、その使用を強く推奨します。

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **CI 環境および Xcode プロジェクトにおける Mise**
>
> Mise がもたらす決定性を全面的に受け入れる場合は、[CI 環境](https://mise.jdx.dev/continuous-integration.html) および [Xcode プロジェクト](https://mise.jdx.dev/ide-integration.html#xcode) で Mise を使用する方法に関するドキュメントを確認することをお勧めします。


> [!NOTE]
> **Homebrew に対応**
>
> macOS で人気のあるパッケージマネージャーである Homebrew を使用して Tuist を引き続きインストールできます。Homebrew を使用して Tuist をインストールする方法については、<.localized_link href="/guides/install-tuist#recommended-homebrew">インストールガイド</.localized_link> を参照してください。


## `init` モデルからの `ProjectDescription` コンストラクタの削除 {#dropped-init-constructors-from-projectdescription-models}

API の可読性と表現力を向上させる目的で、すべての `ProjectDescription` モデルから `init` コンストラクタを削除することにしました。各モデルは現在、モデルのインスタンスを作成するために使用できる静的コンストラクタを提供しています。`init` コンストラクタを使用していた場合は、代わりに静的コンストラクタを使用するようにプロジェクトを更新する必要があります。

> [!TIP]
> **命名規則**
>
> 私たちが従っている命名規則では、モデルの名前を静的コンストラクタの名前として使用します。例えば、`Target` モデルの静的コンストラクタは `Target.target` です。


## `--no-cache` を `--no-binary-cache` に名称変更 {#renamed-nocache-to-nobinarycache}

`--no-cache` フラグは曖昧だったため、バイナリキャッシュを指すことを明確にするために `--no-binary-cache` に名称変更しました。`--no-cache` フラグを使用していた場合は、代わりに `--no-binary-cache` フラグを使用するようにプロジェクトを更新する必要があります。

## `tuist fetch` を `tuist install` に名称変更 {#renamed-tuist-fetch-to-tuist-install}

業界の慣習に合わせて、`tuist fetch` コマンドを `tuist install` に名称変更しました。`tuist fetch` コマンドを使用していた場合は、代わりに `tuist install` コマンドを使用するようにプロジェクトを更新する必要があります。

## [依存関係の DSL として `Package.swift` を採用](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4 より前は、`Dependencies.swift` ファイルで依存関係を定義できました。この独自形式により、[Dependabot](https://github.com/dependabot) や [Renovatebot](https://github.com/renovatebot/renovate) などのツールによる依存関係の自動更新サポートが失われました。さらに、ユーザーにとって不要な間接層を導入していました。そのため、Tuist では依存関係を定義する方法として `Package.swift` のみを採用することにしました。`Dependencies.swift` ファイルを使用していた場合は、`Tuist/Dependencies.swift` の内容をルートにある `Package.swift` に移動し、`#if TUIST` ディレクティブを使用して統合を設定する必要があります。Swift Package の依存関係を統合する方法の詳細は <.localized_link href="/guides/features/projects/dependencies#swift-packages">こちら</.localized_link> をご覧ください。

## `tuist cache warm` を `tuist cache` に名称変更 {#renamed-tuist-cache-warm-to-tuist-cache}

簡潔さのため、`tuist cache warm` コマンドを `tuist cache` に名称変更しました。`tuist cache warm` コマンドを使用していた場合は、代わりに `tuist cache` コマンドを使用するようにプロジェクトを更新する必要があります。


## `tuist cache print-hashes` を `tuist cache --print-hashes` に名称変更 {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` コマンドを `tuist cache --print-hashes` に名称変更し、それが `tuist cache` コマンドのフラグであることを明確にしました。`tuist cache print-hashes` コマンドを使用していた場合は、代わりに `tuist cache --print-hashes` フラグを使用するようにプロジェクトを更新する必要があります。

## キャッシングプロファイルの削除 {#removed-caching-profiles}

Tuist 4 より前は、`Tuist/Config.swift` でキャッシュの設定を含むキャッシングプロファイルを定義できました。プロジェクト生成に使用されたものとは異なるプロファイルを使用して生成プロセスで利用した場合に混乱を招く可能性があるため、この機能を削除することにしました。さらに、アプリのリリースバージョンをビルドするためにデバッグプロファイルを使用してしまう可能性があり、予期しない結果を招くおそれがありました。代わりに、プロジェクト生成時に使用する構成を指定できる `--configuration` オプションを導入しました。キャッシングプロファイルを使用していた場合は、代わりに `--configuration` オプションを使用するようにプロジェクトを更新する必要があります。

## 引数の採用に伴う `--skip-cache` の削除 {#removed-skipcache-in-favor-of-arguments}

バイナリキャッシュをスキップすべきターゲットを引数で制御できるようにするため、`generate` コマンドから `--skip-cache` フラグを削除しました。`--skip-cache` フラグを使用していた場合は、代わりに引数を使用するようにプロジェクトを更新する必要があります。

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

## [署名機能の廃止](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

署名は、[Fastlane](https://fastlane.tools/) や Xcode 自体といったコミュニティツールによってすでに解決されており、これらはその点で 훨씬優れた仕事を行います。署名は Tuist にとって過剰な目標であり、プロジェクトのコア機能に集中する方がよいと考えました。リポジトリ内の証明書とプロファイルを暗号化し、生成時に適切な場所にインストールする Tuist の署名機能を使用していた場合は、プロジェクト生成前に実行される独自のスクリプトでそのロジックを再現することを検討してください。具体的には:
  - ファイルシステムまたは環境変数に保存されたキーを使用して証明書とプロファイルを復号し、証明書をキーチェーンに、プロビジョニングプロファイルを `~/Library/MobileDevice/Provisioning\ Profiles` ディレクトリにインストールするスクリプト。
  - 既存のプロファイルと証明書を取得して暗号化するスクリプト。

> [!TIP]
> **署名の要件**
>
> 署名には、適切な証明書がキーチェーンに存在し、プロビジョニングプロファイルが `~/Library/MobileDevice/Provisioning\ Profiles` ディレクトリに存在している必要があります。`security` コマンドラインツールを使用して証明書をキーチェーンにインストールし、`cp` コマンドを使用してプロビジョニングプロファイルを適切なディレクトリにコピーできます。


## `Dependencies.swift` を介した Carthage 統合の廃止 {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4 より前は、Carthage の依存関係を `Dependencies.swift` ファイルで定義でき、ユーザーは `tuist fetch` を実行して取得できました。Swift Package Manager が依存関係管理の推奨手段となる将来を考えると、これは Tuist にとって過剰な目標であるとも考えました。Carthage の依存関係を使用していた場合は、`Carthage` を直接使用して事前コンパイル済みのフレームワークと XCFramework を Carthage の標準ディレクトリに取得し、`TargetDependency.xcframework` および `TargetDependency.framework` ケースを使用してターゲットからそれらのバイナリを参照する必要があります。

> [!NOTE]
> **Carthage は引き続きサポートされています**
>
> Carthage のサポートを終了したと誤解したユーザーがいましたが、そうではありません。Tuist と Carthage の出力との間の契約は、システムに保存されたフレームワークと XCFramework です。変更されたのは依存関係の取得を担当する主体だけです。以前は Tuist が Carthage を介して行っていたものが、現在は Carthage 自体が行います。


## `TargetDependency.packagePlugin` API の廃止 {#dropped-the-targetdependencypackageplugin-api}

Tuist 4 より前は、`TargetDependency.packagePlugin` ケースを使用してパッケージプラグインの依存関係を定義できました。Swift Package Manager が新しいパッケージタイプを導入するのを見て、より柔軟で将来性のあるものに向けて API を改良することにしました。`TargetDependency.packagePlugin` を使用していた場合は、代わりに `TargetDependency.package` を使用し、使用するパッケージのタイプを引数として渡す必要があります。

## [非推奨 API の削除](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Tuist 3 で非推奨とマークされていた API を削除しました。非推奨の API を使用していた場合は、新しい API を使用するようにプロジェクトを更新する必要があります。
