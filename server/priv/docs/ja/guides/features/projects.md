---
{
  "title": "プロジェクト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "XcodeプロジェクトをSwiftで記述し、Tuistで一貫して生成します。マージ競合を解消し、依存関係をグラフとしてモデル化し、モジュールキャッシュを活用しましょう。"
}
---
# 生成されたプロジェクト {#generated-projects}

Tuist Generated Projectsは、複雑さとコストを許容可能なレベルに抑えながら、これらの課題を克服するための現実的な代替手段です。Xcodeプロジェクトを基本要素と位置づけ、将来のXcodeアップデートに対する耐性を確保し、Xcodeプロジェクトの生成を活用して、モジュール化に重点を置いた宣言型APIをチームに提供します。Tuistはプロジェクト定義を用いてモジュール化の複雑さを簡素化し、さまざまな環境でのビルドやテストなどのワークフローを最適化し、Xcodeプロジェクトの進化を促進し民主化します。

## 仕組み {#how-does-it-work}

生成されたプロジェクトを使い始めるには、**Tuistのドメイン固有言語（DSL）** を使用してプロジェクトを定義するだけで十分です。これには、`Workspace.swift`や`Project.swift`といったマニフェストファイルを使用することが含まれます。以前にSwift Package Managerを使ったことがあれば、そのアプローチは非常に似ています。

プロジェクトを定義すると、Tuistはそれを管理・操作するためのさまざまなワークフローを提供します。

- **Generate:** これは基本的なワークフローです。Xcodeと互換性のあるXcodeプロジェクトを作成するために使用します。
- **<.localized_link href="/cli/build">Build</.localized_link>:** このワークフローはXcodeプロジェクトを生成するだけでなく、`xcodebuild`を使用してコンパイルも行います。
- **<.localized_link href="/cli/test">Test</.localized_link>:** ビルドワークフローと同様に動作し、Xcodeプロジェクトを生成するだけでなく、`xcodebuild`を使用してテストを実行します。

## Xcodeプロジェクトの課題 {#challenges-with-xcode-projects}

Xcodeプロジェクトが大きくなるにつれて、**組織の生産性が低下する可能性があります**。その要因としては、信頼性の低い増分ビルド、問題に遭遇した開発者によるXcodeのグローバルキャッシュの頻繁なクリア、脆弱なプロジェクト構成などが挙げられます。迅速な機能開発を維持するため、組織は通常、さまざまな戦略を検討します。

一部の組織では、[React Native](https://reactnative.dev/)のようなJavaScriptベースの動的ランタイムを使用してプラットフォームを抽象化することで、コンパイラを回避することを選択しています。このアプローチは効果的かもしれませんが、[プラットフォームのネイティブ機能へのアクセスが複雑化](https://shopify.engineering/building-app-clip-react-native)します。他の組織では、**コードベースのモジュール化**を選択し、明確な境界を設定することで、コードベースの作業を容易にし、ビルド時間の信頼性を向上させます。しかし、Xcodeプロジェクト形式はモジュール化を想定しておらず、理解している人が少ない暗黙的な構成や頻繁な競合を引き起こします。これによりバス係数が悪化し、増分ビルドが改善される場合でも、ビルドが失敗した際に開発者がXcodeのビルドキャッシュ（派生データ）を頻繁にクリアすることがあります。この問題に対処するため、一部の組織では**Xcodeのビルドシステムを放棄**し、[Buck](https://buck.build/)や[Bazel](https://bazel.build/)などの代替手段を採用することを選択しています。ただし、これには[高い複雑さとメンテナンス負担](https://bazel.build/migrate/xcode)が伴います。


## 代替手段 {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager（SPM）は主に依存関係に焦点を当てていますが、Tuistは異なるアプローチを提供します。Tuistでは、SPM統合のためにパッケージを定義するだけでなく、プロジェクト、ワークスペース、ターゲット、スキームといった馴染みのある概念を使用してプロジェクトを構築します。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)は、協業におけるXcodeプロジェクトの競合を減らし、Xcode内部動作の複雑さの一部を簡素化するために設計された専用プロジェクトジェネレーターです。ただし、プロジェクトは[YAML](https://yaml.org/)のようなシリアライズ可能な形式で定義されます。Swiftとは異なり、追加のツールを組み込まなければ抽象化やチェックを構築できません。XcodeGenは検証と最適化のために依存関係を内部表現にマップする方法を提供していますが、それでも開発者はXcodeの細かな仕様にさらされます。このため、Bazelコミュニティで見られるように、XcodeGenは[ツール構築](https://github.com/MobileNativeFoundation/rules_xcodeproj)のための適切な基盤となる可能性がありますが、健全で生産的な環境を維持することを目的とした包括的なプロジェクト進化には最適ではありません。現在XcodeGenを使用している場合、[XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen)では、既存のXcodeGenプロジェクトでどのTuist機能が利用できるかを説明しています。Tuist生成プロジェクトに移行するには、<.localized_link href="/guides/features/projects/adoption/migrate/xcodegen-project">移行ガイド</.localized_link>を参照してください。

### Bazel {#bazel}

[Bazel](https://bazel.build)はリモートキャッシング機能で知られる高度なビルドシステムであり、主にこの能力によってSwiftコミュニティで人気を集めています。しかし、Xcodeとそのビルドシステムの拡張性は限られているため、Bazelのシステムで置き換えるには多大な努力とメンテナンスが必要です。BazelとXcodeの統合に多額の投資を行っている企業の一覧からも明らかなように、このオーバーヘッドを負担できるのは豊富なリソースを持つ少数の企業のみです。興味深いことに、コミュニティはBazelのXcodeGenを使用してXcodeプロジェクトを生成する[ツール](https://github.com/MobileNativeFoundation/rules_xcodeproj)を作成しました。これにより、BazelファイルからXcodeGen YAML、そして最終的にXcodeプロジェクトへという複雑な変換チェーンが生じます。このような階層的な間接参照はトラブルシューティングを複雑にし、問題の診断と解決をより困難にします。
