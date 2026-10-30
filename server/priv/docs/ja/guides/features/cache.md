---
{
  "title": "キャッシュ",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "モジュールキャッシュ、Xcodeキャッシュ、Gradleキャッシュ、Bazelキャッシュ、Elixir依存関係キャッシュ、および実験的なRustコンパイルキャッシングを含むTuist Cacheでビルド時間を最適化します。"
}
---
# キャッシュ {#cache}

ビルド成果物は環境間で共有されないため、同じコードを何度も再ビルドする必要があります。Tuist のキャッシング機能は成果物をリモートで共有するため、チームと CI はすでにビルド済みのものを再ビルドすることなく、より高速なビルドを実現できます。

プロジェクトやデプロイメントモデルに合ったキャッシュのワークフローを学びましょう:

<.home_cards>
  <.home_card
    title="モジュールキャッシュ"
    details="Tuist で生成したプロジェクトを使用する場合、個々のモジュールをバイナリとしてキャッシュします。Tuist によるプロジェクト生成が必要です。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode キャッシュ"
    details="Xcode のコンパイル成果物を環境間で共有します。任意の Xcode プロジェクトで動作し、プロジェクト生成は不要です。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle キャッシュ"
    details="Gradle のビルドキャッシュ成果物をリモートで共有します。パフォーマンスを可視化するためのビルドインサイトが含まれています。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel キャッシュ"
    details="Bazel を Tuist の Remote Execution API キャッシュに向けることで、アクションの出力をチームと CI 間で共有できます。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir キャッシュ"
    details="サポートされている Elixir 依存関係のキャッシングを有効にし、Mix を引き続き使用できます。ダッシュボードでキャッシュヒットと転送を確認できます。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust キャッシュ（実験的）"
    details="サポートされているレジストリのリーフライブラリの出力をローカルおよび Kura 経由で再利用します。キャッシングの有効化方法とキャッシュアクティビティの確認方法を学びます。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="セルフホスティング"
    details="CI、オフィス、またはリージョンのコンピューティングに近い場所にキャッシュノードを実行し、それらをホスト型またはセルフホスト型の Tuist に接続します。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Tuist Runners で最速**
>
> <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>では、キャッシュはランナーのプライベートネットワーク上に配置され、開発者マシンが使用するものと同じキャッシュを共有するため、CI ジョブは追加の設定なしですぐにウォームヒットを利用でき、別途 CI キャッシュをウォームアップする必要がありません。


## CI へのアップロードを制限 {#restrict-uploads-to-ci}

アカウント管理者は、開発者を読み取り専用にしながら、CI がキャッシュ成果物をアップロードできるようにすることができます。Tuist でアカウントの **キャッシュ** 設定を開き、**キャッシュアップロードアクセス** を **CI とアカウントトークンのみ** に設定します。その後、ログインセッションで認証されたメンバーは引き続きキャッシュからダウンロードできますが、アップロードには CI OIDC 認証または `project:cache:write` や `ci` などのキャッシュ書き込みスコープを持つアカウントトークンが必要です。

CI が信頼できるキャッシュプロデューサーであり、ローカルマシンはキャッシュの消費のみを行う場合に使用します。この設定はキャッシュアップロードの認可にのみ影響します。
