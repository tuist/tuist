---
{
  "title": "Tuistとは？",
  "description": "開発者のための仮想プラットフォームチーム。Xcode、Gradle、Bazel、Elixir、Rust向けのインフラストラクチャを構築し、各ツールチェーンに最適化された機能を提供します。"
}
---

# ソフトウェアをリリースする開発者のための仮想プラットフォームチーム

**Tuist は、チームのアプリ開発のスケーリングと迅速なリリースをサポート**し、大規模なコードベースの複雑さを、チームの成長に合わせて生産性を高める体験に変えます。すでに使用しているビルドシステム（Xcode、Gradle、Bazel、Elixir、Rust プロジェクト）で動作します。利用可能な機能はツールチェーンによって異なります。Rust プロジェクトでは、doctest、flaky test の検出、実験的なコンパイルキャッシュを含む、Cargo のビルドおよびテストのインサイトを利用できます。

まず <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェースのインストール</.localized_link> から始め、その後、お使いのビルドシステムに応じた <.localized_link href="/guides/get-started">スタートガイド</.localized_link> に従ってください。

<br/>

<.home_cards>
  <.home_card
    title="キャッシュ"
    details="チームと CI 間でコンパイル出力を共有します。Xcode のコンパイルキャッシュ、Tuist のモジュールキャッシュ、Gradle のビルドキャッシュ、Bazel のリモートキャッシュ、Rust の実験的なコンパイルキャッシュに対応しています。"
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="ビルド＆テストのインサイト"
    details="Xcode、Gradle、Bazel、Elixir、Rust プロジェクト全体で、ビルドとテストの所要時間、失敗、flakiness、回帰を追跡します。"
    supported_for="apple,gradle,bazel,elixir,rust"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選択的テスト"
    details="変更の影響を受けるテストのみを実行し、Xcode および生成されたプロジェクトで数秒以内にフィードバックを得られます。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="ランナー"
    details="管理された macOS および Linux ランナー上で CI を実行し、開発者マシンが使用するものと同じキャッシュに近づけます。"
    link="/guides/features/runners"
/>
  <.home_card
    title="プレビュー"
    details="URL でアプリを即座に共有。ストアのレビュー待ちや複雑な設定は不要です。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="Swift で Xcode プロジェクトを定義し、一貫して生成します。マージ競合を解消し、モジュールキャッシュを活用できます。"
    link="/guides/features/projects"
/>
  <.home_card
    title="パッケージレジストリ"
    details="Tuist のキャッシュネットワーク backed なレジストリにより、Swift パッケージの解決を分単位から秒単位に短縮します。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="バンドルサイズ"
    details="アプリを軽量に保つよう分析し、ユーザーのダウンロード速度を向上させ、ストアのガイドラインを満たします。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 大規模なリリースを行うチームからの信頼

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/)、その他 100 社以上の企業のチーム**が、iOS および Android のコードベース全体で Tuist を活用し、より迅速なリリースを実現しています。
