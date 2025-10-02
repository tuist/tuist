---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---
# キャッシュ {#cache}

> [重要】要件
> - 1}生成プロジェクト</LocalizedLink>
> - A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>

Xcode
のビルドシステムは、[インクリメンタルビルド](https://en.wikipedia.org/wiki/Incremental_build_model)
を提供し、通常の状況では効率を高めます。しかし、この機能は[継続的インテグレーション（CI）環境](https://en.wikipedia.org/wiki/Continuous_integration)では不十分であり、インクリメンタルビルドに不可欠なデータは、異なるビルド間で共有されていません。さらに、**開発者は、複雑なコンパイルの問題をトラブルシューティングするために、このデータをローカルでリセットすることがよくあります。**
、クリーンビルドの頻度が高くなります。その結果、チームは、ローカルビルドが終了するのを待ったり、継続的インテグレーションパイプラインがプルリクエストに対するフィードバックを提供するのを待ったりするのに過剰な時間を費やすことになる。さらに、このような環境ではコンテキストの切り替えが頻繁に発生するため、生産性が低下する。

Tuistは、キャッシュ機能によってこれらの課題に効果的に対処している。このツールは、コンパイル済みのバイナリをキャッシュすることでビルドプロセスを最適化し、ローカル開発環境とCI環境の両方でビルド時間を大幅に短縮する。このアプローチは、フィードバックループを加速するだけでなく、コンテキスト切り替えの必要性を最小限に抑え、最終的に生産性を高める。

## 暖かい{#warming}。

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
:::

> [警告]
> バイナリ・キャッシングは、シミュレータやデバイス上でのアプリの実行、テストの実行など、開発ワークフローのために設計された機能です。リリースのビルドを意図したものではありません。アプリをアーカイブする場合は、`--no-binary-cache`
> フラグを使用して、ソースを含むプロジェクトを生成してください。

## 対応製品{#supported-products}。

Tuistでキャッシュ可能なのは以下の対象製品のみである：

- XCTest](https://developer.apple.com/documentation/xctest)に依存しないフレームワーク（静的および動的）。
- バンドル
- スイフト・マクロ

XCTestに依存するライブラリやターゲットのサポートに取り組んでいます。

> [注意] UPSTREAM DEPENDENCIES
> ターゲットがキャッシュ不可能な場合、上流のターゲットもキャッシュ不可能になります。たとえば、依存関係グラフが`A &gt; B`
> で、AがBに依存している場合、Bが非キャッシュ可能であれば、Aも非キャッシュ可能になります。

## 効率性{#efficiency}。

バイナリー・キャッシングで達成できる効率のレベルは、グラフ構造に強く依存する。最良の結果を得るためには、以下を推奨する：

1. 非常にネストした依存関係グラフは避ける。グラフは浅ければ浅いほどよい。
2. 実装の代わりにプロトコル/インターフェースのターゲットで依存関係を定義し、一番上のターゲットから実装を依存関係インジェクトする。
3. 頻繁に変更されるターゲットを、変更の可能性が低い小さなターゲットに分割する。

上記の提案は、<LocalizedLink href="/guides/features/projects/tma-architecture">The
Modular
Architecture</LocalizedLink>の一部であり、バイナリー・キャッシングだけでなく、Xcodeの機能の利点を最大化するためにプロジェクトを構成する方法として提案します。

## 推奨セットアップ {#recommended-setup}

メインブランチ** のコミットごとに**が実行される CI
ジョブを用意して、キャッシュをウォームアップすることをお勧めします。こうすることで、`メインブランチ`
の変更に対応したバイナリが常にキャッシュに含まれるようになり、ローカルブランチと CI ブランチがインクリメンタルにビルドできるようになります。

> [TIP] CACHE WARMING USES BINARIES`tuist cache`
> コマンドは、バイナリーキャッシュも利用してウォームアップを高速化する。

以下は一般的なワークフローの例である：

### 開発者が新機能の開発を始める {#a-developer-starts-to-work-on-a-new-feature}.

1. 彼らは`main` から新しいブランチを作る。
2. 彼らは`を実行し、` を生成する。
3. Tuistは`main` から最新のバイナリを取り出し、それを使ってプロジェクトを生成する。

### 開発者がアップストリームに変更をプッシュする {#a-developer-pushes-changes-upstream}.

1. CIパイプラインは、`tuist build` または`tuist test` を実行して、プロジェクトをビルドまたはテストする。
2. ワークフローは、`main` から最新のバイナリを取り出し、それを使ってプロジェクトを生成する。
3. その後、プロジェクトをインクリメンタルにビルドまたはテストする。

## トラブルシューティング{#troubleshooting}。

### 私のターゲットにはバイナリを使いません {#it-doesnt-use-binaries-for-my-targets}.

1}ハッシュが環境とランにまたがって決定性</LocalizedLink>であることを確認する。これは、プロジェクトが絶対パスなどで環境を参照している場合に発生する可能性があります。`diff`
コマンドを使用すると、`tuist generate`
の2つの連続した呼び出しによって生成されたプロジェクトを比較したり、環境や実行にまたがって比較することができます。

また、ターゲットが<LocalizedLink href="/guides/features/cache#supported-products">キャッシュ不可能なターゲット</LocalizedLink>に直接的にも間接的にも依存していないことを確認してください。
