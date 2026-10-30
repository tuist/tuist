---
{
  "title": "プロジェクト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "SwiftでXcodeプロジェクトを定義し、Tuistで一貫して生成します。マージ競合を解消し、依存関係をグラフとしてモデル化し、モジュールキャッシュを活用しましょう。"
}
---
# 生成されたプロジェクト {#generated-projects}

Tuist Generated Projectsは、複雑さとコストを許容範囲内に抑えながらこれらの課題を克服するための現実的な代替手段です。Xcodeプロジェクトを基本要素と位置づけ、将来のXcodeアップデートに対する耐性を確保し、Xcodeプロジェクトの生成を活用して、モジュール化に焦点を当てた宣言型APIをチームに提供します。Tuistはプロジェクト定義を用いてモジュール化の複雑さを簡素化し、さまざまな環境でのビルドやテストといったワークフローを最適化し、Xcodeプロジェクトの進化を促進して民主化します。

## 仕組み {#how-does-it-work}

生成されたプロジェクトを始めるには、**Tuistのドメイン固有言語（DSL）** を使用してプロジェクトを定義するだけで済みます。これには、`Workspace.swift`や`Project.swift`などのマニフェストファイルを使用します。Swift Package Managerを使った経験があれば、そのアプローチは非常に似ています。

プロジェクトを定義すると、Tuistはそれを管理・操作するためのさまざまなワークフローを提供します。

- **Generate:** これは基本的なワークフローです。Xcodeと互換性のあるXcodeプロジェクトを作成するために使用します。
- **<.localized_link href="/cli/build">Build</.localized_link>:** このワークフローはXcodeプロジェクトを生成するだけでなく、`xcodebuild`を使用してコンパイルも行います。
- **<.localized_link href="/cli/test">Test</.localized_link>:** ビルドワークフローと同様に動作し、Xcodeプロジェクトを生成するだけでなく、`xcodebuild`を使用してテストを実行します。

## Xcodeプロジェクトの課題 {#challenges-with-xcode-projects}

Xcodeプロジェクトが大きくなるにつれて、**組織の生産性が低下する**可能性があります。その要因には、信頼性の低い増分ビルド、問題に遭遇した開発者によるXcodeのグローバルキャッシュの頻繁なクリア、脆弱なプロジェクト設定などが含まれます。迅速な機能開発を維持するため、組織は通常、さまざまな戦略を検討します。

一部の組織は、[React Native](https://reactnative.dev/)のようなJavaScriptベースの動的ランタイムを使用してプラットフォームを抽象化することで、コンパイラを回避することを選択します。このアプローチは効果的かもしれませんが、[プラットフォームのネイティブ機能へのアクセスが複雑化](https://shopify.engineering/building-app-clip-react-native)します。他の組織は**コードベースのモジュール化**を選択し、明確な境界を設けることでコードベースの扱いやすさを高め、ビルド時間の信頼性を向上させます。しかし、Xcodeプロジェクト形式はモジュール化を想定して設計されておらず、理解できる人が少ない暗黙的な設定や頻繁な競合を引き起こします。これにより属人化が進み、増分ビルドが改善されたとしても、ビルドが失敗した際に開発者がXcodeのビルドキャッシュ（派生データ）を頻繁にクリアすることがあります。この問題に対処するため、一部の組織は**Xcodeのビルドシステムを放棄**し、[Buck](https://buck.build/)や[Bazel](https://bazel.build/)などの代替手段を採用します。ただし、これには[高い複雑さとメンテナンス負担](https://bazel.build/migrate/xcode)が伴います。


## 代替手段 {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager（SPM）は主に依存関係に焦点を当てていますが、Tuistは異なるアプローチを提供します。Tuistでは、SPM統合のためのパッケージを定義するだけでなく、プロジェクト、ワークスペース、ターゲット、スキームといった馴染みのある概念を使ってプロジェクトを構成します。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)は、共同作業を行うXcodeプロジェクトでの競合を減らし、Xcodeの内部動作の複雑さを一部簡素化するために設計された専用プロジェクトジェネレーターです。ただし、プロジェクトは[YAML](https://yaml.org/)のようなシリアライズ可能な形式で定義されます。Swiftとは異なり、追加のツールを組み込まないと、抽象化やチェックを構築できません。XcodeGenは検証と最適化のために依存関係を内部表現にマップする方法を提供していますが、それでも開発者はXcodeの細かな仕様にさらされます。このため、Bazelコミュニティで見られるように、XcodeGenは[ツール構築](https://github.com/MobileNativeFoundation/rules_xcodeproj)の適切な基盤となる可能性がありますが、健全で生産的な環境を維持することを目的とした包括的なプロジェクト進化にとっては最適ではありません。

### Bazel {#bazel}

[Bazel](https://bazel.build)はリモートキャッシング機能で知られる高度なビルドシステムであり、主にこの能力によってSwiftコミュニティで人気を集めています。しかし、Xcodeとそのビルドシステムの拡張性は限られているため、これをBazelのシステムで置き換えるには多大な努力とメンテナンスが必要です。BazelとXcodeの統合に多額の投資を行っている限られた企業のリストからも明らかなように、豊富なリソースを持つ少数の企業のみがこのオーバーヘッドを負担できます。興味深いことに、コミュニティはBazelのXcodeGenを使用してXcodeプロジェクトを生成する[ツール](https://github.com/MobileNativeFoundation/rules_xcodeproj)を作成しました。これにより、BazelファイルからXcodeGen YAML、そして最終的にXcodeプロジェクトへという複雑な変換連鎖が生じます。このような多層的な間接参照はトラブルシューティングを複雑にし、問題の診断と解決をより困難にします。
