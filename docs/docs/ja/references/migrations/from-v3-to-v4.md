---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# Tuist v3からv4へ{#from-tuist-v3-to-v4}。

Tuist
4](https://github.com/tuist/tuist/releases/tag/4.0.0)のリリースに伴い、私たちはプロジェクトにいくつかの変更点を導入する機会を得ました。この文書では、Tuist
3からTuist 4にアップグレードするためにプロジェクトに加える必要のある変更について概説します。

### `tuistenv` {#dropped-version-management-through-tuistenv} によるバージョン管理の廃止。

Tuist 4以前は、インストールスクリプトは`tuistenv` というツールをインストールし、インストール時に`tuist`
という名前に変更された。このツールはTuistのバージョンのインストールとアクティベーションを担当し、環境間の決定性を保証する。Tuistのフィーチャー・サーフェスを減らす目的で、私たちは`tuistenv`
をやめ、[Mise](https://mise.jdx.dev/)を採用することにしました。これは同じ仕事をするツールですが、より柔軟で、異なるツール間で使用することができます。`tuistenv`
を使用していた場合は、`curl -Ls https://uninstall.tuist.io | bash`
を実行して現在のバージョンのTuistをアンインストールし、その後、お好みのインストール方法でインストールしてください。Miseの利用を強くお勧めします。なぜならMiseは環境間で決定論的にインストールとアクティベーションができるからです。

コードグループ

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
:::

> [重要] CI環境とXCODEプロジェクトでのMISE
> Miseがもたらす決定論を全面的に受け入れることを決めた場合、[CI環境](https://mise.jdx.dev/continuous-integration.html)と[Xcodeプロジェクト](https://mise.jdx.dev/ide-integration.html#xcode)でのMiseの使い方のドキュメントをチェックすることをお勧めします。

> [注意] HOMEBREW IS SUPPORTED
> macOS用の一般的なパッケージマネージャであるHomebrewを使用してもTuistをインストールできることに注意してください。Homebrewを使ってTuistをインストールする方法は<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">インストールガイド</LocalizedLink>にあります。

### Dropped`init` constructors from`ProjectDescription` models {#dropped-init-constructors-from-projectdescription-models}.

APIの可読性と表現力を向上させる目的で、`init` コンストラクタをすべての`ProjectDescription`
モデルから削除することにしました。すべてのモデルは、モデルのインスタンスを生成するために使うことができる静的なコンストラクタを提供するようになりました。`init`
コンストラクタを使用していた場合は、代わりに静的コンストラクタを使用するようにプロジェクトを更新する必要があります。

> [ヒント] 命名規約 私たちが従う命名規約は、静的コンストラクタの名前としてモデルの名前を使うことです。例えば、`Target`
> モデルの静的コンストラクタは`Target.target` です。

### `--no-cache` を`--no-binary-cache` {#renamed-nocache-to-nobinarycache} にリネーム。

`--no-cache` フラグがあいまいだったので、バイナリ・キャッシュを指すことを明確にするために、`--no-binary-cache`
に名前を変更することにしました。`--no-cache` フラグを使用していた場合は、代わりに`--no-binary-cache`
フラグを使用するようにプロジェクトを更新する必要があります。

### `tuist fetch` を`tuist install` {#renamed-tuist-fetch-to-tuist-install} にリネーム。

業界の慣例に合わせるため、`tuist fetch` コマンドの名前を`tuist install` に変更しました。`tuist fetch`
コマンドを使っていた場合は、代わりに`tuist install` コマンドを使うようにプロジェクトを更新する必要があります。

### [`Package.swift` を依存関係の DSL として採用](https://github.com/tuist/tuist/pull/5862)。{#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}。

Tuist 4以前は、`Dependencies.swift`
ファイルで依存関係を定義できました。この独自形式は、[Dependabot](https://github.com/dependabot)や[Renovatebot](https://github.com/renovatebot/renovate)のようなツールで依存関係を自動的に更新するサポートを壊していた。さらに、ユーザーにとって不必要な間接参照を導入していました。そこで、`Package.swift`
をTuistで依存関係を定義する唯一の方法として採用することにしました。`Dependencies.swift`
ファイルを使用していた場合、`Tuist/Dependencies.swift` の内容をルートにある`Package.swift` に移動し、`#if
TUIST`
ディレクティブを使用して統合を設定する必要があります。Swiftパッケージの依存関係を統合する方法<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">についてはこちらをご覧ください。</LocalizedLink>

### `tuist cache warm` を`tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache} にリネーム。

簡潔にするため、`tuist cache warm` コマンドの名前を、`tuist cache` に変更することにしました。`tuist cache
warm` コマンドを使っていた場合は、代わりに`tuist cache` コマンドを使うようにプロジェクトを更新する必要があります。


### `tuist cache print-hashes` を`tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes} に変更。

私たちは、`tuist cache print-hashes` コマンドの名前を、`tuist cache --print-hashes`
に変更し、`tuist cache` コマンドのフラグであることを明確にすることにしました。`tuist cache print-hashes`
コマンドを使っていた場合は、代わりに`tuist cache --print-hashes` フラグを使うようにプロジェクトを更新する必要があります。

### キャッシング・プロファイルの削除{#removed-caching-profiles}。

Tuist 4以前は、`Tuist/Config.swift`
にキャッシュ用プロファイルを定義することができ、その中にキャッシュ用の設定が含まれていました。この機能を削除することにしたのは、プロジェクトの生成に使用したプロファイル以外のプロファイルを生成プロセスで使用すると混乱につながる可能性があったからです。さらに、ユーザーがアプリのリリースバージョンをビルドするためにデバッグプロファイルを使用することにつながり、予期しない結果につながる可能性があります。その代わりに、`--configuration`
オプションを導入しました。このオプションを使うと、プロジェクトの生成時に使用する設定を指定できます。キャッシング・プロファイルを使用していた場合は、代わりに`--configuration`
オプションを使用するようにプロジェクトを更新する必要があります。

### `--skip-cache` を削除し、引数を優先 {#removed-skipcache-in-favor-of-arguments}.

`generate` コマンドから`--skip-cache`
フラグを削除し、引数を使用してバイナリキャッシュをスキップするターゲットを制御するようにしました。`--skip-cache`
フラグを使用していた場合は、代わりに引数を使用するようにプロジェクトを更新する必要があります。

コードグループ

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
:::

### [削除された署名機能](https://github.com/tuist/tuist/pull/5716)。{#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}。

署名は、[Fastlane](https://fastlane.tools/)やXcode自体のようなコミュニティツールによってすでに解決されており、それらの方がはるかに良い仕事をしている。私たちは、署名はTuistのストレッチゴールであり、プロジェクトのコア機能に集中した方が良いと考えました。リポジトリ内の証明書とプロファイルを暗号化し、生成時に適切な場所にインストールすることで構成されるTuistの署名機能を使用していた場合、プロジェクト生成前に実行する独自のスクリプトでそのロジックを複製したいと思うかもしれません。特に
  - ファイルシステムまたは環境変数に格納されているキーを使用して証明書とプロ
    ファイルを復号化し、証明書をキーチェーンに、プロビジョニング・プロファイルをディレク
    トリ`~/Library/MobileDevice/Provisioning Profiles` にインストールするスクリプト。
  - 既存のプロファイルと証明書を取り込んで暗号化するスクリプト。

> [署名には、正しい証明書がキーチェーンに存在し、プロビジョニング・プロファイルが`~/Library/MobileDevice/Provisioning
> Profiles` ディレクトリに存在することが必要である。キーチェーンに証明書をインストールするには`security`
> コマンドラインツールを使用し、プロビジョニング・プロファイルを正しいディレクトリにコピーするには`cp` コマンドを使用します。

### `Dependencies.swift` {#dropped-carthage-integration-via-dependenciesswift} によるカルタゴ統合を削除した。

Tuist 4以前は、Carthageの依存関係は`Dependencies.swift` ファイルで定義することができ、ユーザーは`tuist fetch`
を実行することでそれを取得することができました。私たちはまた、Swiftパッケージマネージャが依存関係を管理するための望ましい方法である将来を考慮し、これはTuistのためのストレッチゴールであると感じました。Carthage
依存関係を使用していた場合、`Carthage` を直接使用して、コンパイル済みのフレームワークと XCFrameworks を Carthage
の標準ディレクトリにプルし、`TargetDependency.xcframework` と`TargetDependency.framework`
のケースを使用してタグセットからこれらのバイナリを参照する必要があります。

> [注意] Carthageはまだサポートされています
> 一部のユーザーは、私たちがCarthageのサポートを停止したと理解していました。そうではありません。TuistとCarthageの出力の間の契約は、システムに格納されたフレームワークとXCFrameworksに対するものです。唯一変わったのは、誰が依存関係のフェッチに責任を持つかということです。以前はCarthageを通してTuistでしたが、今はCarthageです。

### `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api} を削除しました。

Tuist 4以前は、`TargetDependency.packagePlugin`
caseを使用してパッケージプラグイン依存関係を定義することができました。Swiftパッケージマネージャが新しいパッケージタイプを導入するのを見た後、私たちはより柔軟で将来性のあるものに向けてAPIを反復することにしました。`TargetDependency.packagePlugin`
を使用していた場合、代わりに`TargetDependency.package` を使用し、引数として使用したいパッケージのタイプを渡す必要があります。

### [廃止された非推奨API](https://github.com/tuist/tuist/pull/5560)。{#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}。

Tuist
3で非推奨とされたAPIを削除しました。非推奨APIのいずれかを使用していた場合は、新しいAPIを使用するようにプロジェクトを更新する必要があります。
