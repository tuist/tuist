---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, and Bazel cache."
}
---
# キャッシュ {#cache}

ビルド成果物は環境間で共有されないため、同じコードを何度も再ビルドする必要が生じます。Tuist のキャッシング機能は成果物をリモートで共有するため、チームと CI はすでにビルド済みのものを再ビルドすることなく、より高速なビルドを実現できます。

プロジェクトやデプロイメントモデルに合わせたキャッシュワークフローをご覧ください。

\<.home\_cards\>
\<.home\_card
title="モジュールキャッシュ"
details="Tuist で生成されたプロジェクトを使用する場合、個々のモジュールをバイナリとしてキャッシュします。Tuist によるプロジェクト生成が必要です。"
link="/guides/features/cache/module-cache"
/\>
\<.home\_card
title="Xcode キャッシュ"
details="Xcode のコンパイル成果物を環境間で共有します。任意の Xcode プロジェクトで動作し、プロジェクト生成は不要です。"
link="/guides/features/cache/xcode-cache"
/\>
\<.home\_card
title="Gradle キャッシュ"
details="Gradle のビルドキャッシュ成果物をリモートで共有します。パフォーマンス可視化のためのビルドインサイトが含まれます。"
link="/guides/features/cache/gradle-cache"
/\>
\<.home\_card
title="Bazel キャッシュ"
details="Bazel を Tuist の Remote Execution API キャッシュに向けることで、アクションの出力をチームと CI で共有します。"
link="/guides/features/cache/bazel-cache"
/\>
\<.home\_card
title="セルフホスティング"
details="CI、オフィス、またはリージョン内のコンピューティングリソースの近くにキャッシュノードを実行し、それらをホスト型またはセルフホスト型の Tuist に接続します。"
link="/guides/features/cache/self-hosting"
/\>
\</.home\_cards\>

> \[\!TIP\]
> **Tuist Runners で最速**
> 
> \<.localized\_link href="/guides/features/runners"\>Tuist Runners\</.localized\_link\> では、キャッシュはランナーのプライベートネットワーク上に配置され、開発者マシンと同じキャッシュが共有されるため、CI ジョブは別途ウォームアップ用の CI キャッシュを用意することなく、すぐにウォームヒットを利用できます。

## アップロードを CI に制限する {#restrict-uploads-to-ci}

アカウント管理者は、開発者を読み取り専用にしながら、CI がキャッシュ成果物をアップロードできるようにすることができます。Tuist でアカウントの **キャッシュ** 設定を開き、**キャッシュアップロードアクセス** を **CI およびアカウントトークンのみ** に設定してください。その後、ログインセッションで認証されたメンバーは引き続きキャッシュからダウンロードできますが、アップロードには CI OIDC 認証、または `project:cache:write` や `ci` などのキャッシュ書き込みスコープを持つアカウントトークンが必要です。

CI が信頼できるキャッシュプロデューサーであり、ローカルマシンはキャッシュを消費のみ行う場合にこの設定を使用してください。この設定はキャッシュアップロードの認可にのみ影響します。