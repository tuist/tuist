---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · 選択的テスト · 機能 · ガイド · Tuist",
  "description": "Tuistの選択的テストを使用すると、最新の変更の影響を受けたXcodeおよび生成プロジェクトのテストのみを実行できるため、継続的インテグレーションによるフィードバックが数秒で届きます。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project}

プロジェクトが大きくなるにつれて、テストの数も増えます。長年、すべてのPRや `main` へのプッシュですべてのテストを実行するのに数十秒かかっていました。しかし、この方法ではチームが抱える数千のテストにはスケールしません。

CI上のすべてのテスト実行で、変更の有無にかかわらず、おそらくすべてのテストを再実行しているでしょう。Tuistの選択的テストは、<.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link>に基づき、最後の成功したテスト実行以降に変更されたテストのみを実行することで、テストの実行自体を大幅に高速化します。

<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link>で選択的テストを実行するには、`tuist test`コマンドを使用します。このコマンドは<.localized_link href="/guides/features/projects/hashing">モジュールキャッシュ</.localized_link>と同様の方法でプロジェクトを<.localized_link href="/guides/features/cache/module-cache">ハッシュ化</.localized_link>し、成功するとそのハッシュを保存して、次回の実行時に変更があった部分を特定します。次回の実行では、`tuist test`がハッシュを透過的に使用してテストを絞り込み、前回正常に完了したテスト実行以降に変更があったもののみを実行します。

`tuist test`は<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>と直接統合され、ローカルまたはリモートストレージから可能な限り多くのバイナリを使用して、テストスイートの実行時のビルド時間を短縮します。選択的テストとモジュールキャッシングを組み合わせることで、CIでのテスト実行時間を大幅に削減できます。

## ビルドジョブとテストジョブの分離 {#separate-build-and-test-jobs}

選択的テストは、ビルドジョブとテストジョブの分離をサポートしています。ビルドジョブで `tuist test --build-only` を実行し、Tuistがビルド成果物 alongside に `selective-testing-graph.json` ファイルを永続化できるようにします。このグラフには選択的テストに必要なハッシュが含まれているため、テストジョブでプロジェクトを再生成したり、Swift Packageの依存関係を解決して実行対象のターゲットを特定したりする必要がありません。

Tuistは `--build-only` の間にグラフを2箇所に書き出します:

- `-testProductsPath` を指定した場合、`.xctestproducts` バンドル内。
- Derived Dataの `Build/Products/` ディレクトリ配下にある各 `.xctestrun` ファイルの隣。

いずれかの出力をビルド成果物 alongside にキャッシュし、テストジョブの `--without-building` に同じパスを渡します。どちらの形式でも動作します:

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

Tuistが入力の隣にそのグラフを見つけられない場合（例えば、ビルドジョブで `tuist test --build-only` ではなく通常の `xcodebuild build-for-testing` を使用した場合）、影響を受けるターゲットを計算できるようプロジェクトの再生成にフォールバックします。このフォールバックでは、テストジョブでSwift Packageの依存関係を解決する必要があるため、事前に `tuist install` を実行するか、ジョブ間で `Tuist/.build` をキャッシュしてください。

グラフはビルド時点のソースツリーを反映しています。テストジョブはビルドジョブと同じコミットに対して実行してください。両者の間でソースにずれが生じると、ハッシュが古くなり、選択的テストが新しいソースでは実際に失敗するはずのテストをスキップしてしまう可能性があります。

### どのフラグを使用すべきですか？ {#which-flag-should-i-use}

`.xctestrun` と `.xctestproducts` は異なる2つのXcode出力形式であり、ポータビリティとパイプラインの利便性のトレードオフがあります:

- **`-testProductsPath` (`.xctestproducts`) — 新しいパイプラインにおすすめ。** これは自己完結型のディレクトリです。ビルドされた `.xctest` バイナリとその `.xctestrun` ファイルが内部に格納され、パスはバンドルルートからの相対パスになるため、どこに移動しても有効です。また、この形式は最も長い間選択的テストの高速パスを持っていたため、最も実績のあるパスです。
- **`-xctestrun` (生の `.xctestrun`) — Derived Dataを中心としたパイプラインを既に構築している場合に使用します。** `xcodebuild build-for-testing` はデフォルトで `<derivedData>/Build/Products/` のトップレベルに `.xctestrun` を書き出し、そのツリー内の他の場所にあるテストバンドルを指します。別のジョブでこれを再利用するには、`Build/Products/` 内のパスをそのまま維持する必要があります。

新しく始める場合は、`-testProductsPath` を優先してください。Derived Dataを既にキャッシュしている既存のパイプラインにTuistを組み込む場合、ビルドジョブが `tuist test --build-only` を経由して実行される限り、`-xctestrun` でも同じ高速パスを利用できます。

いずれの入力モードも `-workspace`/`-project`/`-scheme` と排他的であるため、パススルー引数に `-xctestrun` または `-testProductsPath` が含まれる場合、Tuistはこれらのフラグをスキップし、選択されたターゲットを `-only-testing` を介して転送します。

> [!WARNING]
> **モジュール単位 vs ファイル単位の粒度**
>
> テストとソース間のコード内依存関係を検出することが不可能であるため、選択的テストの最大粒度はターゲットレベルになります。したがって、選択的テストのメリットを最大化するために、ターゲットを小さく焦点を絞った状態に保つことをおすすめします。


> [!WARNING]
> **テストカバレッジ**
>
> テストカバレッジツールは、テストスイート全体が一度に実行されることを前提としているため、選択的テスト実行とは互換性がありません。つまり、テスト選択を使用する場合、カバレッジデータが実態を反映しない可能性があります。これは既知の制限事項であり、あなたが何か間違っているわけではありません。この文脈でカバレッジが依然として意味のある洞察をもたらしているかどうかを検討することをおすすめします。もしそうであれば、将来的に選択的実行でカバレッジが適切に機能するようにする方法を既に検討中ですのでご安心ください。


## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Gitプラットフォームとの統合が必要**
>
> プル/マージリクエストのコメントを自動的に取得するには、<.localized_link href="/guides/server/accounts-and-projects">Tuistプロジェクト</.localized_link> を <.localized_link href="/guides/server/authentication">Gitプラットフォーム</.localized_link> と統合してください。


Tuistプロジェクトが [GitHub](https://github.com) などのGitプラットフォームと接続され、CIワークフローの一部として `tuist test` の使用を開始すると、Tuistはプル/マージリクエストに直接コメントを投稿し、どのテストが実行され、どのテストがスキップされたかを含めます: ![Tuist Previewリンクを含むGitHubアプリのコメント](/images/guides/features/selective-testing/github-app-comment.png)


## ダッシュボードでのミス調査 {#investigating-misses-on-the-dashboard}

以前キャッシュされていたテストターゲットがミスとして表示された場合、テスト実行ページの **選択的テスト** タブで、ハッシュを生成した入力を詳細に確認できます。行を展開すると、ソース、依存関係、環境変数、プロジェクトおよびターゲットの設定、Info.plist、Entitlements、ヘッダーなどのコンポーネントごとのサブハッシュが表示され、実行間でずれた入力を特定できます。

選択的テストカードの上部にある **JSONとしてコピー** ボタンを使用して、すべての選択的テストターゲットとそのハッシュ、サブハッシュをエクスポートします。2回の実行間でJSONを比較することは、テストターゲットのハッシュがずれた際にどの入力を変更したかを確認する最速の方法です。
