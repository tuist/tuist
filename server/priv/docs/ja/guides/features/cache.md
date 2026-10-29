---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, Bazel cache, Elixir dependency cache, and experimental Rust compilation caching."
}
---
# キャッシュ {#cache}

ビルド成果物は環境間で共有されないため、同じコードを何度も再ビルドする必要があります。Tuistのキャッシング機能は成果物をリモートで共有するため、チームとCIはすでにビルド済みのものを再ビルドすることなく、より高速なビルドを実現できます。

プロジェクトやデプロイメントモデルに合ったキャッシュワークフローを学びましょう:

<.home_cards>
  <.home_card
    title="モジュールキャッシュ"
    details="Tuistの生成プロジェクトを使用するプロジェクト向けに、個々のモジュールをバイナリとしてキャッシュします。Tuistプロジェクトの生成が必要です。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcodeキャッシュ"
    details="Xcodeコンパイル成果物を環境間で共有します。任意のXcodeプロジェクトで動作し、プロジェクト生成は不要です。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradleキャッシュ"
    details="Gradleビルドキャッシュ成果物をリモートで共有します。パフォーマンス可視化のためのビルドインサイトが含まれます。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazelキャッシュ"
    details="BazelをTuistのリモート実行APIキャッシュに向けて、アクション出力をチームとCI間で共有します。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixirキャッシュ"
    details="サポートされているElixir依存関係のキャッシングを有効にし、Mixを引き続き使用します。ダッシュボードでキャッシュヒットと転送を確認できます。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rustキャッシュ（実験的）"
    details="サポートされているレジストリのリーフライブラリ出力をローカルおよびKura経由で再利用します。キャッシングの有効化方法とキャッシュアクティビティの確認方法を学びます。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="セルフホスティング"
    details="CI、オフィス、またはリージョンコンピューティングに近い場所にキャッシュノードを実行し、それらをホスト型またはセルフホスト型のTuistに接続します。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Tuist Runnersで最速**
>
> <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>では、キャッシュはランナーのプライベートネットワーク上に同居配置され、開発者マシンが使用するものと同じキャッシュと共有されるため、CIジョブは別途ウォームアップ用のCIキャッシュを用意することなく、すぐにウォームヒットを得られます。


## CIへのアップロードを制限 {#restrict-uploads-to-ci}

アカウント管理者は、CIがキャッシュ成果物をアップロードできるようにしながら、開発者を読み取り専用にすることができます。Tuistでアカウントの**キャッシュ**設定を開き、**キャッシュアップロードアクセス**を**CIとアカウントトークンのみ**に設定します。その後、ログインセッションで認証されたメンバーは引き続きキャッシュからダウンロードできますが、アップロードにはCI OIDC認証または`project:cache:write`や`ci`などのキャッシュ書き込みスコープを持つアカウントトークンが必要です。

CIが信頼できるキャッシュプロデューサーであり、ローカルマシンはキャッシュを消費のみ行う場合にこれを使用します。この設定はキャッシュアップロードの承認にのみ影響します。
