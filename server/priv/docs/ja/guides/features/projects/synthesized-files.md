---
{
  "title": "合成ファイル",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist プロジェクトにおける合成ファイルについて学びます。"
}
---
# 生成されるファイル {#synthesized-files}

Tuist は、Xcode プロジェクトの管理と作業を便利にするために、生成時にファイルやコードを生成できます。このページでは、この機能とそのプロジェクトでの活用方法について説明します。

## ターゲットのリソース {#target-resources}

Xcode プロジェクトでは、ターゲットにリソースを追加できます。ただし、ソースやリソースが頻繁に移動するモジュラープロジェクトで作業する場合など、チームはいくつかの課題に直面します。

- **ランタイムアクセスの一貫性の欠如**: リソースが最終的な製品内のどこに配置され、どのようにアクセスされるかは、ターゲットの製品タイプによって異なります。例えば、ターゲットがアプリケーションを表す場合、リソースはアプリケーションバンドルにコピーされます。これにより、リソースにアクセスするコードがバンドル構造を前提とするようになり、コードの理解が難しくなり、リソースの移動も煩雑になるため、理想的ではありません。
- **リソースをサポートしない製品タイプ**: 静的ライブラリのようにバンドルではないためリソースをサポートしない製品タイプがあります。そのため、フレームワークなど別の製品タイプを使用する必要があり、プロジェクトやアプリにオーバーヘッドが生じる可能性があります。例えば、静的フレームワークは最終的な製品に静的にリンクされ、リソースのみを最終製品にコピーするためのビルドフェーズが必要です。また、動的フレームワークの場合、Xcode はバイナリとリソースの両方を最終製品にコピーしますが、フレームワークを動的に読み込む必要があるため、アプリの起動時間が長くなります。
- **ランタイムエラーが発生しやすい**: リソースは名前と拡張子（文字列）で識別されます。そのため、いずれかにタイプミスがあると、リソースへのアクセス時にランタイムエラーが発生します。コンパイル時に検出されず、リリース版でクラッシュを引き起こす可能性があるため、理想的ではありません。

Tuist は、実装の詳細を抽象化した**バンドルとリソースにアクセスするための統一されたインターフェースを生成する**ことで、上記の問題を解決します。

> [!WARNING]
> **推奨**
>
> Tuist が生成したインターフェースを通じてリソースにアクセスすることは必須ではありませんが、コードの理解が容易になり、リソースの移動も簡素化されるため、これを推奨します。


## リソース {#resources}

Tuist は、`Info.plist` や entitlements などのファイルの内容を Swift で宣言するためのインターフェースを提供します。これは、ターゲットやプロジェクト間の一貫性を確保し、コンパイラを活用してコンパイル時に問題を検出するために役立ちます。また、独自のアブストラクションを作成して内容をモデル化し、ターゲットやプロジェクト間で共有することも可能です。

プロジェクトが生成されると、Tuist はそれらのファイルの内容を生成し、それらを定義したプロジェクトを含むディレクトリに対する相対パスにある `Derived` ディレクトリに書き込みます。

> [!TIP]
> **Derived ディレクトリを Gitignore に追加する**
>
> プロジェクトの `.gitignore` ファイルに `Derived` ディレクトリを追加することを推奨します。


## バンドルアクセサ {#bundle-accessors}

Tuist は、ターゲットのリソースを含むバンドルにアクセスするためのインターフェースを生成します。

### Swift {#swift}

ターゲットには、バンドルを公開する `Bundle` 型の拡張機能が含まれます。

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
> 現在、Tuist は Objective-C ソースのみを含む内部ターゲットに対してリソースバンドルアクセサを生成しません。これは既知の制限事項であり、[issue #6456](https://github.com/tuist/tuist/issues/6456) で管理されています。


> [!TIP]
> **バンドルを通じてライブラリでリソースをサポートする**
>
> ライブラリなどのターゲット製品がリソースをサポートしていない場合、Tuist は製品タイプが `bundle` のターゲットにリソースを含め、それが最終製品に含まれ、インターフェースが正しいバンドルを指すようにします。これらの生成されたバンドルには自動的に `tuist:synthesized` タグが付与され、親ターゲットのすべてのタグを継承するため、<.localized_link href="/guides/features/projects/metadata-tags#system-tags">キャッシュプロファイル</.localized_link>で対象とすることができます。


## リソースアクセサ {#resource-accessors}

リソースは名前と拡張子を文字列で識別します。これはコンパイル時に検出されず、リリース版でクラッシュを引き起こす可能性があるため、理想的ではありません。これを防ぐため、Tuist はプロジェクト生成プロセスに [SwiftGen](https://github.com/SwiftGen/SwiftGen) を統合し、リソースにアクセスするためのインターフェースを生成します。これにより、コンパイラを活用して問題を確実に検出しながら、自信を持ってリソースにアクセスできます。

Tuist には、以下のリソースタイプに対するアクセサをデフォルトで生成するための [テンプレート](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates) が含まれています。

| リソースタイプ | 生成されるファイル |
| --- | ---- |
| 画像とカラー | `Assets+{Target}.swift` |
| 文字列 | `Strings+{Target}.swift` |
| Plist | `{NameOfPlist}.swift` |
| フォント | `Fonts+{Target}.swift` |
| ファイル | `Files+{Target}.swift` |

> 注: プロジェクトオプションに `disableSynthesizedResourceAccessors` オプションを渡すことで、プロジェクトごとにリソースアクセサの生成を無効にできます。

### カスタムテンプレート {#custom-templates}

他のリソースタイプに対するアクセサを生成するための独自のテンプレートを提供したい場合（[SwiftGen](https://github.com/SwiftGen/SwiftGen) でサポートされている必要があります）、`Tuist/ResourceSynthesizers/{name}.stencil` に作成できます。ここで、name はリソース名のキャメルケース版です。

| リソース | テンプレート名 |
| --- | --- |
| 文字列 | `Strings.stencil` |
| アセット | `Assets.stencil` |
| Plist | `Plists.stencil` |
| フォント | `Fonts.stencil` |
| Core Data | `CoreData.stencil` |
| Interface Builder | `InterfaceBuilder.stencil` |
| JSON | `JSON.stencil` |
| YAML | `YAML.stencil` |
| ファイル | `Files.stencil` |

アクセサを生成するリソースタイプのリストを設定したい場合は、`Project.resourceSynthesizers` プロパティを使用して、使用するリソースシンセサイザーのリストを渡すことができます。

```swift
let project = Project(name: "App", resourceSynthesizers: [.strings(), .fonts()])
```

> [!NOTE]
> **参考**
>
> カスタムテンプレートを使用してリソースへのアクセサを生成する方法については、[この例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)をご確認ください。
