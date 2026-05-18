---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# キャッシュ {#cache}

Xcode
のビルドシステムは、[インクリメンタルビルド](https://en.wikipedia.org/wiki/Incremental_build_model)
を提供し、1 台のマシンでの効率を高めます。しかし、ビルドアーチファクトは、異なる環境間で共有されないため、同じコードを何度もリビルドする必要があります -
継続的インテグレーション（CI）環境](https://en.wikipedia.org/wiki/Continuous_integration)
またはローカル開発環境（Mac）のいずれかで。

Tuistはキャッシュ機能によってこれらの課題に対処し、ローカル開発環境とCI環境の両方でビルド時間を大幅に短縮する。このアプローチは、フィードバックループを加速するだけでなく、コンテキスト切り替えの必要性を最小化し、最終的に生産性を高める。

キャッシュには2種類あります：
- <LocalizedLink href="/guides/features/cache/module-cache">モジュールキャッシュ</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcodeキャッシュ</LocalizedLink>

## モジュール・キャッシュ {#module-cache}

Tuistの<LocalizedLink href="/guides/features/projects">プロジェクト生成</LocalizedLink>機能を使用するプロジェクトには、個々のモジュールをバイナリとしてキャッシュし、チームやCI環境で共有する強力なキャッシュシステムを提供します。

新しい Xcode
キャッシュを使用することもできますが、この機能は現在ローカルビルド用に最適化されており、生成されたプロジェクトのキャッシュと比較すると、キャッシュのヒット率は低くなるでしょう。しかし、どのキャッシュソリューションを使用するかの決定は、あなたの特定のニーズと好みに依存します。最良の結果を得るために両方のキャッシュソリューションを組み合わせることもできます。

<LocalizedLink href="/guides/features/cache/module-cache">モジュール・キャッシュについて詳しくはこちら</LocalizedLink>

## Xcodeキャッシュ {#xcode-cache}

XCODEにおけるキャッシュの状態。
<!-- -->
Xcodeのキャッシュは現在、ローカルのインクリメンタルビルドに最適化されており、ビルドタスクの全領域はまだパスに依存していません。それでも、Tuistのリモートキャッシュをプラグインすることで恩恵を受けることができ、ビルドシステムの能力が向上し続けるにつれて、ビルド時間が改善されることを期待しています。
<!-- -->
:::

Appleは、BazelやBuckのような他のビルドシステムと同様に、ビルドレベルでの新しいキャッシュソリューションに取り組んできた。この新しいキャッシュ機能はXcode
26から利用できるようになり、TuistはTuistの<LocalizedLink href="/guides/features/projects">プロジェクト生成</LocalizedLink>機能を使用しているかどうかに関係なく、シームレスに統合されるようになった。

<LocalizedLink href="/guides/features/cache/xcode-cache">Xcodeキャッシュについて詳しくはこちら</LocalizedLink>
