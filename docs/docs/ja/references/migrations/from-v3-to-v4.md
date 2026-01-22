---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# Tuist v3 から v4 へ{#from-tuist-v3-to-v4}

[Tuist
4](https://github.com/tuist/tuist/releases/tag/4.0.0)のリリースに伴い、プロジェクトの長期的な使用と保守を容易にするため、いくつかの重大な変更を導入しました。このドキュメントでは、Tuist
3からTuist 4へアップグレードするために必要な変更点を説明します。

### `によるバージョン管理の廃止 tuistenv` {#dropped-version-management-through-tuistenv}

Tuist 4以前のインストールスクリプトは、ツール`tuistenv` をインストールし、インストール時に`tuist`
にリネームしていました。このツールはTuistのバージョンをインストール・アクティベートし、環境間で決定論を保証していました。Tuistの機能面を減らす目的で、`tuistenv`
を廃止し、同様の機能を持ちながら柔軟性が高く異なるツール間で使用可能な[Mise](https://mise.jdx.dev/)ツールを採用することにしました。`tuistenv`
を使用していた場合、以下のコマンドで現行バージョンのTuistをアンインストールする必要があります：`curl -Ls
https://uninstall.tuist.io | bash`
その後、任意の方法で再インストールしてください。環境間で決定論的にバージョンをインストール・アクティベート可能なMiseの使用を強く推奨します。

コードグループ

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: warning MISE IN CI ENVIRONMENTS AND XCODE PROJECTS
<!-- -->
Miseが提供する決定論を全面的に採用する場合、[CI環境](https://mise.jdx.dev/continuous-integration.html)および[Xcodeプロジェクト](https://mise.jdx.dev/ide-integration.html#xcode)でのMiseの使用方法に関するドキュメントを確認することを推奨します。
<!-- -->
:::

::: info HOMEBREW IS SUPPORTED
<!-- -->
macOS用の人気パッケージマネージャーであるHomebrewを使用してTuistをインストールすることも可能です。Homebrewを使ったTuistのインストール手順は<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">インストールガイド</LocalizedLink>でご確認いただけます。
<!-- -->
:::

### ` `のイニシャライザ のコンストラクタ を から削除ProjectDescription のモデル`` {#dropped-init-constructors-from-projectdescription-models}

APIの可読性と表現力を向上させるため、すべての`プロジェクトおよび` モデルから、`init`
コンストラクタを削除することにしました。各モデルは現在、モデルのインスタンスを作成するために使用できる静的コンストラクタを提供しています。`init`
コンストラクタを使用していた場合は、代わりに静的コンストラクタを使用するようにプロジェクトを更新する必要があります。

::: tip NAMING CONVENTION
<!-- -->
当社が採用する命名規則では、静的コンストラクタ名にモデル名を使用します。例えば、`Target` の静的コンストラクタ名は`Target.target`
となります。
<!-- -->
:::

### `--no-cache` を`--no-binary-cache に改名` {#renamed-nocache-to-nobinarycache}

`--no-cache` フラグは曖昧であったため、バイナリキャッシュを指すことを明確にするため、`--no-binary-cache`
に名称を変更しました。`--no-cache` フラグを使用していた場合は、代わりに`--no-binary-cache`
フラグを使用するようプロジェクトを更新する必要があります。

### `tuist fetch` を`tuist install に改名` {#renamed-tuist-fetch-to-tuist-install}

業界標準に合わせるため、`tuist fetch` コマンドを`tuist install` に変更しました。`tuist fetch`
コマンドを使用していた場合は、プロジェクトを更新し、代わりに`tuist install` コマンドを使用する必要があります。

### [依存関係記述言語として`のPackage.swift` を採用](https://github.com/tuist/tuist/pull/5862){#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4以前では、`/Dependencies.swift`
ファイルで依存関係を定義できました。この独自フォーマットは、[Dependabot](https://github.com/dependabot) や
[Renovatebot](https://github.com/renovatebot/renovate)
などのツールによる依存関係の自動更新サポートを妨げていました。さらに、ユーザーにとって不要な間接的な操作を強いるものでした。
そのため、Tuistでは依存関係を定義する唯一の方法として`Package.swift` を採用することに決定しました。`Dependencies.swift`
ファイルを使用していた場合は、その内容を`Tuist/Dependencies.swift` からルートディレクトリの`Package.swift`
に移動し、`#if TUIST` ディレクティブを使用して統合を設定する必要があります。Swift
Packageの依存関係を統合する方法の詳細は<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">こちらをご覧ください。</LocalizedLink>

### `tuist cache warm` を`tuist cache に改名` {#renamed-tuist-cache-warm-to-tuist-cache}

簡潔化のため、``` tuist cache warm `` ` コマンドを ``` tuist cache ``` に改名しました。``` tuist
cache warm `` ` コマンドを使用していた場合は、代わりに ``` tuist cache `` `
コマンドを使用するようプロジェクトを更新する必要があります。


### `tuist cache print-hashes` を`tuist cache --print-hashes に改名` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` コマンドを、`tuist cache --print-hashes`
に改名しました。これにより、`tuist cache` コマンドのフラグであることが明確になります。`tuist cache print-hashes`
コマンドを使用していた場合は、プロジェクトを更新し、代わりに`tuist cache --print-hashes` フラグを使用する必要があります。

### キャッシュプロファイルを削除しました{#removed-caching-profiles}

Tuist 4以前では、`Tuist/Config.swift`
でキャッシュプロファイルを定義でき、キャッシュ設定を含んでいました。プロジェクト生成に使用したプロファイルとは異なるプロファイルで生成プロセスを使用すると混乱を招く可能性があるため、この機能は削除されました。
さらに、デバッグプロファイルでアプリのリリース版をビルドするといった誤った操作を招き、予期せぬ結果を招く恐れがありました。代わりに、プロジェクト生成時に使用する設定を指定できる「`--configuration」`
オプションを導入しました。キャッシュプロファイルを使用していた場合は、代わりに「`--configuration」`
オプションを使用するようプロジェクトを更新する必要があります。

### 引数優先のため、``--skip-cache` ` を削除{#removed-skipcache-in-favor-of-arguments}

` `` の ` ` コマンドから ` --skip-cache`
フラグを削除しました。代わりに、引数を使用してバイナリキャッシュをスキップする対象を制御します。` --skip-cache`
フラグを使用していた場合は、プロジェクトを更新して代わりに引数を使用する必要があります。` ` `

コードグループ

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [署名機能の廃止](https://github.com/tuist/tuist/pull/5716){#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

署名処理は既に[Fastlane](https://fastlane.tools/)やXcode自体のコミュニティツールで解決されており、そちらの方がはるかに優れた処理を行います。
Tuistにとって署名機能はストレッチゴールであり、プロジェクトの中核機能に注力すべきと判断しました。Tuistの署名機能（リポジトリ内の証明書とプロファイルを暗号化し、生成時に適切な場所にインストールする処理）を利用していた場合、プロジェクト生成前に実行する独自スクリプトで同等のロジックを再現することを推奨します。具体的には：
  - ファイルシステムまたは環境変数に保存されたキーを使用して証明書とプロファイルを復号化し、証明書をキーチェーンにインストールし、プロビジョニングプロファイルをディレクトリ`~/Library/MobileDevice/Provisioning\
    Profiles` にインストールするスクリプト。
  - 既存のプロファイルと証明書を受け取り、それらを暗号化できるスクリプト。

::: tip SIGNING REQUIREMENTS
<!-- -->
署名には、キーチェーンに適切な証明書が存在し、プロビジョニングプロファイルがディレクトリ`~/Library/MobileDevice/Provisioning\
Profiles` に存在している必要があります。キーチェーンへの証明書インストールには`security`
コマンドラインツールを、プロビジョニングプロファイルのコピーには`cp` コマンドを使用できます。
<!-- -->
:::

### `のDependencies.swift経由でのCarthage統合を廃止` {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4以前では、Carthage依存関係は`/Dependencies.swift` ファイルで定義でき、ユーザーは`tuist fetch`
を実行して取得できました。しかし、特に将来的にSwift Package
Managerが依存関係管理の主流となることを考慮すると、これはTuistにとってやや無理のある目標だと感じていました。
Carthage依存関係を使用している場合、`Carthage`
を直接実行して事前コンパイル済みフレームワークとXCFrameworksをCarthageの標準ディレクトリに取得し、その後`TargetDependency.xcframework`
および`TargetDependency.framework` のケースで、それらのバイナリをターゲットから参照する必要があります。

::: info CARTHAGE IS STILL SUPPORTED
<!-- -->
一部のユーザーがCarthageのサポートを終了したと誤解していました。終了していません。TuistとCarthageの出力間の契約は、システム保存フレームワークとXCFrameworksに対して行われます。変更されたのは依存関係取得の責任主体のみです。以前はTuistがCarthage経由で行っていましたが、現在はCarthageが行っています。
<!-- -->
:::

### `TargetDependency.packagePlugin` API を削除しました{#dropped-the-targetdependencypackageplugin-api}

Tuist 4以前では、`TargetDependency.packagePlugin`
のケースを使用してパッケージプラグイン依存関係を定義できました。Swift Package
Managerが新しいパッケージタイプを導入したことを受け、より柔軟で将来を見据えたAPIへと進化させることを決定しました。`TargetDependency.packagePlugin`
を使用していた場合は、代わりに`TargetDependency.package` を使用し、使用するパッケージのタイプを引数として渡す必要があります。

### [廃止予定のAPIは削除](https://github.com/tuist/tuist/pull/5560){#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Tuist 3で非推奨とマークされたAPIは削除しました。非推奨APIを使用していた場合は、新しいAPIを使用するようにプロジェクトを更新する必要があります。
