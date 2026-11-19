---
{
  "title": "合成ファイル",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuistプロジェクトにおける合成ファイルについて学びます。"
}
---
# 合成ファイル {#synthesized-files}

Tuist は生成時にファイルやコードを自動生成し、Xcode プロジェクトの管理と作業を便利にします。このページでは、その機能の概要とプロジェクトでの使い方を説明します。

## ターゲットリソース {#target-resources}

Xcode プロジェクトでは、ターゲットにリソースを追加できます。ただし、ソースやリソースが頻繁に移動されるモジュラープロジェクトで作業する場合、チームはいくつかの課題に直面します。

- **ランタイムアクセスの一貫性の欠如**: リソースが最終製品内のどこに配置され、どのようにアクセスするかは、ターゲットの製品タイプによって異なります。例えば、ターゲットがアプリケーションを表す場合、リソースはアプリケーションバンドルにコピーされます。これにより、リソースへのアクセスコードがバンドル構造を前提とするようになり、コードの理解が難しくなり、リソースの移動も煩雑になるため、理想的ではありません。
- **リソースをサポートしない製品タイプ**: 静的ライブラリなど、バンドルではないためリソースをサポートしない製品タイプが存在します。そのため、フレームワークなど別の製品タイプを採用する必要があり、プロジェクトやアプリにオーバーヘッドが生じる可能性があります。例えば、静的フレームワークは最終製品に静的にリンクされ、リソースだけを最終製品にコピーするためのビルドフェーズが必要になります。また、動的フレームワークの場合、Xcode はバイナリとリソースの両方を最終製品にコピーしますが、フレームワークを動的に読み込む必要があるため、アプリの起動時間が長くなります。
- **ランタイムエラーが発生しやすい**: リソースは名前と拡張子（文字列）で識別されます。そのため、いずれかにタイプミスがあると、リソースへのアクセス時にランタイムエラーが発生します。コンパイル時に検出されず、リリース版でクラッシュを引き起こす可能性があるため、理想的ではありません。

Tuist は、実装の詳細を抽象化する**バンドルとリソースにアクセスするための統一インターフェースを合成**することで、上記の問題を解決します。

> [!WARNING]
> **推奨**
>
> Tuist が合成したインターフェースを通じてリソースにアクセスすることは必須ではありませんが、コードの理解が容易になり、リソースの移動も簡素化されるため、推奨します。


## リソース {#resources}

Tuist は、`Info.plist` や entitlements などのファイルの内容を Swift で宣言するためのインターフェースを提供します。これは、ターゲットやプロジェクト間の一貫性を確保し、コンパイラを活用してコンパイル時に問題を検出するのに役立ちます。また、独自に抽象化を定義して内容をモデル化し、ターゲットやプロジェクト間で共有することも可能です。

プロジェクトが生成されると、Tuist はそれらのファイルの内容を合成し、それらを定義したプロジェクトを含むディレクトリからの相対パスにある `Derived` ディレクトリに書き込みます。

> [!TIP]
> **Derived ディレクトリを .gitignore に追加**
>
> プロジェクトの `.gitignore` ファイルに `Derived` ディレクトリを追加することを推奨します。


## バンドルアクセサ {#bundle-accessors}

Tuist は、ターゲットリソースを含むバンドルにアクセスするためのインターフェースを合成します。

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
> **内部ターゲットに関する制限**
>
> 現在、Tuist は Objective-C ソースのみを含む内部ターゲットのリソースバンドルアクセサを生成しません。これは既知の制限であり、[issue #6456](https://github.com/tuist/tuist/issues/6456) で管理されています。


> [!TIP]
> **バンドル経由でライブラリのリソースをサポート**
>
> ライブラリなどのターゲット製品がリソースをサポートしていない場合、Tuist はリソースを製品タイプ `bundle` のターゲットに含め、最終製品に正しく配置され、インターフェースが適切なバンドルを指すようにします。これらの合成されたバンドルには自動的に `tuist:synthesized` タグが付与され、親ターゲットのすべてのタグを継承するため、<.localized_link href="/guides/features/projects/metadata-tags#system-tags">キャッシュプロファイル</.localized_link>で対象とすることができます。


## リソースアクセサ {#resource-accessors}

リソースは名前と拡張子を文字列で識別します。これはコンパイル時に検出されず、リリース版でクラッシュを引き起こす可能性があるため、理想的ではありません。これを防ぐため、Tuist はプロジェクト生成プロセスに [SwiftGen](https://github.com/SwiftGen/SwiftGen) を統合し、リソースにアクセスするためのインターフェースを合成します。これにより、コンパイラを活用して問題を確実に検出しながら、安心してリソースにアクセスできます。

Tuist には、デフォルトで以下のリソースタイプのアクセサを合成するための [テンプレート](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates) が含まれています。

| リソースタイプ | 合成ファイル |
| --- | ---- |
| 画像とカラー | `Assets+{Target}.swift` |
| Strings | `Strings+{Target}.swift` |
| Plists | `{NameOfPlist}.swift` |
| フォント | `Fonts+{Target}.swift` |
| ファイル | `Files+{Target}.swift` |

> 注: プロジェクトオプションに `disableSynthesizedResourceAccessors` オプションを渡すことで、プロジェクトごとにリソースアクセサの合成を無効にできます。

### カスタムテンプレート {#custom-templates}

他のリソースタイプのアクセサを合成するための独自のテンプレートを提供したい場合（[SwiftGen](https://github.com/SwiftGen/SwiftGen) でサポートされている必要があります）、`Tuist/ResourceSynthesizers/{name}.stencil` に作成できます。ここで name はリソース名のキャメルケース版です。

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

合成するアクセサのリソースタイプリストを設定したい場合は、`Project.resourceSynthesizers` プロパティを使用して使用するリソースシンセサイザーのリストを渡します。

```swift
let project = Project(name: "App", resourceSynthesizers: [.strings(), .fonts()])
```

> [!NOTE]
> **参考**
>
> カスタムテンプレートを使用してリソースへのアクセサを合成する方法の例は、[この例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)をご覧ください。
