---
{
  "title": "Tuistとは？",
  "description": "開発者のための仮想プラットフォームチーム。Xcode、Gradle、Bazel、Elixir、Rust向けのビルドインフラストラクチャを、各ツールチェーンに最適化された機能で提供します。"
}
---

# リリースを加速する開発者のための仮想プラットフォームチーム

**Tuist はアプリ開発のスケールアップと迅速なリリースを支援**し、大規模なコードベースの複雑さを、チームの成長に合わせて生産性を高める体験へと変えます。Xcode、Gradle、Bazel、Elixir、Rust のプロジェクトで、すでに使用しているビルドシステムと連携します。利用可能な機能はツールチェーンによって異なります。Rust プロジェクトでは、doctest、flaky テストの検出、実験的なコンパイルキャッシュを含む Cargo のビルドおよびテストインサイトを利用できます。

まず <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェースのインストール</.localized_link> から始め、その後、お使いのビルドシステムに応じた <.localized_link href="/guides/get-started">はじめの一歩</.localized_link> に進んでください。

<br/>

<.home_cards>
  <.home_card
    title="キャッシュ"
    details="チームと CI でコンパイル成果物を共有します。Xcode のコンパイルキャッシュ、Tuist のモジュールキャッシュ、Gradle のビルドキャッシュ、Bazel のリモートキャッシュ、Rust の実験的なコンパイルキャッシュに対応しています。"
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="ビルド＆テストインサイト"
    details="Xcode、Gradle、Bazel、Elixir、Rust のプロジェクト全体で、ビルドとテストの所要時間、失敗、flakiness、回帰を追跡します。"
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
    details="管理された macOS および Linux ランナーで CI を実行し、開発マシンと同じキャッシュを近くで利用できます。"
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
    details="Tuist のキャッシュネットワーク-backed なレジストリにより、Swift パッケージの解決を分単位から秒単位に短縮します。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="バンドルサイズ"
    details="アプリを軽量に保つことで、ユーザーはより高速にダウンロードでき、ストアのガイドラインにも適合しやすくなります。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 大規模なリリースを支えるチームからの信頼

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/)、その他 100 社以上の企業**が、iOS および Android のコードベースで Tuist を活用し、より迅速なリリースを実現しています。
