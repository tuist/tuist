---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# モジュール・キャッシュ {#module-cache}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/features/projects">生成されたプロジェクト</LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

Tuist Module
cacheは、モジュールをバイナリ（`.xcframework`s）としてキャッシュし、異なる環境間で共有することでビルド時間を最適化する強力な手段を提供します。この機能により、事前に生成されたバイナリを活用でき、繰り返しのコンパイルの必要性を減らし、開発プロセスを高速化します。

## 注意{#warming}

Tuistは依存関係グラフ内の各ターゲットに対してハッシュを効率的に利用し、変更を検出します。このデータを活用して、これらのターゲットから派生したバイナリに固有の識別子を構築・割り当てます。グラフ生成時には、Tuistが元のターゲットを対応するバイナリ版にシームレスに置換します。

この操作は「* 」の「warming」として知られており、*
はローカル使用またはTuist経由でのチームメイトやCI環境との共有用のバイナリを生成します。キャッシュのウォーミングプロセスは単純明快で、簡単なコマンドで開始できます：


```bash
tuist cache
```

このコマンドは処理を高速化するため、バイナリを再利用します。

## 使用法 {#usage}

デフォルトでは、Tuistコマンドがプロジェクト生成を必要とする場合、利用可能な場合、依存関係をキャッシュ内のバイナリ相当物で自動的に置換します。さらに、対象とするターゲットのリストを指定した場合、Tuistは利用可能な場合、依存するターゲットもキャッシュされたバイナリで置換します。異なるアプローチを好むユーザー向けに、特定のフラグを使用してこの動作を完全に無効化するオプションがあります：

コードグループ
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: 警告
<!-- -->
バイナリキャッシュは、シミュレータやデバイスでのアプリ実行、テスト実行などの開発ワークフロー向けに設計された機能です。リリースビルドを目的としたものではありません。アプリをアーカイブする際は、`--cache-profile
none` を実行し、ソースを含むプロジェクトを生成してください。
<!-- -->
:::

## キャッシュプロファイル{#cache-profiles}

Tuistは、プロジェクト生成時にターゲットがキャッシュ済みバイナリで置き換えられる頻度を制御するキャッシュプロファイルをサポートしています。

- 組み込み関数:
  - `only-external`: 外部依存関係のみを置換（システムデフォルト）
  - `可能な限り多くのターゲットを置換（内部ターゲットを含む）: all-possible`
  - `none`: キャッシュされたバイナリで置き換えない

`--cache-profile` on`tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

::: info DEPRECATED FLAG
<!-- -->
`--no-binary-cache` フラグは非推奨です。代わりに`--cache-profile none`
を使用してください。非推奨フラグは下位互換性のため引き続き機能します。
<!-- -->
:::

有効な動作を解決する際の優先順位（高い順）：

1. `--cache-profile none`
2. ターゲットフォーカス（`へのターゲット渡しが` を生成）→プロファイル`全可能性`
3. `--cache-profile <value>`</value>
4. 設定デフォルト（設定されている場合）
5. システムデフォルト (`only-external`)

## 対応製品{#supported-products}

Tuistでキャッシュ可能な対象製品は以下の通りです：

- [XCTest](https://developer.apple.com/documentation/xctest)に依存しないフレームワーク（静的および動的）
- バンドル
- Swift マクロ

XCTestに依存するライブラリとターゲットのサポートに取り組んでいます。

::: info UPSTREAM DEPENDENCIES
<!-- -->
ターゲットが非キャッシュ可能の場合、上流のターゲットも非キャッシュ可能になります。例えば、依存関係グラフが`A &gt; B` の場合、A が B
に依存しており、B が非キャッシュ可能であれば、A も非キャッシュ可能になります。
<!-- -->
:::

## 効率性{#efficiency}

バイナリキャッシュで達成可能な効率性は、グラフ構造に大きく依存します。最適な結果を得るためには、以下のことを推奨します：

1. 非常に深い依存関係グラフは避けてください。グラフは浅いほど良いです。
2. 依存関係は実装ではなくプロトコル/インターフェースターゲットで定義し、最上位ターゲットから実装を依存性注入する。
3. 頻繁に変更されるターゲットは、変更可能性が低い小さなターゲットに分割してください。

上記の提案は、バイナリキャッシュだけでなくXcodeの機能も最大限に活用するためのプロジェクト構造化手法として提案する<LocalizedLink href="/guides/features/projects/tma-architecture">モジュラーアーキテクチャ</LocalizedLink>の一部です。

## 推奨設定{#recommended-setup}

メインブランチ（** ）では、**がコミットごとに実行される CI
ジョブを用意し、キャッシュをウォームアップすることを推奨します。これにより、キャッシュには常に`main` の変更に対応したバイナリが含まれ、ローカルブランチと
CI ブランチのビルドがそれらを基盤に増分的に行われるようになります。

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` コマンドもバイナリキャッシュを利用してウォームアップを高速化します。
<!-- -->
:::

