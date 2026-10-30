---
{
  "title": "Xcode キャッシュ",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Tuist の Xcode キャッシュ統合により、ローカルおよび CI 環境での Xcode ビルドを高速化します。"
}
---
# Xcode キャッシュ {#xcode-cache}

Tuist は Xcode のコンパイルキャッシュをサポートしており、ビルドシステムのキャッシング機能を活用してチーム間でコンパイル成果物を共有できます。

Xcode キャッシュは Xcode 26 で導入されました。Xcode ビルドキャッシュと呼ばれることもあります。このキャッシュは入力に基づいてキー付けされたコンパイル成果物を再利用し、Tuist のリモートキャッシュにより、これらの成果物をマシン間で共有可能にします。

> [!TIP]
> **モジュールキャッシュと併用する**
>
> Xcode キャッシュと<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>は異なる粒度で動作し、互いに補完し合います。モジュールキャッシュはビルド実行前にモジュール全体を事前ビルド済みの `.xcframework` に置き換えますが、Xcode キャッシュはビルド中にコンパイル出力を再利用します。

> [!TIP]
> **開発者マシンでは、クリーン時に `CompilationCache.noindex` を保持する**
>
> デフォルトでは、コンパイルキャッシュのストアは `DerivedData` 内に存在するため、`DerivedData` を削除するとビルド成果物とともにキャッシュも失われます。開発者マシンでは、ビルド成果物のみを削除することをお勧めします。これにより、再ビルド時にディスク上のストアからリプレイされ、何もフェッチする必要がありません。

## セットアップ {#setup}

Tuist アカウントとプロジェクトをまだお持ちでない場合は、以下を実行して作成できます。

```bash
tuist init
```

`Tuist.swift` ファイルがあり、それがあなたの `fullHandle` を参照している場合、以下を実行してプロジェクトのキャッシングを設定できます。

```bash
tuist setup cache
```

