---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · 選択的テスト · 機能 · ガイド · Tuist",
  "description": "Tuistの選択的テストを使用して、最新の変更の影響を受けたXcodeおよび生成されたプロジェクトのテストのみを実行し、継続的インテグレーションによるフィードバックを数秒で受け取れます。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project}

プロジェクトが大きくなるにつれて、テストの数も増えます。長い間、すべてのPRや`main`へのpushで全テストを実行すると数十秒かかっていました。しかし、この方法ではチームが抱える数千のテストには対応できません。

CI上の各テスト実行では、変更の有無にかかわらず、おそらくすべてのテストを再実行しているでしょう。Tuistの選択的テストは、<.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link>に基づき、最後の成功したテスト実行以降に変更があったテストのみを実行することで、テストの実行速度を大幅に向上させます。

<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link>で選択的にテストを実行するには、`tuist test`コマンドを使用します。このコマンドは<.localized_link href="/guides/features/projects/hashing">ハッシュ</.localized_link>を<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>と同様の方法でプロジェクトに適用し、成功時には将来の実行で変更箇所を特定するためにハッシュを永続化します。以降の実行では、`tuist test`がハッシュを透過的に使用してテストを絞り込み、最後の成功したテスト実行以降に変更があったもののみを実行します。

`tuist test`は<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>と直接統合され、ローカルまたはリモートストレージから可能な限り多くのバイナリを活用して、テストスイート実行時のビルド時間を短縮します。選択的テストとモジュールキャッシュを組み合わせることで、CIでのテスト実行時間を大幅に削減できます。

テスト実行がシミュレータのみを対象とする場合は、`--destination simulator`を指定して、`tuist test`がキャッシュ済みバイナリのシミュレータ用スライスのみを使用・ダウンロードするようにしてください。<.localized_link href="/guides/features/cache/module-cache#destination-selection">デスティネーションの選択</.localized_link>をご覧ください。選択的テストのハッシュは、すべての`--destination`値で同一です。

## ビルドジョブとテストジョブの分離 {#separate-build-and-test-jobs}

選択的テストは、ビルドジョブとテストジョブの分離をサポートしています。ビルドジョブで`tuist test --build-only`を実行すると、Tuistはビルドが出力する成果物 alongside に`selective-testing-graph.json`ファイルを永続化できます。このグラフには選択的テストに必要なハッシュが含まれているため、テストジョブ側でプロジェクトを再生成したりSwift Packageの依存関係を解決したりして、実行対象のターゲットを特定する必要がありません。

Tuistは`--build-only`中にグラフを2箇所に書き出します。

- `-testProductsPath`を指定した場合、`.xctestproducts`バンドル内に書き出されます。
- Derive Dataの`Build/Products/`ディレクトリ配下にある各`.xctestrun`ファイルの隣に書き出されます。

いずれかの出力をビルド成果物 alongside にキャッシュし、テストジョブで同じパスを`--without-building`に渡してください。どちらの形式でも動作します。

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  --derived-data-path artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  --derived-data-path artifacts/derived-data \
  -- \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Tuistが入力 alongside にそのグラフを見つけられない場合（たとえば、ビルドジョブで`tuist test --build-only`ではなく通常の`xcodebuild build-for-testing`を使用した場合など）、影響を受けるターゲットを計算できるようプロジェクトの再生成にフォールバックします。このフォールバックではテストジョブ上でSwift Packageの依存関係を解決する必要があるため、事前に`tuist install`を実行するか、ジョブ間で`Tuist/.build`をキャッシュしてください。

グラフはビルド時点のソースツリーを反映しています。テストジョブはビルドジョブと同じコミットに対して実行してください。両者の間でソースにずれが生じると、ハッシュが古くなり、選択的テストが新しいソースでは実際に失敗するはずのテストをスキップしてしまう可能性があります。

### どのフラグを使用すべきですか？ {#which-flag-should-i-use}

