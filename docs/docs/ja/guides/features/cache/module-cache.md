---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# モジュール・キャッシュ {#module-cache}

::: warning 要件
<!-- -->
- <LocalizedLink href="/guides/features/projects">生成プロジェクト</LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

Tuistモジュールキャッシュは、モジュールをバイナリ(`.xcframework`s)としてキャッシュし、異なる環境間で共有することで、ビルド時間を最適化する強力な方法を提供します。この機能により、以前に生成されたバイナリを活用し、コンパイルを繰り返す必要性を減らし、開発プロセスを高速化することができます。

## 温暖化{#warming}

Tuistは効率的に<LocalizedLink href="/guides/features/projects/hashing">、依存グラフの各ターゲットのハッシュ</LocalizedLink>を利用して変更を検出する。このデータを利用して、これらのターゲットから派生したバイナリに一意の識別子を構築して割り当てる。そしてグラフ生成時に、Tuistは元のターゲットを対応するバイナリバージョンでシームレスに置換する。

*"ウォーミング "として知られるこの操作は、*
、ローカルで使用したり、Tuist経由でチームメイトやCI環境と共有したりするためのバイナリを生成する。キャッシュをウォームアップするプロセスは簡単で、簡単なコマンドで開始できる：


```bash
tuist cache
```

このコマンドはバイナリを再利用して処理を高速化する。

## 使用法 {#usage}

デフォルトでは、Tuistコマンドがプロジェクト生成を必要とする場合、利用可能であれば、依存関係を自動的にキャッシュから同等のバイナリに置き換える。さらに、フォーカスするターゲットのリストを指定すると、Tuistは依存するターゲットも、それらが利用可能であれば、キャッシュされたバイナリに置き換える。異なるアプローチを好む人のために、特定のフラグを使用することでこの動作を完全にオプトアウトするオプションがある：

コードグループ
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: 警告
<!-- -->
バイナリ・キャッシングは、シミュレータやデバイス上でのアプリの実行、テストの実行など、開発ワークフローのために設計された機能です。リリースのビルドを意図したものではありません。アプリをアーカイブする場合は、`--no-binary-cache`
フラグを使用して、ソースを含むプロジェクトを生成してください。
<!-- -->
:::

## キャッシュ・プロファイル{#cache-profiles}

Tuistはキャッシュ・プロファイルをサポートしており、プロジェクトを生成する際に、どの程度積極的にターゲットをキャッシュ・バイナリに置き換えるかを制御できる。

- ビルトイン：
  - `only-external`: 外部依存関係のみを置き換える (システムデフォルト)
  - `all-possible`: できるだけ多くのターゲット（内部ターゲットも含む）を入れ替える。
  - `none`: キャッシュされたバイナリに置き換えない