このコマンドは、Swift [ビルドシステム](https://github.com/swiftlang/swift-build) がコンパイル成果物を共有するために使用するローカルキャッシュサービスを起動時に実行するための [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) を作成します。最初は開発者マシンで実行し、各 CI ジョブのセットアップの一部として実行してください。

CI でキャッシュを設定するには、<.localized_link href="/guides/integrations/continuous-integration#authentication">認証済み</.localized_link>であることを確認してください。

### キャッシュコンポーネントの更新 {#updating-the-cache-components}

キャッシュプロキシは、最後にセットアップを実行した Tuist インストールに固定されたパスではなく、安定したランチャーを使用します。インストールされると、`tuist setup cache` およびキャッシュ有効化された `tuist generate` は、利用可能なターゲットを新しい Tuist リリースに進めます。したがって、古い Tuist に固定されたプロジェクトでも、共有プロキシのダウングレードは発生しません。生成は既存のランチャーターゲットのみを更新します。サービスのインストール、認証、プラグインの置き換え、またはプロキシの再起動は行いません。カスタムプラグイン、プロキシ、ソケット、またはレジストリのオーバーライドがある場合、自動的な進捗はスキップされます。

実行中のプロキシは、キャッシュリクエストが少なくとも 30 秒間なく、進行中のリクエストやバックグラウンド作業がなく、公開スプールが空になった後にのみ、新しいターゲットを採用します。その後終了し、launchd が選択された CLI を起動し、サービスの引数と認証情報環境を保持します。実際にターゲットを採用したプロキシのみが、バンドルからディスク上のプラグインをアトミックに更新します。古いプロキシがまだドレインしている間は、セットアップによって新しいプラグインがインストールされることはありません。インストールされたプラグインが見つからない場合、明示的なアイドル状態のセットアップにより、選択されたプロキシが再起動され、更新が再試行されます。レジストリとスプールを所有するプロキシは依然として 1 つだけです。利用できないターゲットまたはドレインされていないアップロードがある場合、アクティブなリクエストを中断するのではなく、切り替えが遅延されます。認証情報の更新は、切り替えの前でも選択された CLI に従うため、古い CLI インストールを削除しても、ドレイン待ちのアップロードが取り残されることはありません。

安定したランチャー以前に作成された既存のインストールには、明示的な移行が 1 回必要です。ビルドが実行されていないときに以下を実行してください。

```bash
tuist setup cache
```

その移行後、Tuist を更新して通常の `tuist generate` を実行するだけで、プロキシとインストールされたプラグインを進めることができます。各 CLI リリースごとにセットアップを再実行する必要はありません。異なる Xcode（同じパスで更新された Xcode を含む）を選択するには、依然として明示的なセットアップが必要です。設定が変更されると、セットアップは共有サービスを置き換えることができるため、まずマシン上のすべてのビルドが完了するのを待ってください。プロキシは以前のプラグインプロトコルと現在のプロトコルの両方をサポートしているため、Xcode にすでに読み込まれている互換性のあるプラグインは、プロキシのアップグレード後も動作し続けます。最新のプラグインを読み込むには、Xcode を完全に終了して再度開いてください。ただし、互換性のある読み込み済みプラグインの場合、即時の再起動は必要ありません。リリースによって生成されたビルド設定が変更された場合は、プロジェクトを再生成してください。

選択した Tuist インストールを利用可能な状態に保ってください。ランチャーは、起動、構成、および認証情報の更新にそれを使用します。ランチャーが進んだら、古いインストールを削除できます。選択した実行可能ファイルが削除されたか、実行可能でなくなった場合、`tuist setup cache` は、キャッシュを最初に解体することなく、利用可能なインストール（古いリリースであっても）を使用してターゲットを修復できます。安定した実行可能ファイルのエイリアスは、パッケージマネージャーのアップグレードを通じて保持されます。シンボリックリンクは、インストール ID を比較するときのみ解決されます。起動時、プロキシは実際に起動されたバージョン（その場での更新や意図的なロールバックを含む）を記録し、関連のない古いチェックアウトが利用可能なインストールに切り替えるのを防ぐために、使用された最高バージョンを保持します。

リリースバージョンのないソースビルド CLI および明示的な `TUIST_CAS_PLUGIN_PATH` または `TUIST_CAS_PROXY_PATH` セットアップは、自動バージョン選択ではなく明示的な起動構成を使用します。それらのコンポーネントを再ビルドした後、セットアップを再実行してください。セットアップはそれらの新鮮さを確認し、置換が準備できて初めて管理対象ターゲットの進捗を無効にします。

`tuist teardown cache` は、ランチャーターゲットを削除する前にサービスを停止し、既存のプロジェクトのために安定したプラグインを保持します。サービスの停止に失敗した場合、そのランチャーは再起動および別のティアダウン試行のために利用可能なままになります。成功したティアダウン後、生成によってサービスを再作成することはできません。

### Xcode ビルド設定の構成 {#configure-xcode-build-settings}

既存の Xcode プロジェクトの場合、`tuist setup cache` によって出力されたビルド設定をプロジェクトのビルド設定または既存の `.xcconfig` ファイルにコピーしてください。このコマンドはあなたのアカウントの構成を出力しますが、構成ファイルを生成したり Xcode プロジェクトを編集したりすることはありません。`OTHER_SWIFT_FLAGS` を拡張する際は `$(inherited)` を保持し、他のコンパイラオプションが保存されるようにしてください。

設定には以下が含まれます。

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_PLUGIN_PATH = $HOME/.local/state/tuist/libtuist_cas_plugin.dylib
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock
COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
OTHER_SWIFT_FLAGS = $(inherited) -cas-plugin-option tuist-instance=your-org/your-project
```

`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH`、および `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` は、Xcode のビルド設定 UI で直接公開されていないため、**ユーザー定義ビルド設定**として追加する必要があることに注意してください。

> [!NOTE]
> **プラグインパス**
>
> `libtuist_cas_plugin.dylib` は Tuist に同梱されるコンパイルキャッシュプラグインで、`tuist` 実行ファイルの隣に配置されます。`tuist setup cache` はこれを `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib` にコピーし、`COMPILATION_CACHE_PLUGIN_PATH` がそのコピーを指します。パスはすべてのマシンで同じであり、Tuist を更新しても変わらないため、この設定をプロジェクトと一緒にコミットできます。セットアップと新たに起動されたプロキシは、選択された Tuist バンドルからコピーを更新します。古いチェックアウトからセットアップを実行しても、新しいプラグインがダウングレードされることはありません。

> [!NOTE]
> **プロジェクトごとに 1 つのソケット**
>
> `tuist setup cache` はマシンごとに単一のキャッシュプロキシをインストールするため、すべてのプロジェクトが同じ `COMPILATION_CACHE_REMOTE_SERVICE_PATH` を使用します。プロジェクトを識別するのは `tuist-instance` プラグインオプションです。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` が C と Objective-C を共有する仕組み**
>
> この設定を「キャッシュサービスの場所」と読み取り、任意のものとして扱いがちですが、実際には C、Objective-C、プリコンパイル済みモジュール、およびプリコンパイル済みヘッダーを共有するかどうかを決定するスイッチでもあります。ビルドシステムは、リモートキャッシュサービスが構成されている場合にのみ、それらのキャッシングを実行します。これを省略しても Swift コンパイルは共有されますが、以前にプロジェクトをビルドしていないマシンでは、すべての C/Objective-C ファイルとすべてのモジュールが再コンパイルされます。

> [!NOTE]
> **並列キャッシュルックアップ**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` は、ビルドの実行レーンで一度に少数ずつ処理するのではなく、ビルドの残りの部分と同時に、ビルドシステムが各コンパイルに対して行うリモートキャッシュルックアップを実行します。 distant cache から多くのコンパイルをミスしたり復元したりするビルドは、より早く完了します。

`xcodebuild` を実行する際に、以下のようなフラグを追加してこれらの設定を指定することもできます。

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_PLUGIN_PATH=$HOME/.local/state/tuist/libtuist_cas_plugin.dylib \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/cas-proxy.sock \
    COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=your-org/your-project'
```

> [!NOTE]
> **Xcode 27 以降でのプレフィックスマッピング**
>
> Xcode 27 以降では、`tuist setup cache` は `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、および `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` も出力します。これらは、プロジェクトと `DerivedData` の場所とは無関係にコンパイルキャッシュキーを独立させます。ユーザー定義ビルド設定として追加してください。有効にするとすべてのキャッシュキーが変更されるため、次のビルドでキャッシュが再び構築されます。`enableCaching` がオンの場合、`tuist generate` がこれらを自動的に設定します。
>
> コンパイラはマップされたパスをコードカバレッジデータにも書き込むため、Xcode はそれらを解決できず、カバレッジレポートからはプレフィックスマッピングを使用してコンパイルされたすべてのソースが除外されます。出力された設定と `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` の設定は、コードカバレッジを収集するビルドでプレフィックスマッピングを無効にします。`tuist generate` も同様です。これらのビルドでもコンパイルキャッシュは使用されますが、キャッシュキーはプロジェクトと `DerivedData` のパスに依存します。
>
> コマンドラインで `xcodebuild` にこれらの設定を渡す際は、`OTHER_SWIFT_FLAGS` の例と同様に、`$(...)` を含む値をシングルクォートで囲んでください。そうしないと、シェルがそれらを空文字列に展開し、プレフィックスマッピングが無効になります。
>
> ```
> xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
>     'SWIFT_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     'CLANG_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_NO=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_YES=NO
> ```

> [!NOTE]
> **生成されたプロジェクト**
>
> プロジェクトが Tuist によって生成されている場合は、設定を手動で行う必要はありません。
>
> その場合、`Tuist.swift` ファイルに `enableCaching: true` を追加するだけで済みます。
> ```swift
> import ProjectDescription
>
> let tuist = Tuist(
>     fullHandle: "your-org/your-project",
>     project: .tuist(
>         generationOptions: .options(
>             enableCaching: true
>         )
>     )
> )
> ```

### プレフィックスマッピングを使用したカバレッジ {#coverage-with-prefix-mapping}

デフォルトでは、生成されたプロジェクトは Xcode のカバレッジレポートと `xccov` が機能するように、カバレッジビルド用のプレフィックスマッピングを無効にします。チェックアウト間でカバレッジコンパイルを共有可能にするために、これを有効にすることができます。

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            enableCaching: true,
            coverage: .coverage(prefixMapping: true)
        )
    )
)
```

`TUIST_COVERAGE_PREFIX_MAPPING` 環境変数（`1` または `0`）は `prefixMapping` より優先されます。このオプションは Xcode 27 以降に適用され、`enableCaching` が必要です。カバレッジ `tuist test` アップロードはこれをサポートしています。Tuist は `llvm-cov` を使用して実行を測定し、マップされたパスでソースを読み取り、それをリポジトリのファイルに紐付けます。Xcode 自体のカバレッジレポートと `xccov` は依然としてそれらのソースを除外することがあり、`llvm-cov` エクスポートが失敗したために結果バンドルの `xccov` レポートにフォールバックするアップロードでも同様です。マップされた `#filePath` 値は、ソースファイル相対でフィクスチャを探すテストにも影響を与える可能性があります。代わりに明示的なランタイムチェックアウトパスを通じてフィクスチャを解決してください。カバレッジを自分で処理する場合は、計測された各バイナリをそのターゲットの `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` と組み合わせてください。これは仮想プレフィックスをローカルディレクトリにマッピングし直します。プロジェクトごとのマッピングが有効な場合、あるターゲットのマップをすべてのバイナリで再利用しないでください。

カバレッジプレフィックスの設定は、カバレッジアーティファクトに書き込まれるパスを制御するため、バイナリキャッシュと選択的テストのハッシュに影響します。このオプションを変更するか、`TUIST_COVERAGE_PREFIX_MAPPING` を異なる値に設定すると、通常のビルドでもこれらのハッシュが無効になります。バイナリキャッシュと選択的テストの結果を共有する必要がある場合は、開発者と CI ジョブ間で値を一貫させてください。

### 生成されたプロジェクトのデバッグ {#debugging-generated-projects}

復元されたネイティブモジュールには、リンクされたデバッグ情報だけでなく、コンパイルキャッシュへのアクセスも必要です。Tuist は Debug および Release モジュールを dSYM とスライスごとのソース識別メタデータでウォームアップし、ターゲットを置き換える前に、メタデータをコンシューマーが宣言したソースに対して検証します。メタデータが欠落しているか互換性がない場合、そのターゲットのソースは保持されます。スクリプト生成された `.generated(...)` ソースは、検証可能なコンテンツチェックサムではなく宣言フィンガープリントを持つため、それらのターゲットはソースビルドのままとなり、ネイティブモジュールキャッシュには公開されません。実際のコンテンツチェックサムを持つ生成されたリソースアクセサは対象となります。サポートされていないデバッグ情報がある場合、影響を受けるターゲットの公開はスキップされますが、無関係な製品はブロックされません。ソースの変更とキャンセルは依然としてウォームアップを失敗させます。キャッシュ形式が変更されるため、古いバージョンでウォームアップされたアーティファクトは再ウォームアップが必要です。

検証済みの置き換えの場合、Tuist はコンシューマー所有の dSYM UUID plists でソースの再配置を準備し、静的キャッシュコード用のデバッグ専用コンパニオンをリンクします。キャッシュされたバイナリを書き換えたり、LLDB の永続的なグローバルソースマップにプロデューサーソースパスをインストールしたりすることはありません。明示的なデバッガ初期化子とモジュールローダー設定が優先されます。デバッグシンボルとソースの再配置は、ソース相対のランタイムファイルアクセスやネイティブな Xcode カバレッジレポートを修復しません。カバレッジバリアントの選択と LLVM エクスポートは別々の機能です。

`enableCaching: true` を使用すると、Tuist は Run および Test アクション用に LLDB ソースマップを設定します。アクションにカスタム LLDB 初期化子が設定されている場合、Tuist はまず解決済みのソースマップを書き込み、その後カスタム初期化子をソースとして読み込むことで、マップの拡張や上書きを可能にします。それ以外の場合、ソースマップを置き換える前に、ファイルが存在すれば `~/.lldbinit-Xcode` を読み込み、存在しなければ `~/.lldbinit` にフォールバックします。ホームファイルは 1 つだけ読み込まれ、二重読み込みを防ぎながらユーザーごとのデバッガ設定を復元します。この置き換えにより、前回の実行からの古くなったマッピングが削除され、ホームファイルのソースマップよりも優先されます。維持すべきソースマップのエントリは、アクションのカスタム初期化子に記述してください。その他のホーム設定は保持されます。Tuist のキャッシュ固有のモジュール検索パス、ローダー設定、および Clang フラグはその後適用され、これらの設定に関するユーザー値よりも優先されます。ホームファイルのエラーは表示されたままですが、後続のコマンドの読み込みを停止することはありません。また、コマンドはエコーされません。この初期化子の保持は、モジュールキャッシュから復元されたバイナリのデバッグを Tuist が設定する場合にも適用され、`enableCaching` がなくても、また以前の Xcode バージョンでも有効です。

Xcode 27 以降では、生成されたプロジェクトは、プロジェクトで明示的に設定されていない限り、Xcode のプロジェクト別プレフィックスマッピング（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` および `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`）を無効にします。`/^src` などのプレフィックスは、プロジェクトごとに異なるディレクトリを指し、LLDB はデバッグ対象のターゲットのプロジェクトに対してのみこれを解決します。代わりに、ソースはワークスペース全体のプレフィックスの下に記録されます。`/^root` は Tuist ルートディレクトリ、`/^spm` は Swift パッケージのスクラッチディレクトリ、`/^intermediates` および `/^products` はビルド出力用です。これらはすべてのプロジェクトで同じディレクトリを指すため、ワークスペース内の任意のプロジェクトのソースでブレークポイントが解決されます。

Tuist ルート外のパスはマッピングされません。ルート外のプロジェクトのキャッシュキーはチェックアウト場所に依存するため、他のチェックアウトやマシンではそのキャッシュが見つかりません。チェックアウト場所に依存しないキーを維持するには、そのプロジェクトのマニフェストでプロジェクト別マッピングを有効にします。

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

これらの設定をその `Project` に渡します。別のプロジェクトのターゲットをデバッグする場合、LLDB はそのプロジェクトのソースを見つけられなくなります。マニフェストのプロジェクト基本設定はプロジェクトレベルの xcconfig 値よりも優先されるため、マニフェスト自体で設定してください。

これらの設定を変更すると、コンパイルキャッシュキー、バイナリキャッシュハッシュ、および選択的テストハッシュが変更されるため、それらのキャッシュを再度ウォームアップする必要があります。チーム全体で一貫した選択を維持してください。

### キャッシュアップロードポリシー {#cache-upload-policy}

デフォルトでは、キャッシュサービスはリモートキャッシュへのアーティファクトのダウンロードとアップロードの両方を行います。`Tuist.swift` ファイルの `xcodeCache` オプションを使用して、アーティファクトはダウンロードされるがアップロードされない読み取り専用モードを有効にすることができます。

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: false
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

一般的なパターンは、ビルドが再現可能な CI からのみアーティファクトをプッシュし、ローカル環境を読み取り専用に保つことです。これは、ほとんどの CI プロバイダーによって設定される `CI` 環境変数をチェックする `Environment.isCI` を使用して実現できます。

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: Environment.isCI
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

この設定により、ローカルビルドはアップロードなしでキャッシュされたアーティファクトの恩恵を受け、CI ビルドはチームの残りのメンバーのためにキャッシュを準備します。

アップロードポリシーは、`tuist setup cache` を実行するマシン上でプロジェクトごとに記録されます。これを変更するには、`upload` を更新して `tuist setup cache` を再度実行し、Tuist がプロジェクトを生成している場合は `tuist generate` も実行してください。その後、そのマシン上のキャッシュを再起動することなく、新しいポリシーに従ってアップロードが行われます。同じマシンで同時に実行される同じプロジェクトのジョブはそのポリシーを共有するため、最新の `tuist setup cache` がすべてに対して決定します。

### ストアサイズ制限 {#store-size-limit}

コンパイルキャッシュストアはビルドごとに増大します。プロジェクトのストアを制限するには、`Tuist.swift` ファイルで `storeSizeLimit` を設定します。

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        storeSizeLimit: .gigabytes(20)
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

ビルドが実行されていない間、Tuist は 10 分ごとにプロジェクトの各ストアをチェックします。新しいビルドが制限の約半分を書き込むと、ストアの最も古いキャッシュ出力が削除されるため、ストアは制限付近で安定します。ビルド実行中はストアが制限を超えることがあり、制限設定時にすでに大きかったストアは、新しいビルドがその量を書き込むと縮小します。複数のプロジェクトが同じストア（デフォルトの場所など）を使用する場合、最小の制限が適用されます。この制限は `tuist setup cache` を実行するすべてのマシンに適用されるため、制限を変更した後は再度実行してください。

### モジュールキャッシュハッシュ {#module-cache-hashes}

コンパイルキャッシュ設定は <.localized_link href="/guides/features/projects/hashing">モジュールキャッシュハッシュ</.localized_link> の一部ではありません。Tuist は、すべての `COMPILATION_CACHE_*` ビルド設定と、その値を持つすべての `-cas-plugin-option` フラグをハッシュから除外します。`enableCaching` のオン/オフ切り替えやアップロードポリシーの変更は、ターゲットのハッシュを保持するため、すでにウォームアップ済みの <.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> バイナリは有効なままです。Xcode キャッシュの有無にかかわらず、同じモジュールキャッシュに対してビルドを比較できます。

> [!NOTE]
> **プレフィックスマッピング設定はハッシュ化されます**
>
> Xcode 27 以降では、`enableCaching: true` は `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`、および `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 設定も設定します。これらの設定はモジュールキャッシュハッシュの一部であるため、Xcode 27 以降では `enableCaching` のオン/オフ切り替えによりターゲットのハッシュが変更されます。

### 大きな出力の一部の再利用 {#reusing-parts-of-large-outputs}

Xcode キャッシュは、コンテンツ定義チャンキングにより転送量を削減できます。各大きな出力を以前のバージョンとは無関係なものとして扱うのではなく、コンテンツによって決定される境界で圧縮出力を分割します。編集後、オフセットが変更されていても、一致するチャンクを再利用できます。

アップロードでは、サーバーに欠けているチャンクのみを送信します。ダウンロードでは、まず正確なキャッシュアクションと出力のチャンクレシピを取得し、次にローカルマシンに保存されている検証済みチャンクを再利用して、欠けている部分を取得します。完全な再構成出力は、コンパイラキャッシュに復元される前に検証されます。

転送チャンクキャッシュは `DerivedData` とは別個であり、そのチャンクはコンパイルキャッシュのクリーンアップやローカルキャッシュサービスの再起動後も残ります。これは使い捨て可能で、チャンクペイロードは最大 1 GiB に制限され、追加の一時ステージングファイルは最大 2 MiB です。排除されたまたは損傷したチャンクは、必要に応じて再度ダウンロードされます。コンパイルキャッシュ自体を保持することは、その内容を再構築するよりも依然として高速です。

クライアントは、サーバーが互換性のあるサポートを告知している場合にのみチャンク転送を使用します。古いクライアントでも完全な出力を読み取ることができ、古いかサポートされていないサーバーに接続されたクライアントは通常の転送を維持します。小さな出力は既存の全体出力パスのままです。

これは転送バイト数を削減しますが、コンパイラの無効化ではありません。ソースファイルの変更は依然としてコンパイルを必要とする場合があります。チャンキングは、結果の出力のパブリッシュまたは復元を支援します。節約量は出力と編集内容に依存し、一致するチャンクがないコールドマシンでは出力全体をダウンロードする必要があります。

### 継続的インテグレーション {#continuous-integration}

CI環境でキャッシングを有効にするには、ローカル環境と同じコマンドを実行する必要があります。`tuist setup cache`。

認証には、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>（サポートされているCIプロバイダーに推奨）または<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を`TUIST_TOKEN`環境変数経由で使用できます。

OIDC認証を使用したGitHub Actionsのワークフロー例：
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

詳細については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link>を参照してください。トークンベースの認証や、Xcode Cloud、CircleCI、Bitrise、Codemagicなどの他のCIプラットフォームの例も含まれています。

### CI上のコンパイルキャッシュストア {#compilation-cache-store-on-ci}

コンパイルキャッシュストアは、Xcodeがコンパイル出力を保持するローカルディレクトリです。`COMPILATION_CACHE_CAS_PATH`ビルド設定はその場所を設定し、デフォルトでは`DerivedData`内の`CompilationCache.noindex`になります。

#### ステートフルストア {#stateful-store}

ビルド間でストアを保持するには、`COMPILATION_CACHE_CAS_PATH`（および`tuist cache`用の`TUIST_COMPILATION_CACHE_CAS_PATH`）を1つの永続的なパスに向け、そのサイズを[ストアサイズ制限](#store-size-limit)で制限します。

## トラブルシューティング {#troubleshooting}

### ビルドがXcodeキャッシュプロキシの失敗を警告する {#cas-proxy-failed}

ビルドに以下のような警告が表示される場合、Xcodeは最初に失敗したコンパイルに応じて`CAS error:`または`CAS operation failed:`をプレフィックスとして付けます：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

この場合、コンパイルキャッシュは`tuist setup cache`がインストールするローカルキャッシュプロキシに到達できませんでした。ビルド自体は成功しますが、影響を受けたコンパイルはリモートキャッシュヒットを得られないため、空のキャッシュでのビルドと同様に実行されます。それらのアップロードはディスク上に保持され、プロキシが再びリクエストを処理できるようになった時点で送信されます。同じビルド中にプロキシが復帰すればそのタイミングで、そうでなければ同じマシンでの次のビルド中に送信されます。ジョブ後に破棄されるCIマシンでは、これらは失われます。警告はビルドごとに1回、XcodeのIssueナビゲーターおよび`xcodebuild`出力に表示されます。

プロキシが実行中かどうかを確認するには、警告に記載されているソケットでリッスンしているプロセスを探します：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

コマンドが何も出力しない場合は、`tuist setup cache`を実行してプロキシを再度起動してください。CIでは、各ジョブのあらゆる`xcodebuild`呼び出しの前に`tuist setup cache`を実行します。

### ビルドが非常に遅く、`CAS error: deadlineExceeded`警告を出力する {#cas-deadline-exceeded}

ビルドが予想よりもはるかに時間がかかり、Xcodeビルドログに以下のような警告がたくさん表示される場合：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

または：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

この場合、`COMPILATION_CACHE_REMOTE_SERVICE_PATH`は誰もリッスンしていないソケットを指しています。通常は、以前のバージョンのTuistが構成したプロジェクトごとのソケット（`~/.local/state/tuist/<org>_<project>.sock`）です。Tuistはそのソケットをもう提供していません。Xcodeは高速に失敗するのではなく、すべてのコンパイルキャッシュリクエストで接続を再試行するため、ビルドに1時間以上かかることがあり、Tuistはこの動作を変更できません。

修正方法：

- **生成されたプロジェクト**：`tuist generate`を再度実行します。
- **その他のプロジェクト**：[Xcodeビルド設定の構成](#configure-xcode-build-settings)で説明されているように、`COMPILATION_CACHE_*`ビルド設定を`tuist setup cache`が出力するものに置き換えます。

Xcodeキャッシュを使用していない場合は、代わりに`COMPILATION_CACHE_*`ビルド設定を削除し、`tuist teardown cache`を実行します。

### アップロードが無効でもローカルで`uploaded CAS output`が表示される {#uploaded-cas-output-with-upload-disabled}

`xcodeCache: .xcodeCache(upload: false)`（または非CIマシン上の`upload: Environment.isCI`）が設定されている場合、ビルドログに依然として`note: uploaded CAS output ...`が表示されることがあります。`xcodebuild`にはこれらの呼び出しをスキップする方法がないため、Tuistはそれらを受け取りますが、Tuistサーバーには何もパブリッシュしません。ダッシュボードのメトリクスはこの点を考慮しているため、誤ったアップロードトラフィックは報告されません。
