---
{
  "title": "プロジェクト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Swift で Xcode プロジェクトを定義し、Tuist を使って一貫して生成します。マージコンフリクトを解消し、依存関係をグラフとしてモデル化し、モジュールキャッシュを活用できます。"
}
---
# 生成されたプロジェクト {#generated-projects}

Tuist の生成されたプロジェクトは、複雑さとコストを許容範囲内に抑えながらこれらの課題を克服するための現実的な代替手段です。Xcode プロジェクトを基本要素と位置づけ、将来の Xcode アップデートに対する耐性を確保し、Xcode プロジェクトの生成を活用して、モジュール化に重点を置いた宣言型 API をチームに提供します。Tuist はプロジェクト定義を用いてモジュール化の複雑さを簡素化し、さまざまな環境でのビルドやテストといったワークフローを最適化し、Xcode プロジェクトの進化を促進・民主化します。

## 仕組み {#how-does-it-work}

生成されたプロジェクトを始めるには、**Tuist のドメイン固有言語（DSL）** を使ってプロジェクトを定義するだけで済みます。これには、`Workspace.swift` や `Project.swift` などのマニフェストファイルを使用します。Swift Package Manager を使ったことがあれば、そのアプローチは非常に似ています。

プロジェクトを定義すると、Tuist はそれを管理・操作するためのさまざまなワークフローを提供します。

- **Generate:** これは基本的なワークフローです。Xcode と互換性のある Xcode プロジェクトを作成するために使用します。
- **<.localized_link href="/cli/build">Build</.localized_link>:** このワークフローは Xcode プロジェクトを生成するだけでなく、`xcodebuild` を使ってコンパイルも実行します。
- **<.localized_link href="/cli/test">Test</.localized_link>:** ビルドワークフローと同様に動作し、Xcode プロジェクトを生成するだけでなく、`xcodebuild` を使ってテストを実行します。

## Xcode プロジェクトの課題 {#challenges-with-xcode-projects}

Xcode プロジェクトが大きくなるにつれて、**組織の生産性が低下する可能性があります**。その要因としては、信頼性の低い増分ビルド、問題に遭遇した開発者による Xcode のグローバルキャッシュの頻繁なクリア、脆弱なプロジェクト設定などが挙げられます。迅速な機能開発を維持するため、組織は通常、さまざまな戦略を検討します。

一部の組織は、[React Native](https://reactnative.dev/) のような JavaScript ベースの動的ランタイムを使ってプラットフォームを抽象化することで、コンパイラを回避することを選択します。このアプローチは効果的かもしれませんが、[プラットフォームのネイティブ機能へのアクセスが複雑化](https://shopify.engineering/building-app-clip-react-native)します。他の組織は、**コードベースのモジュール化**を選択し、明確な境界を設けることでコードベースの扱いやすさを高め、ビルド時間の信頼性を向上させます。しかし、Xcode プロジェクト形式はモジュール化向けに設計されておらず、理解できる人が少なく頻繁なコンフリクトを引き起こす暗黙的な設定につながります。これはバス係数を悪化させ、増分ビルドが改善される場合でも、ビルドが失敗した際に開発者が Xcode のビルドキャッシュ（派生データ）を頻繁にクリアすることがあります。この問題に対処するため、一部の組織は **Xcode のビルドシステムを放棄** し、[Buck](https://buck.build/) や [Bazel](https://bazel.build/) などの代替手段を採用することを選択します。ただし、これには [高い複雑さとメンテナンス負担](https://bazel.build/migrate/xcode) が伴います。


## 代替手段 {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager（SPM）は主に依存関係に焦点を当てていますが、Tuist は異なるアプローチを提供します。Tuist では、SPM 統合のためのパッケージを定義するだけでなく、プロジェクト、ワークスペース、ターゲット、スキームといった馴染みのある概念を使ってプロジェクトを構築します。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) は、共同作業を行う Xcode プロジェクトでのコンフリクトを減らし、Xcode の内部動作の複雑さの一部を簡素化するために設計された専用プロジェクトジェネレーターです。ただし、プロジェクトは [YAML](https://yaml.org/) のようなシリアライズ可能な形式で定義されます。Swift とは異なり、追加のツールを組み込まないと抽象化やチェックの上に構築することができません。XcodeGen は検証と最適化のために依存関係を内部表現にマッピングする方法を提供していますが、それでも開発者は Xcode の細かな仕様にさらされます。このため、Bazel コミュニティで見られるように、XcodeGen は [ツール構築](https://github.com/MobileNativeFoundation/rules_xcodeproj) の適切な基盤となる可能性がありますが、健全で生産的な環境を維持することを目的とした包括的なプロジェクト進化には最適ではありません。現在 XcodeGen を使用している場合、[XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) では、既存の XcodeGen プロジェクトでどの Tuist 機能が利用できるかが説明されています。Tuist の生成されたプロジェクトに移行するには、<.localized_link href="/guides/features/projects/adoption/migrate/xcodegen-project">移行ガイド</.localized_link>を参照してください。

### Bazel {#bazel}

[Bazel](https://bazel.build) はリモートキャッシング機能で知られる高度なビルドシステムであり、主にこの機能によって Swift コミュニティ内で人気を集めています。しかし、Xcode とそのビルドシステムの拡張性は限られているため、これを Bazel のシステムに置き換えるには多大な努力とメンテナンスが必要です。このオーバーヘッドを負担できるのは豊富なリソースを持つ少数の企業に限られ、Bazel と Xcode の統合に多額の投資を行っている企業の限定されたリストからも明らかです。興味深いことに、コミュニティは Bazel の XcodeGen を利用して Xcode プロジェクトを生成する [ツール](https://github.com/MobileNativeFoundation/rules_xcodeproj) を作成しました。これにより、Bazel ファイルから XcodeGen YAML、そして最終的に Xcode プロジェクトへという複雑な変換チェーンが生じます。このような多層的な間接化はトラブルシューティングを複雑にし、問題の診断と解決をより困難にします。
