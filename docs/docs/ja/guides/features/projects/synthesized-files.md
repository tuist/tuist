---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# 合成ファイル{#synthesized-files}

Tuistは生成時にファイルやコードを生成し、Xcodeプロジェクトの管理や作業を便利にします。このページではこの機能と、プロジェクトでの活用方法について説明します。

## ターゲットリソース{#target-resources}

Xcodeプロジェクトはターゲットへのリソース追加をサポートしています。ただし、ソースとリソースが頻繁に移動されるモジュール型プロジェクトでは、チームにいくつかの課題をもたらします：

- ****リソースの最終的な配置場所とアクセス方法は、ターゲット製品によって異なります。例えば、ターゲットがアプリケーションを表す場合、リソースはアプリケーションバンドルにコピーされます。これにより、コードがリソースにアクセスする際にバンドル構造を前提とする必要が生じます。これはコードの理解を困難にし、リソースの移動を複雑にするため、理想的ではありません。
- **リソースをサポートしないプロダクト**:
  静的ライブラリなど、バンドルではないためリソースをサポートしないプロダクトが存在します。そのため、プロジェクトやアプリにオーバーヘッドが生じる可能性のあるフレームワークなど、別のプロダクトタイプに切り替える必要があります。
  例えば、静的フレームワークは最終製品に静的にリンクされ、リソースのみを最終製品にコピーするためのビルドフェーズが必要となります。あるいは動的フレームワークの場合、Xcodeはバイナリとリソースの両方を最終製品にコピーしますが、フレームワークを動的にロードする必要があるためアプリの起動時間が長くなります。
- ****
  は実行時エラーが発生しやすい：リソースは名前と拡張子（文字列）で識別される。したがって、いずれかに誤字があると、リソースにアクセスしようとした際に実行時エラーが発生する。コンパイル時に検出されず、リリース版でクラッシュを引き起こす可能性があるため、これは理想的ではない。

Tuistは、実装の詳細を抽象化する統合インターフェースを**で合成し、バンドルとリソースにアクセスする** ことで上記の問題を解決します。

::: warning RECOMMENDED
<!-- -->
Tuistで合成されたインターフェースを介したリソースへのアクセスは必須ではありませんが、コードの理解を容易にし、リソースの移動を簡素化するため推奨します。
<!-- -->
:::

## リソース {#resources}

Tuistは、`、Info.plist、`
などのファイル内容や、Swiftでのentitlementsを宣言するためのインターフェースを提供します。これにより、ターゲットやプロジェクト間で一貫性を確保し、コンパイル時に問題を検出するためにコンパイラを活用できます。また、独自の抽象化を考案して内容をモデル化し、ターゲットやプロジェクト間で共有することも可能です。

プロジェクトが生成されると、Tuistはこれらのファイルの内容を合成し、それらを定義するプロジェクトを含むディレクトリを基準として、`派生`
ディレクトリに書き出します。

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
プロジェクトの`.gitignore ファイルに、`ディレクトリを派生させた` を追加することを推奨します。`
<!-- -->
:::

## アクセサをバンドルする{#bundle-accessors}

Tuistは、対象リソースを含むバンドルにアクセスするためのインターフェースを合成します。

### Swift{#swift}

ターゲットには、バンドルを公開する`Bundle` タイプの拡張が含まれます：

```swift
let bundle = Bundle.module
```

### Objective-C{#objectivec}

Objective-Cでは、バンドルにアクセスするために`{Target}Resources` というインターフェースが提供されます：

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
現在、TuistはObjective-Cソースのみを含む内部ターゲットに対してリソースバンドルアクセサを生成しません。これは[issue
#6456](https://github.com/tuist/tuist/issues/6456)で追跡されている既知の制限事項です。
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
ターゲット製品（例：ライブラリ）がリソースをサポートしていない場合、Tuistはリソースを`バンドルタイプのターゲットに含めます（`
）。これにより、最終製品に確実に組み込まれ、インターフェースが正しいバンドルを指すようになります。これらの合成バンドルには自動的に`tuist:synthesizedタグが付与され（`
）、親ターゲットの全タグを継承します。これにより、<LocalizedLink href="/guides/features/projects/metadata-tags#system-tags">キャッシュプロファイル</LocalizedLink>でそれらをターゲットに設定できます。
<!-- -->
:::

## リソースアクセサ{#resource-accessors}

リソースは名前と拡張子で識別され、文字列として扱われます。これはコンパイル時に検出されないため理想的ではなく、リリース時にクラッシュを引き起こす可能性があります。これを防ぐため、Tuistはプロジェクト生成プロセスに[SwiftGen](https://github.com/SwiftGen/SwiftGen)を統合し、リソースにアクセスするためのインターフェースを合成します。これにより、コンパイラが問題を検出する仕組みを活用して、リソースを安全にアクセスできます。

Tuistはデフォルトで以下のリソースタイプに対するアクセサを合成するため、[テンプレート](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)を含みます：

| リソースタイプ | 自動生成ファイル                 |
| ------- | ------------------------ |
| 画像と色    | `Assets+{Target}.swift`  |
| 文字列     | `Strings+{Target}.swift` |
| Plists  | `{NameOfPlist}.swift`    |
| フォント    | `Fonts+{Target}.swift`   |
| ファイル    | `Files+{Target}.swift`   |

> ` 注記: プロジェクト単位でリソースアクセサの自動生成を無効化するには、プロジェクトオプションに ```
> の `disableSynthesizedResourceAccessors` オプションを指定してください。

#### カスタムテンプレート{#custom-templates}

他のリソースタイプへのアクセサを合成するための独自のテンプレートを提供したい場合（[SwiftGen](https://github.com/SwiftGen/SwiftGen)でサポートされている必要がある）、`Tuist/ResourceSynthesizers/{name}.stencil`
に作成できます。ここでnameはリソース名のキャメルケース表記です。

| リソース             | テンプレート名                    |
| ---------------- | -------------------------- |
| 文字列              | `Strings.stencil`          |
| assets           | `Assets.stencil`           |
| plists           | `Plists.stencil`           |
| フォント             | `Fonts.stencil`            |
| coreData         | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| files            | `Files.stencil`            |

` アクセサを合成するリソースタイプのリストを設定したい場合は、`の `Project.resourceSynthesizers`
プロパティを使用し、使用するリソースシンセサイザーのリストを渡すことができます:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
カスタムテンプレートを使用してリソースへのアクセサを合成する方法の例は、[この例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)
を参照してください。
<!-- -->
:::
