---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# ハッシング {#hashing}

<LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink>や選択的テスト実行のような機能には、ターゲットが変更されたかどうかを判断する方法が必要です。Tuistは依存関係グラフの各ターゲットについてハッシュを計算し、ターゲットが変更されたかどうかを判定する。ハッシュは以下の属性に基づいて計算される：

- ターゲットの属性（名前、プラットフォーム、製品など）
- ターゲットのファイル
- ターゲットの依存関係のハッシュ

### キャッシュ属性 {#cache-attributes}

さらに、<LocalizedLink href="/guides/features/cache">caching</LocalizedLink>のハッシュを計算するとき、以下の属性もハッシュする。

#### スウィフトバージョン {#swift-version}

`/usr/bin/xcrun swift --version`
というコマンドを実行して得られたSwiftバージョンをハッシュ化し、ターゲットとバイナリ間のSwiftバージョンの不一致によるコンパイルエラーを防ぐ。

情報 モジュールの安定性
<!-- -->
以前のバージョンのバイナリー・キャッシングでは、`BUILD_LIBRARY_FOR_DISTRIBUTION` ビルド設定を使用して
[モジュールの安定性](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)
を有効にし、任意のコンパイラー・バージョンでバイナリーを使用できるようにしていました。しかし、モジュールの安定性をサポートしないターゲットを使用するプロジェクトでは、コンパイルの問題が発生しました。生成されたバイナリはそれらをコンパイルするために使用された
Swift のバージョンにバインドされ、Swift のバージョンはプロジェクトをコンパイルするために使用されたものと一致しなければなりません。
<!-- -->
:::

#### コンフィギュレーション {#configuration}

`-configuration`
というフラグの背後にあるアイデアは、デバッグ・バイナリがリリース・ビルドで使用されないようにすることであり、その逆も同様である。しかし、他のコンフィギュレーションが使用されないようにプロジェクトから削除するメカニズムがまだ不足しています。

## デバッグ {#debugging}

環境や呼び出しにまたがってキャッシュを使用したときに非決定的な動作に気づいた場合、それは環境間の違いやハッシュロジックのバグに関連している可能性があります。この問題をデバッグするために以下のステップを踏むことをお勧めします：

1. `tuist hash cache` または`tuist hash selective-testing`
   （<LocalizedLink href="/guides/features/cache">バイナリ・キャッシュ</LocalizedLink>または<LocalizedLink href="/guides/features/selective-testing">選択テスト</LocalizedLink>用のハッシュ）を実行し、ハッシュをコピーしてプロジェクト・ディレクトリの名前を変更し、もう一度コマンドを実行してください。ハッシュは一致するはずです。
2. ハッシュが一致しない場合は、生成されたプロジェクトが環境に依存している可能性があります。両方のケースで`tuist graph --format
   json`
   を実行し、グラフを比較してください。あるいは、プロジェクトを生成して、[Diffchecker](https://www.diffchecker.com)のような差分ツールで`project.pbxproj`
   ファイルを比較してください。
3. ハッシュが同じであっても、環境（例えば、CIとローカル）で異なる場合は、同じ[configuration](#configuration)と[Swift
   version](#swift-version)がどこでも使用されていることを確認してください。Swift のバージョンは、Xcode
   のバージョンと結びついているので、Xcode のバージョンが一致することを確認してください。

それでもハッシュが非決定的な場合は、デバッグのお手伝いをしますので、お知らせください。


より良いデバッグ体験を計画中
<!-- -->
デバッグ体験の向上は我々のロードマップにある。print-hashesコマンドは、違いを理解するためのコンテキストを欠いているため、ハッシュ間の違いをツリーのような構造で表示する、よりユーザーフレンドリーなコマンドに置き換える予定である。
<!-- -->
:::