`--cache-profile` on`tuist generate` でプロファイルを選択する：

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely (backwards compatible)
tuist generate --no-binary-cache  # equivalent to --cache-profile none
```

有効な行動を解決する際の優先順位（高いものから低いものへ）：

1. `--no-binary-cache` → profile`none`
2. ターゲット・フォーカス（ターゲットを`に渡す` を生成） → プロファイル`すべて可能`
3. `--キャッシュ・プロファイル &lt;値`
4. 設定デフォルト（設定されている場合）
5. システム・デフォルト (`のみ-外部`)

## 対応製品{#supported-products}

Tuistでキャッシュ可能なのは以下の対象製品のみである：

- XCTest](https://developer.apple.com/documentation/xctest)に依存しないフレームワーク（静的および動的）。
- バンドル
- スイフト・マクロ

XCTestに依存するライブラリやターゲットのサポートに取り組んでいます。

::: info UPSTREAM DEPENDENCIES
<!-- -->
ターゲットがキャッシュ不可能になると、上流のターゲットもキャッシュ不可能になる。たとえば、依存グラフが`A &gt; B`
で、AがBに依存している場合、Bが非キャッシュ可能であれば、Aも非キャッシュ可能になります。
<!-- -->
:::

## 効率性{#efficiency}

バイナリー・キャッシングで達成できる効率のレベルは、グラフ構造に強く依存する。最良の結果を得るためには、以下を推奨する：

1. 非常にネストした依存関係グラフは避ける。グラフは浅ければ浅いほどよい。
2. 実装の代わりにプロトコル/インターフェースのターゲットで依存関係を定義し、一番上のターゲットから実装を依存関係インジェクトする。
3. 頻繁に変更されるターゲットを、変更の可能性が低い小さなターゲットに分割する。

上記の提案は、<LocalizedLink href="/guides/features/projects/tma-architecture">The Modular Architecture</LocalizedLink>の一部であり、バイナリー・キャッシングだけでなく、Xcodeの機能の利点を最大化するためにプロジェクトを構成する方法として提案します。

## 推奨セットアップ{#recommended-setup}

メインブランチ** のコミットごとに**が実行される CI
ジョブを用意して、キャッシュをウォームアップすることをお勧めします。こうすることで、`メインブランチ`
の変更に対応したバイナリが常にキャッシュに含まれるようになり、ローカルブランチと CI ブランチがインクリメンタルにビルドできるようになります。

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` コマンドもバイナリーキャッシュを利用してウォーミングアップを高速化する。
<!-- -->
:::

以下は一般的なワークフローの例である：

### 開発者が新機能の開発に取りかかる{#a-developer-starts-to-work-on-a-new-feature}

1. 彼らは`main` から新しいブランチを作る。
2. 彼らは`を実行し、` を生成する。
3. Tuistは`main` から最新のバイナリを取り出し、それを使ってプロジェクトを生成する。

### 開発者が変更を上流にプッシュする{#a-developer-pushes-changes-upstream}

1. CIパイプラインは、`xcodebuild build` または`tuist test` を実行し、プロジェクトをビルドまたはテストする。
2. ワークフローは、`main` から最新のバイナリを取り出し、それを使ってプロジェクトを生成する。
3. その後、プロジェクトをインクリメンタルにビルドまたはテストする。

## コンフィギュレーション {#configuration}

### キャッシュの同時実行数制限{#cache-concurrency-limit}

デフォルトでは、Tuistはスループットを最大化するために、同時実行数制限なしでキャッシュアーティファクトをダウンロードおよびアップロードします。この動作は、`TUIST_CACHE_CONCURRENCY_LIMIT`
環境変数を使用して制御できます：

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

これは、ネットワーク帯域幅が制限されている環境や、キャッシュ操作中のシステム負荷を軽減するのに有効である。

## トラブルシューティング{#troubleshooting}

### 私のターゲットにはバイナリーを使わない{#it-doesnt-use-binaries-for-my-targets}

<LocalizedLink href="/guides/features/projects/hashing#debugging">ハッシュが環境とランにまたがって決定性</LocalizedLink>であることを確認する。これは、プロジェクトが絶対パスなどで環境を参照している場合に発生する可能性があります。`diff`
コマンドを使用すると、`tuist generate`
の2つの連続した呼び出しによって生成されたプロジェクトを比較したり、環境や実行にまたがって比較することができます。

また、ターゲットが<LocalizedLink href="/guides/features/cache/generated-project#supported-products">キャッシュ不可能なターゲット</LocalizedLink>に直接的にも間接的にも依存していないことを確認してください。

### 記号の欠落{#missing-symbols}

ソースを使用する場合、Xcode のビルドシステムは、Derived Data
を通じて、明示的に宣言されていない依存関係を解決することができます。しかし、バイナリキャッシュに依存する場合、依存関係は明示的に宣言されなければなりません。そうしないと、シンボルが見つからないときにコンパイルエラーが発生する可能性が高い。これをデバッグするには、暗黙リンクのリグレッションを防ぐために、<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect implicit-imports`</LocalizedLink>コマンドを使い、CIで設定することを推奨する。
