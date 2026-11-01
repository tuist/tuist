---
{
  "title": "合成ファイル",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuistプロジェクトにおける合成ファイルについて学びます。"
}
---
# 生成されるファイル {#synthesized-files}

Tuist は生成時にファイルやコードを自動生成し、Xcode プロジェクトの管理と作業をより便利にします。このページでは、この機能の概要と、プロジェクトでの活用方法について説明します。

## ターゲットリソース {#target-resources}

Xcode プロジェクトでは、ターゲットにリソースを追加できます。ただし、特にモジュラープロジェクトでソースやリソースが頻繁に移動される場合、チームはいくつかの課題に直面します。

- **ランタイムアクセスの一貫性の欠如**: リソースが最終的な製品内のどこに配置され、どのようにアクセスされるかは、ターゲットの製品タイプに依存します。例えば、ターゲットがアプリケーションを表す場合、リソースはアプリケーションバンドルにコピーされます。これにより、リソースにアクセスするコードがバンドル構造を前提とするようになり、コードの理解が難しくなり、リソースの移動も煩雑になるため、理想的ではありません。
- **リソースをサポートしない製品タイプ**: 静的ライブラリなど、バンドルではないためリソースをサポートしない製品タイプが存在します。そのため、フレームワークなど別の製品タイプを採用する必要があり、プロジェクトやアプリにオーバーヘッドが生じる可能性があります。例えば、静的フレームワークは最終製品に静的にリンクされ、リソースだけを最終製品にコピーするためのビルドフェーズが必要になります。また、動的フレームワークの場合、Xcode はバイナリとリソースの両方を最終製品にコピーしますが、フレームワークを動的に読み込む必要があるため、アプリの起動時間が増加します。
- **ランタイムエラーが発生しやすい**: リソースは名前と拡張子（文字列）で識別されます。そのため、これらのいずれかにタイポがあると、リソースへのアクセス時にランタイムエラーが発生します。コンパイル時に検出されず、リリース版でクラッシュを引き起こす可能性があるため、理想的ではありません。

Tuist は、実装の詳細を抽象化した**バンドルとリソースにアクセスするための統一されたインターフェースを生成**することで、上記の問題を解決します。

> [!WARNING]
> **推奨**
>
> Tuist が生成したインターフェースを通じてリソースにアクセスすることは必須ではありませんが、コードの理解を容易にし、リソースの移動を簡素化できるため、推奨しています。


## リソース {#resources}

Tuist は、`Info.plist` や entitlements などのファイルの内容を Swift で宣言するためのインターフェースを提供します。これは、ターゲットやプロジェクト間の一貫性を確保し、コンパイラを活用してコンパイル時に問題を検出するのに役立ちます。また、独自のアブストラクションを作成して内容をモデル化し、ターゲットやプロジェクト間で共有することも可能です。

プロジェクトが生成されると、Tuist はこれらのファイルの内容を生成し、それらを定義しているプロジェクトを含むディレクトリ相対の `Derived` ディレクトリに書き込みます。

> [!TIP]
> **Derived ディレクトリを Gitignore に追加**
>
> プロジェクトの `.gitignore` ファイルに `Derived` ディレクトリを追加することを推奨します。


## バンドルアクセサ {#bundle-accessors}

Tuist は、ターゲットリソースを含むバンドルにアクセスするためのインターフェースを生成します。

### Swift {#swift}

ターゲットには、バンドルを公開する `Bundle` 型の拡張が含まれます。

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C では、バンドルにアクセスするための `{Target}Resources` インターフェースが提供されます。

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **内部ターゲットにおける制限**
>
> 現在、Tuist は Objective-C ソースのみを含む内部ターゲットのリソースバンドルアクセサを生成しません。これは既知の制限であり、[issue #6456](https://github.com/tuist/tuist/issues/6456) で管理されています。


> [!TIP]
> **バンドルを通じてライブラリでリソースをサポート**
>
> ライブラリなどのターゲット製品がリソースをサポートしていない場合、Tuist はリソースを製品タイプ `bundle` のターゲットに含め、最終製品に含まれるようにし、インターフェースが正しいバンドルを指すようにします。これらの生成されたバンドルには自動的に `tuist:synthesized` タグが付与され、親ターゲットのすべてのタグを継承するため、<.localized_link href="/guides/features/projects/metadata-tags#system-tags">キャッシュプロファイル</.localized_link> で対象とすることができます。


## リソースアクセサ {#resource-accessors}

リソースは名前と拡張子（文字列）で識別されます。これはコンパイル時に検出されず、リリース版でクラッシュを引き起こす可能性があるため、理想的ではありません。これを防ぐため、Tuist はプロジェクト生成プロセスに [SwiftGen](https://github.com/SwiftGen/SwiftGen) を統合し、リソースにアクセスするためのインターフェースを生成します。これにより、コンパイラを活用して問題を確実に検出しながら、安心してリソースにアクセスできます。

Tuist には、以下のリソースタイプに対するアクセサをデフォルトで生成するための [テンプレート](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates) が含まれています。

| リソースタイプ | 生成されるファイル |
| --- | ---- |
| 画像とカラー | `Assets+{Target}.swift` |
| 文字列 | `Strings+{Target}.swift` |
| Plist | `{NameOfPlist}.swift` |
| フォント | `Fonts+{Target}.swift` |
| ファイル | `Files+{Target}.swift` |

> 注: プロジェクトオプションに `disableSynthesizedResourceAccessors` オプションを渡すことで、プロジェクト単位でリソースアクセサの生成を無効にできます。

#### カスタムテンプレート {#custom-templates}

[SwiftGen](https://github.com/SwiftGen/SwiftGen) でサポートされている他のリソースタイプに対するアクセサを生成するための独自のテンプレートを提供したい場合は、`Tuist/ResourceSynthesizers/{name}.stencil` に作成できます。ここで、名前はリソースのキャメルケース版です。

| リソース | テンプレート名 |
| --- | --- |
| strings | `Strings.stencil` |
| assets | `Assets.stencil` |
| plists | `Plists.stencil` |
| fonts | `Fonts.stencil` |
| coreData | `CoreData.stencil` |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json | `JSON.stencil` |
| yaml | `YAML.stencil` |
| files | `Files.stencil` |

生成するアクセサのリソースタイプを構成したい場合は、`Project.resourceSynthesizers` プロパティを使用して、使用するリソースシンセサイザーのリストを渡します。

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [!NOTE]
> **参考**
>
> カスタムテンプレートを使用してリソースへのアクセサを生成する方法については、[この例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates) をご覧ください。