以下に一般的なワークフローの例を示します：

### 開発者が新機能の開発を開始する{#a-developer-starts-to-work-on-a-new-feature}

1. `main` から新しいブランチを作成します。
2. They run`tuist generate`.
3. Tuistは`main` から最新のバイナリを取得し、それらを用いてプロジェクトを生成します。

### 開発者が変更をアップストリームにプッシュする{#a-developer-pushes-changes-upstream}

1. CIパイプラインはプロジェクトのビルドまたはテストを実行するため、以下のコマンドを実行します：`xcodebuild build` または`tuist
   test`
2. ワークフローは、`main` から最新のバイナリを取得し、それらを使用してプロジェクトを生成します。
3. その後、プロジェクトを段階的にビルドまたはテストします。

## コンフィギュレーション {#configuration}

### キャッシュの同時アクセス制限{#cache-concurrency-limit}

デフォルトでは、Tuistはキャッシュアーティファクトのダウンロードおよびアップロードを並列制限なしで実行し、スループットを最大化します。この動作は、`TUIST_CACHE_CONCURRENCY_LIMIT`
環境変数を使用して制御できます：

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

これは、ネットワーク帯域幅が限られている環境や、キャッシュ操作中のシステム負荷を軽減するのに役立つ場合があります。

## トラブルシューティング{#troubleshooting}

### 私のターゲットではバイナリを使用しません{#it-doesnt-use-binaries-for-my-targets}

<LocalizedLink href="/guides/features/projects/hashing#debugging">ハッシュが環境や実行回数を跨いで</LocalizedLink>確定的であることを保証してください。これは、プロジェクトが絶対パスなどを通じて環境に参照している場合に発生する可能性があります。`diff`
コマンドを使用して、`tuist generate` を連続して呼び出した際に生成されるプロジェクトを比較したり、環境や実行回数を跨いで比較したりできます。

また、対象が<LocalizedLink href="/guides/features/cache/generated-project#supported-products">非キャッシュ対象</LocalizedLink>に直接的または間接的に依存しないことを確認してください。

### 欠落している記号{#missing-symbols}

ソースを使用する場合、Xcodeのビルドシステムは派生データを通じて明示的に宣言されていない依存関係を解決できます。ただし、バイナリキャッシュに依存する場合は、依存関係を明示的に宣言する必要があります。そうしないと、シンボルが見つからない場合にコンパイルエラーが発生する可能性があります。これをデバッグするには、<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist
inspect dependencies --only implicit`</LocalizedLink>
コマンドの使用と、CIでの設定を推奨します。これにより、暗黙的リンクの退行を防止できます。

### レガシーモジュールキャッシュ{#legacy-module-cache}

Tuist`4.128.0`
では、モジュールキャッシュの新インフラストラクチャをデフォルトとしました。この新バージョンで問題が発生した場合、環境変数`TUIST_LEGACY_MODULE_CACHE`
を設定することで、従来のキャッシュ動作に戻すことができます。

このレガシーモジュールキャッシュは一時的な代替手段であり、今後のアップデートでサーバー側から削除されます。移行計画を立ててください。

```bash
export TUIST_LEGACY_MODULE_CACHE=1
tuist generate
```