`.xctestrun`と`.xctestproducts`は異なる2つのXcode出力フォーマットであり、ポータビリティとパイプラインの利便性のトレードオフがあります。

- **`-testProductsPath`（`.xctestproducts`）— 新しいパイプラインにおすすめ。** 自己完結型のディレクトリです。ビルド済みの`.xctest`バイナリとその`.xctestrun`ファイルが内部に格納され、パスはバンドルルートからの相対パスになるため、どこに配置しても有効性が保たれます。また、このフォーマットは最も長く選択的テストの高速パスに対応してきたため、最も実績のある経路です。
- **`-xctestrun`（生の`.xctestrun`）— Derive Dataを中心としたパイプラインがすでに構築されている場合に使用してください。**`xcodebuild build-for-testing`はデフォルトで`<derivedData>/Build/Products/`のトップレベルに`.xctestrun`を書き出し、そのツリー内の別の場所にあるテストバンドルを指します。これを別のジョブで再利用するには、`Build/Products/`内のパス構造を維持する必要があります。

新規に始める場合は、`-testProductsPath`を優先してください。Derive Dataをすでにキャッシュしている既存のパイプラインにTuistを組み込む場合は、ビルドジョブが`tuist test --build-only`経由で実行される限り、`-xctestrun`でも同じ高速パスを利用できます。

いずれの入力モードも`-workspace`/`-project`/`-scheme`と排他的であるため、パススルー引数に`-xctestrun`または`-testProductsPath`が含まれる場合、Tuistはそれらのフラグをスキップし、選択されたターゲットを`-only-testing`経由で転送します。

> [!WARNING]
> **モジュール粒度とファイル粒度**
>
> テストとソース間のコード内依存関係を検出することが不可能であるため、選択的テストの最大粒度はターゲットレベルになります。したがって、選択的テストのメリットを最大化するため、ターゲットは小さく焦点を絞った状態に保つことをおすすめします。


> [!NOTE]
> **テストカバレッジ**
>
> 1回の実行レポートを読み取るカバレッジツール（Xcodeのものを含む）は、テストスイート全体が実行されたことを前提としているため、選択的実行のレポートではスキップされたテストが除外されます。Tuistの<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">コードカバレッジ</.localized_link>は、各実行で記録する<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">ターゲットレベルのカバレッジ</.localized_link>を使用し、スキップされたテストターゲットのカバレッジを以前の実行から引き継ぎます。


## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Gitプラットフォームとの連携が必要**
>
> プル/マージリクエストに自動でコメントを投稿するには、<.localized_link href="/guides/server/accounts-and-projects">Tuistプロジェクト</.localized_link>を<.localized_link href="/guides/server/authentication">Gitプラットフォーム</.localized_link>と連携してください。


Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームと接続され、CIワークフローの一部として`tuist test`の使用を開始すると、Tuistはプル/マージリクエストに直接コメントを投稿し、どのテストが実行され、どのテストがスキップされたかを示します。![Tuist Previewリンク付きのGitHubアプリコメント](/images/guides/features/selective-testing/github-app-comment.png)


## ダッシュボードでのミス調査 {#investigating-misses-on-the-dashboard}

以前キャッシュされていたテストターゲットがミスとして表示された場合、テスト実行ページの**選択的テスト**タブで、ハッシュ生成のもととなった入力を詳細に確認できます。行を展開すると、ソース、依存関係、環境変数、プロジェクトおよびターゲットの設定、Info.plist、エンタイトルメント、ヘッダーなどのコンポーネントごとのサブハッシュが表示され、実行間で変化していた入力を特定できます。

選択的テストカードの上部にある**JSONとしてコピー**ボタンを使用して、各選択的テストターゲットのハッシュとサブハッシュをエクスポートしてください。2回の実行間でJSONを比較すると、テストターゲットのハッシュが変化した際に入力のどれが変更されたかを迅速に確認できます。
