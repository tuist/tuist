---
{
  "title": "プロジェクト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "SwiftでXcodeプロジェクトを定義し、Tuistで一貫して生成します。マージコンフリクトを解消し、依存関係をグラフとしてモデル化し、モジュールキャッシュを活用しましょう。"
}
---
# 生成されたプロジェクト {#generated-projects}

Tuist Generated Projects は、複雑さとコストを許容範囲に抑えながらこれらの課題を克服するための現実的な代替手段です。Xcode プロジェクトを基本要素として扱い、将来の Xcode アップデートに対する耐性を確保するとともに、Xcode プロジェクトの生成を活用して、モジュラー化に重点を置いた宣言型 API をチームに提供します。Tuist はプロジェクト定義を用いてモジュラー化の複雑さを簡素化し、さまざまな環境でのビルドやテストなどのワークフローを最適化し、Xcode プロジェクトの進化を促進し民主化します。

## 仕組み {#how-does-it-work}

生成されたプロジェクトを始めるには、**Tuist のドメイン固有言語 (DSL)** を使ってプロジェクトを定義するだけで十分です。これには、`Workspace.swift` や `Project.swift` といったマニフェストファイルを使用します。Swift Package Manager を使った経験があれば、そのアプローチは非常に似ています。

プロジェクトを定義したら、Tuist はそれを管理・操作するためのさまざまなワークフローを提供します:

- **Generate:** これは基本的なワークフローです。Xcode と互換性のある Xcode プロジェクトを作成するために使用します。
- **<.localized_link href="/cli/build">Build</.localized_link>:** このワークフローは Xcode プロジェクトを生成するだけでなく、`xcodebuild` を使用してコンパイルも行います。
- **<.localized_link href="/cli/test">Test</.localized_link>:** ビルドワークフローと同様に動作し、Xcode プロジェクトを生成するだけでなく、`xcodebuild` を使用してテストを実行します。

## Xcode プロジェクトの課題 {#challenges-with-xcode-projects}

Xcode プロジェクトが大きくなるにつれて、**組織の生産性が低下する**可能性があります。その要因としては、信頼性の低い増分ビルド、問題に遭遇した開発者による Xcode のグローバルキャッシュの頻繁なクリア、脆弱なプロジェクト構成などが挙げられます。迅速な機能開発を維持するため、組織は通常、さまざまな戦略を検討します。

一部の組織は、[React Native](https://reactnative.dev/) のような JavaScript ベースの動的ランタイムを使用してプラットフォームを抽象化することで、コンパイラを回避することを選びます。このアプローチは効果的かもしれませんが、[プラットフォームのネイティブ機能へのアクセスが複雑化](https://shopify.engineering/building-app-clip-react-native)します。他の組織は、**コードベースのモジュラー化**を選択します。これにより明確な境界を設定でき、コードベースの作業が容易になり、ビルド時間の信頼性が向上します。しかし、Xcode プロジェクト形式はモジュラー化を想定しておらず、理解できる人が少なく頻繁な競合を引き起こす暗黙的な構成につながります。これはバス係数を悪化させ、増分ビルドが改善される場合でも、ビルドが失敗した際に開発者が Xcode のビルドキャッシュ (派生データ) を頻繁にクリアすることがあります。この問題に対処するため、一部の組織は **Xcode のビルドシステムを放棄** し、[Buck](https://buck.build/) や [Bazel](https://bazel.build/) などの代替手段を採用することを選びます。ただし、これには [高い複雑さとメンテナンス負担](https://bazel.build/migrate/xcode) が伴います。


## 代替手段 {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager (SPM) が主に依存関係に焦点を当てているのに対し、Tuist は異なるアプローチを提供します。Tuist では、SPM 統合のためのパッケージを定義するだけでなく、プロジェクト、ワークスペース、ターゲット、スキームといった馴染みのある概念を使ってプロジェクトを構築します。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) は、共同作業を行う Xcode プロジェクトでの競合を減らし、Xcode の内部動作の複雑さの一部を簡素化するために設計された専用プロジェクトジェネレーターです。ただし、プロジェクトは [YAML](https://yaml.org/) のようなシリアライズ可能な形式で定義されます。Swift とは異なり、追加のツールを組み込まないと抽象化やチェックを構築できません。XcodeGen は検証と最適化のために依存関係を内部表現にマッピングする方法を提供していますが、それでも開発者は Xcode の細かな仕様にさらされます。このため、Bazel コミュニティで見られるように、XcodeGen は [ツール構築](https://github.com/MobileNativeFoundation/rules_xcodeproj) の適切な基盤となる可能性がありますが、健全で生産的な環境を維持することを目的とした包括的なプロジェクト進化には最適ではありません。

### Bazel {#bazel}

[Bazel](https://bazel.build) はリモートキャッシング機能で知られる高度なビルドシステムであり、主にこの能力によって Swift コミュニティ内で人気を集めています。ただし、Xcode とそのビルドシステムの拡張性は限られているため、これを Bazel のシステムに置き換えるには多大な努力とメンテナンスが必要です。Bazel と Xcode の統合に多額の投資を行っている限られた企業のリストからも明らかなように、このオーバーヘッドを負担できるのは豊富なリソースを持つ少数の企業だけです。興味深いことに、コミュニティは Bazel の XcodeGen を使用して Xcode プロジェクトを生成する [ツール](https://github.com/MobileNativeFoundation/rules_xcodeproj) を作成しました。これにより、Bazel ファイルから XcodeGen YAML、そして最終的に Xcode プロジェクトへと変換される複雑な連鎖が生じます。このような多層的な間接参照はトラブルシューティングを複雑にし、問題の診断と解決をより困難にします。
