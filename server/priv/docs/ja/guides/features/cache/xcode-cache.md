---
{
  "title": "Xcode キャッシュ",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Tuist の Xcode キャッシュ連携により、ローカルおよび CI 環境での Xcode ビルドを高速化します。"
}
---
# Xcode キャッシュ {#xcode-cache}

Tuist は Xcode コンパイルキャッシュをサポートしており、ビルドシステムのキャッシング機能を活用してチーム間でコンパイル成果物を共有できます。

Xcode キャッシュは Xcode 26 で導入されました。Xcode ビルドキャッシュと呼ばれることもあります。これは入力に基づいてキー化されたコンパイル成果物を再利用し、Tuist のリモートキャッシュによってそれらの成果物をマシン間で共有可能にします。遅いビルドのどの部分をキャッシュが削減するのか、またプロジェクトでまず修正すべき点については、[Slow builds](https://tuist.dev/solutions/slow-builds) を参照してください。

> [!TIP]
> **モジュールキャッシュと組み合わせる**
>
> Xcode キャッシュと <.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> は異なる粒度で動作し、相互に補完します。モジュールキャッシュはビルド実行前にモジュール全体を事前ビルド済みの `.xcframework` に置き換えますが、Xcode キャッシュはビルド中にコンパイル出力を再利用します。

> [!TIP]
> **開発者マシンでは、クリーン時に `CompilationCache.noindex` を保持する**
>
> デフォルトでは、コンパイルキャッシュストアは `DerivedData` 内に存在するため、`DerivedData` を削除するとビルド成果物とともにキャッシュも失われます。開発者マシンでは、ビルド成果物のみを削除することをお勧めします。これにより、再ビルド時にディスク上のストアからリプレイされ、何もフェッチする必要がありません。

## セットアップ {#setup}

Tuist アカウントとプロジェクトをまだ作成していない場合は、以下を実行して作成できます。

```bash
tuist init
```

`Tuist.swift` ファイルがあり、それがあなたの `fullHandle` を参照している場合、以下を実行してプロジェクトのキャッシングを設定できます。

```bash
tuist setup cache
```

このコマンドは [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) を作成し、起動時にローカルキャッシュサービスを実行します。これは Swift の [build system](https://github.com/swiftlang/swift-build) がコンパイル成果物を共有するために使用します。最初は開発者マシンで実行し、各 CI ジョブのセットアップの一部として実行してください。

CI でキャッシュを設定するには、<.localized_link href="/guides/server/authentication#continuous-integration">authenticated</.localized_link> であることを確認してください。

### キャッシュコンポーネントの更新 {#updating-the-cache-components}

キャッシュプロキシは、最後にセットアップを実行した Tuist インストールに固定されたパスではなく、安定したランチャーを使用します。一度インストールされると、`tuist setup cache` およびキャッシュ有効な `tuist generate` は、利用可能なターゲットを新しい Tuist リリースに進めます。したがって、古い Tuist に固定されているプロジェクトでも、共有プロキシのダウングレードは発生しません。生成は既存のランチャーターゲットを更新するだけであり、サービスのインストール、認証、プラグインの置換、またはプロキシの再起動は行いません。カスタムプラグイン、プロキシ、ソケット、またはレジストリのオーバーライドがある場合、自動的な進捗はスキップされます。

実行中のプロキシは、キャッシュリクエストがない状態が少なくとも 30 秒続き、進行中のリクエストやバックグラウンド作業がなく、公開スプールが排出された後にのみ、新しいターゲットを採用します。その後終了し、launchd が選択された CLI を起動し、サービスの引数と認証情報環境を維持します。実際にターゲットを採用したプロキシのみが、バンドルからディスク上のプラグインをアトミックに更新します。古いプロキシがまだ排出中である間は、セットアップは新しいプラグインをインストールしません。インストールされたプラグインが見つからない場合、明示的なアイドル状態のセットアップは選択されたプロキシを再起動して更新を再試行します。レジストリとスプールを所有するプロキシは依然として 1 つだけです。利用できないターゲットまたは未排出のアップロードがある場合、アクティブなリクエストを中断するのではなく、切り替えを延期します。認証情報の更新は切り替えの前でも選択された CLI に従うため、古い CLI インストールを削除しても、排出待ちのアップロードが取り残されることはありません。

安定したランチャーより前に作成された既存のインストールには、一度の明示的な移行が必要です。ビルドが実行されていないときに以下を実行してください。

```bash
tuist setup cache
```

その移行後、Tuist を更新して通常の `tuist generate` を実行するだけで、プロキシとインストールされたプラグインを進めることができます。各 CLI リリースごとにセットアップを再実行する必要はありません。異なる Xcode（同じパスで更新された Xcode を含む）を選択するには、引き続き明示的なセットアップが必要です。構成が変更された場合、セットアップは共有サービスを置き換える可能性があるため、まずマシン上のすべてのビルドが完了するのを待ってください。プロキシは以前のプラグインプロトコルと現在のプロトコルの両方をサポートしているため、Xcode にすでに読み込まれている互換性のあるプラグインは、プロキシのアップグレード後も動作し続けます。最新のプラグインを読み込むために Xcode を完全に終了して再開しますが、互換性のある読み込み済みプラグインの場合は即時の再起動は必要ありません。リリースで生成されたビルド設定が変更された場合は、プロジェクトを再生成してください。

選択した Tuist インストールを利用可能な状態に保ってください。ランチャーはそれを起動、構成、および認証情報の更新に使用します。ランチャーが進んだ後、古いインストールは削除できます。選択された実行ファイルが削除されたか、実行不可能になった場合、`tuist setup cache` は利用可能なインストール（古いリリースを含む）を使用してターゲットを修復でき、最初にキャッシュを解体する必要はありません。安定した実行ファイルエイリアスはパッケージマネージャーのアップグレードを通じて保持されます。シンボリックリンクはインストール ID の比較時にのみ解決されます。起動時、プロキシは実際に起動されたバージョン（インプレース更新や意図的なロールバックを含む）を記録し、関連のない古いチェックアウトが利用可能なインストールを切り替えるのを防ぐために、使用された最高バージョンを保持します。

リリースバージョンのないソースビルド CLI および明示的な `TUIST_CAS_PLUGIN_PATH` または `TUIST_CAS_PROXY_PATH` セットアップは、自動バージョン選択ではなく明示的な起動構成を使用します。これらのコンポーネントを再ビルドした後、セットアップを再実行してください。セットアップはそれらの新鮮さを確認し、置き換えの準備ができてから管理対象ターゲットの進捗を無効にします。

`tuist teardown cache` はランチャーターゲットを削除する前にサービスを停止し、既存のプロジェクトのために安定したプラグインを保持します。サービスの停止に失敗した場合、そのランチャーは再起動および別のティアダウン試行のために利用可能なままです。成功したティアダウン後、生成はサービスを再作成できません。

### Xcode ビルド設定の構成 {#configure-xcode-build-settings}

既存の Xcode プロジェクトの場合、`tuist setup cache` によって出力されたビルド設定をプロジェクトのビルド設定または既存の `.xcconfig` ファイルにコピーしてください。このコマンドはアカウント用の構成を出力しますが、構成ファイルを生成したり Xcode プロジェクトを編集したりはしません。`OTHER_SWIFT_FLAGS` を拡張する際は `$(inherited)` を保持し、他のコンパイラオプションが保存されるようにしてください。

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

`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH`、および `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` は Xcode のビルド設定 UI で直接公開されていないため、**ユーザー定義ビルド設定** として追加する必要があることに注意してください。

> [!NOTE]
> **プラグインパス**
>
> `libtuist_cas_plugin.dylib` は `tuist` 実行ファイルの隣に配置され、Tuist に同梱されているコンパイルキャッシュプラグインです。`tuist setup cache` はこれを `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib` にコピーし、`COMPILATION_CACHE_PLUGIN_PATH` がそのコピーを指します。このパスはすべてのマシンで同じであり、Tuist を更新しても変更されないため、設定をプロジェクトと一緒にコミットできます。セットアップと新たに起動されたプロキシは、選択された Tuist バンドルからコピーを更新します。古いチェックアウトからセットアップを実行しても、新しいプラグインがダウングレードされることはありません。

> [!NOTE]
> **プロジェクトごとに1つのソケット**
>
> `tuist setup cache` はマシンごとに単一のキャッシュプロキシをインストールするため、すべてのプロジェクトが同じ `COMPILATION_CACHE_REMOTE_SERVICE_PATH` を使用します。プロジェクトを識別するのは `tuist-instance` プラグインオプションです。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` が C と Objective-C を共有する仕組み**
>
> この設定を「キャッシュサービスの場所」と読み取り、任意のものとして扱いがちです。しかし、C、Objective-C、プリコンパイル済みモジュール、およびプリコンパイル済みヘッダーを共有するかどうかを決定するスイッチでもあります。ビルドシステムは、リモートキャッシュサービスが構成されている場合にのみ、それらのキャッシングを実行します。これを省略しても Swift コンパイルは共有されますが、以前にプロジェクトをビルドしていないマシンでは、すべての C/Objective-C ファイルとすべてのモジュールが再コンパイルされます。

> [!NOTE]
> **並列キャッシュルックアップ**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` は、ビルドの実行レーンで一度にいくつかずつ行うのではなく、残りのビルドと同時に、ビルドシステムが各コンパイルに対して行うリモートキャッシュルックアップを実行します。遠隔のキャッシュから多くのコンパイルをミスしたり復元したりするビルドは、より早く完了します。

以下のフラグを追加することで、`xcodebuild` を実行する際にもこれらの設定を指定できます。例：

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
> Xcode 27 以降では、`tuist setup cache` は `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、および `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` も出力します。これらは、プロジェクトと `DerivedData` の場所に関係なくコンパイルキャッシュキーを独立させます。ユーザー定義ビルド設定として追加してください。有効にするとすべてのキャッシュキーが変更されるため、次のビルドでキャッシュが再び埋められます。`enableCaching` がオンの場合、`tuist generate` がこれらを自動的に設定します。
>
> コンパイラはマッピングされたパスをコードカバレッジデータにも書き込みますが、Xcode はそれらを解決できないため、カバレッジレポートにはプレフィックスマッピングを使用してコンパイルされたすべてのソースが含まれなくなります。出力された設定と `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` の設定は、コードカバレッジを収集するビルドでプレフィックスマッピングを無効にします。`tuist generate` も同様に行います。これらのビルドでもコンパイルキャッシュは使用されますが、そのキャッシュキーはプロジェクトと `DerivedData` のパスに依存します。
>
> コマンドラインでこれらの設定を `xcodebuild` に渡す場合は、上記の `OTHER_SWIFT_FLAGS` と同様に、`$(...)` を含む値を一重引用符で囲んでください。そうしないと、シェルがそれらを空の文字列に展開し、プレフィックスマッピングが無効になります。
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
> プロジェクトが Tuist によって生成されている場合、手動で設定を行う必要はありません。
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

`TUIST_COVERAGE_PREFIX_MAPPING` 環境変数（`1` または `0`）は `prefixMapping` より優先されます。このオプションは Xcode 27 以降で適用され、`enableCaching` が必要です。カバレッジ `tuist test` のアップロードはこれをサポートしています。Tuist は `llvm-cov` を使用して実行を測定し、マッピングされたパスでソースを読み取り、それをリポジトリのファイルに紐付けます。Xcode 独自のカバレッジレポートと `xccov` は依然としてそれらのソースを省略することがあり、`llvm-cov` エクスポートが失敗したために結果バンドルの `xccov` レポートにフォールバックするアップロードも同様です。マッピングされた `#filePath` 値は、ソースファイルに対する相対パスでフィクスチャを探すテストにも影響を与える可能性があります。代わりに明示的なランタイムチェックアウトパスを通じてフィクスチャを解決してください。自分でカバレッジを処理する場合、各インストゥルメント化されたバイナリを、そのターゲットの `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` とペアにしてください。これは仮想プレフィックスをローカルディレクトリにマッピングし直します。プロジェクトごとのマッピングが有効な場合、あるターゲットのマップをすべてのバイナリで再利用しないでください。

カバレッジプレフィックス設定は、カバレッジアーティファクトに書き込まれるパスを制御するため、バイナリキャッシュと選択的テストのハッシュに影響します。このオプションを変更するか、`TUIST_COVERAGE_PREFIX_MAPPING` を異なる値に設定すると、通常のビルドであってもこれらのハッシュは無効になります。バイナリキャッシュと選択的テストの結果を共有する必要がある場合は、開発者と CI ジョブ間で値を一貫させてください。

### 生成されたプロジェクトのデバッグ {#debugging-generated-projects}

復元されたネイティブモジュールには、リンクされたデバッグ情報だけでなく、コンパイルキャッシュへのアクセスも必要です。Tuist は Debug および Release モジュールを dSYM とスライスごとのソース識別メタデータでウォームアップし、ターゲットを置き換える前に、メタデータをコンシューマーが宣言したソースに対して検証します。メタデータが欠落しているか互換性がない場合、そのターゲットのソースが保持されます。スクリプトで生成された `.generated(...)` ソースには、検証可能なコンテンツチェックサムではなく宣言フィンガープリントがあるため、それらのターゲットはソースビルドのままとなり、ネイティブモジュールキャッシュには公開されません。実際のコンテンツチェックサムを持つ生成されたリソースアクセサは対象となります。サポートされていないデバッグ情報は、関連のない製品のブロックなしに影響を受けるターゲットの公開をスキップしますが、ソースの変更とキャンセルは依然としてウォームアップを失敗させます。キャッシュ形式が変更されるため、古いバージョンでウォームアップされたアーティファクトは再ウォームアップが必要です。

検証済みの置き換えのために、Tuist はコンシューマー所有の dSYM UUID plist でソースの再配置を準備し、静的キャッシュコード用のデバッグ専用コンパニオンをリンクします。キャッシュされたバイナリを書き換えたり、LLDB の永続的なグローバルソースマップにプロデューサーソースパスをインストールしたりすることはしません。明示的なデバッガ初期化子とモジュールローダー設定が優先されます。CI 上（`CI` または `JENKINS_URL` が設定されている場合）、これを行うスキームのプレアクションは変更なしで終了します。そこではテストにデバッガがアタッチされないためです。デバッグシンボルとソースの再配置は、ソース相対のランタイムファイルアクセスやネイティブな Xcode カバレッジレポートを修復しません。カバレッジバリアントの選択と LLVM エクスポートは別個の機能です。

`enableCaching: true` を有効にすると、Tuist は Run アクションと Test アクション用に LLDB ソースマップを構成します。アクションにカスタム LLDB 初期化子が設定されている場合、Tuist はまず解決済みのソースマップを書き込み、その後カスタム初期化子を読み込んでマップを拡張または上書きできるようにします。それ以外の場合、ソースマップを置き換える前に、ファイルが存在すれば `~/.lldbinit-Xcode` を読み込み、存在しなければ `~/.lldbinit` にフォールバックします。ホームファイルは 1 つだけ読み込まれ、二重読み込みを防ぎながらユーザーごとのデバッガ設定を復元します。この置き換えにより、以前の実行からの古いマッピングが削除され、ホームファイルのソースマップよりも優先されます。維持すべきソースマップのエントリは、アクションのカスタム初期化子に記述してください。その他のホーム設定は保持されます。Tuist のキャッシュ固有のモジュール検索パス、ローダー設定、および Clang フラグはその後適用され、これらの設定に関するユーザー値よりも優先されます。ホームファイルのエラーは表示されますが、後続のコマンドの読み込みを停止することはなく、コマンドはエコーされません。この初期化子の保持は、モジュールキャッシュから復元されたバイナリのデバッグを Tuist が構成する場合にも適用され、`enableCaching` が無効な場合や以前の Xcode バージョンでも同様です。

Xcode 27 以降では、生成されたプロジェクトは、プロジェクトで明示的に設定されていない限り、Xcode のプロジェクト別プレフィックスマッピング（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` および `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`）をオフにします。`/^src` などのプレフィックスはプロジェクトごとに異なるディレクトリを指し、LLDB はデバッグ対象のターゲットのプロジェクトに対してのみこれらを解決します。代わりに、ワークスペース全体のプレフィックスの下にソースが記録されます：`/^root` は Tuist ルートディレクトリ用、`/^spm` は Swift パッケージのスクラッチディレクトリ用、`/^intermediates` および `/^products` はビルド出力用です。これらはすべてのプロジェクトで同じディレクトリを指すため、ワークスペース内の任意のプロジェクトのソースでブレークポイントが解決されます。

Tuist ルート外のパスはマップされません。ルート外のプロジェクトのキャッシュキーはチェックアウト場所に依存するため、他のチェックアウトやマシンではそのキャッシュが見つかりません。チェックアウト場所に依存しないキーを維持するには、そのプロジェクトのマニフェストでプロジェクト別マッピングを有効にしてください：

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

これらの設定をその `Project` に渡してください。別のプロジェクトのターゲットをデバッグする場合、LLDB はそのプロジェクトのソースを見つけられなくなります。マニフェストのプロジェクトベース設定はプロジェクトレベルの xcconfig 値よりも優先されるため、マニフェスト自体で設定してください。

これらの設定を変更すると、コンパイルキャッシュキー、バイナリキャッシュハッシュ、および選択的テストハッシュが変更されるため、それらのキャッシュを再度ウォームアップする必要があります。チーム全体で一貫した選択を維持してください。

### キャッシュアップロードポリシー {#cache-upload-policy}

デフォルトでは、キャッシュサービスはリモートキャッシュへのアーティファクトのダウンロードとアップロードの両方を行います。`Tuist.swift` ファイルの `xcodeCache` オプションを使用して読み取り専用モードを有効にし、アーティファクトはダウンロードされるもののアップロードされないように制御できます：

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

一般的なパターンは、ビルドが再現可能な CI からのみアーティファクトをプッシュし、ローカル環境は読み取り専用に保つことです。これは `Environment.isCI` を使用して実現できます。これは、ほとんどの CI プロバイダーによって設定される `CI` 環境変数をチェックします：

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

この設定により、ローカルビルドはアップロードなしでキャッシュされたアーティファクトの恩恵を受け、CI ビルドはチームの他のメンバーのためにキャッシュを入力します。

アップロードポリシーは、`tuist setup cache` を実行するマシン上でプロジェクトごとに記録されます。変更するには、`upload` を更新して `tuist setup cache` を再度実行し、Tuist がプロジェクトを生成する場合は `tuist generate` も実行してください。その後、そのマシン上のキャッシュを再起動することなく、新しいポリシーに従ってアップロードが行われます。同じマシンで同時に実行される同じプロジェクトのジョブはそのポリシーを共有するため、最新の `tuist setup cache` がすべてに対して決定します。

### ストアサイズ制限 {#store-size-limit}

コンパイルキャッシュストアはビルドごとに増加します。プロジェクトのストアを制限するには、`Tuist.swift` ファイルで `storeSizeLimit` を設定してください：

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

Tuist は、キャッシュプロキシが開始されるとき（ビルドが使用する前）、およびビルドが実行されていない間は 10 分ごとに、プロジェクトの各ストアをチェックします。`tuist setup cache` はプロキシが実行されていない場合にプロキシを開始するため、ビルドの前に `tuist setup cache` を実行し、後に `tuist teardown cache` を実行する CI ジョブは、長寿命ランナーのストアを各ジョブの開始時に制限します。新しいビルドが制限の約半分を書き込むと、ストアの最も古いキャッシュ出力が削除されるため、ストアは制限付近で安定します。ビルド実行中はストアが制限を超えることがあり、制限を設定した時点で既に大きかったストアも、新しいビルドがその量を書き込むと縮小します。複数のプロジェクトが同じストア（デフォルトの場所など）を使用する場合、最も小さい制限が適用されます。この制限は `tuist setup cache` を実行するすべてのマシンに適用されるため、制限を変更した後は再度実行してください。すでに実行中のキャッシュプロキシは実行を継続し、次のチェックで新しい制限を適用します。

### モジュールキャッシュハッシュ {#module-cache-hashes}

コンパイルキャッシュの設定は <.localized_link href="/guides/features/projects/hashing">モジュールキャッシュハッシュ</.localized_link> の一部ではありません。Tuist は、すべての `COMPILATION_CACHE_*` ビルド設定と、その値を持つすべての `-cas-plugin-option` フラグをハッシュから除外します。`enableCaching` のオン/オフ切り替えやアップロードポリシーの変更は、ターゲットのハッシュを保持するため、すでにウォームアップ済みの <.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> バイナリは有効なままです。Xcode キャッシュの有無にかかわらず、同じモジュールキャッシュに対してビルドを比較できます。

> [!NOTE]
> **プレフィックスマッピング設定はハッシュ化されます**
>
> Xcode 27 以降では、`enableCaching: true` は `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`、および `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 設定も設定します。これらの設定はモジュールキャッシュハッシュの一部であるため、Xcode 27 以降では `enableCaching` のオン/オフ切り替えによりターゲットのハッシュが変更されます。

### 大きな出力の一部の再利用 {#reusing-parts-of-large-outputs}

サーバーがサポートしている場合、Xcode キャッシュは大きな出力をチャンク単位で転送し、以前のバージョンから変更されたチャンクのみを送信または取得します。チャンクは `DerivedData` とは別に小さなローカルキャッシュに保持されるため、コンパイルキャッシュのクリーンアップ後も残ります。小さな出力、古いサーバー、および古いクライアントは通常の全出力転送を使用します。

これにより、再コンパイルされる量ではなく、ダウンロードおよびアップロードされる量が削減されます。一致するチャンクがないコールドマシンは、依然として出力全体をダウンロードします。

### 継続的インテグレーション {#continuous-integration}

CI 環境でキャッシングを有効にするには、ローカル環境と同じコマンド `tuist setup cache` を実行する必要があります。

認証には、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link>（サポートされている CI プロバイダーに推奨）または `TUIST_TOKEN` 環境変数を介した <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> のいずれかを使用できます。

OIDC 認証を使用した GitHub Actions のワークフロー例：
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

トークンベースの認証や、Xcode Cloud、CircleCI、Bitrise、Codemagic などの他の CI プラットフォームを含むその他の例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link> を参照してください。

### CI 上のコンパイルキャッシュストア {#compilation-cache-store-on-ci}

コンパイルキャッシュストアは、Xcode がコンパイル出力を保持するローカルディレクトリです。`COMPILATION_CACHE_CAS_PATH` ビルド設定はその場所を設定し、デフォルトでは `DerivedData` 内の `CompilationCache.noindex` になります。

#### ステートフルなストア {#stateful-store}

ビルド間でストアを維持するには、`COMPILATION_CACHE_CAS_PATH`（および `tuist cache` 用の `TUIST_COMPILATION_CACHE_CAS_PATH`）を永続的なパスに向け、[ストアサイズ制限](#store-size-limit) でそのサイズを制限します。

## トラブルシューティング {#troubleshooting}

### ビルドで Xcode キャッシュプロキシが失敗したという警告が表示される {#cas-proxy-failed}

ビルドで以下のような警告が表示された場合、Xcode は最初に失敗したコンパイルに応じて `CAS error:` または `CAS operation failed:` のプレフィックスを付けます：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

これは、コンパイルキャッシュが `tuist setup cache` がインストールするローカルキャッシュプロキシに到達できなかったことを意味します。ビルド自体は成功しますが、影響を受けたコンパイルはリモートキャッシュヒットを得られないため、空のキャッシュでのビルドと同様に実行されます。それらのアップロードはディスク上に保持され、プロキシが再びリクエストを処理できるようになった時点で送信されます。同じビルド中にプロキシが復旧すればその時点で、そうでなければ同じマシンでの次のビルド時に送信されます。ジョブ後に廃棄される CI マシンでは、これらは失われます。警告はビルドごとに 1 回、Xcode の Issue ナビゲーターと `xcodebuild` 出力に表示されます。

プロキシが実行中かどうかを確認するには、警告に記載されているソケットでリッスンしているプロセスを探します：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

コマンドが何も出力しない場合は、`tuist setup cache` を実行してプロキシを再度起動してください。CI では、すべてのジョブで `xcodebuild` 呼び出しの前に `tuist setup cache` を実行してください。

### ビルドが極端に遅く、`CAS error: deadlineExceeded` 警告が出力される {#cas-deadline-exceeded}

ビルドが予想よりもはるかに時間がかかり、Xcode ビルドログに以下のような警告が多数表示される場合：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

または：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

この場合、`COMPILATION_CACHE_REMOTE_SERVICE_PATH` は誰もリッスンしていないソケットを指しています。通常は、以前のバージョンの Tuist が構成していたプロジェクトごとのソケット（`~/.local/state/tuist/<org>_<project>.sock`）です。Tuist はそのソケットをもう提供していません。Xcode は高速に失敗するのではなく、すべてのコンパイルキャッシュリクエストで接続を再試行するため、ビルドに 1 時間以上かかることがありますが、Tuist はその動作を変更できません。

修正方法：

- **生成されたプロジェクト**：`tuist generate` を再度実行します。
- **その他のプロジェクト**：[Xcode ビルド設定の構成](#configure-xcode-build-settings) で説明されているように、`COMPILATION_CACHE_*` ビルド設定を `tuist setup cache` が出力するものに置き換えます。

Xcode キャッシュを使用していない場合は、代わりに `COMPILATION_CACHE_*` ビルド設定を削除し、`tuist teardown cache` を実行してください。

### アップロードが無効でもローカルで `uploaded CAS output` が表示される {#uploaded-cas-output-with-upload-disabled}

`xcodeCache: .xcodeCache(upload: false)`（または非 CI マシンでの `upload: Environment.isCI`）が設定されている場合、ビルドログに `note: uploaded CAS output ...` が表示されることがあります。`xcodebuild` にはこれらの呼び出しをスキップする方法がないため、Tuist はそれらを受け取りますが、Tuist サーバーには何も公開しません。ダッシュボードのメトリクスはこの点を考慮しているため、誤ったアップロードトラフィックは報告されません。

## 関連情報 {#related}

エンジニアリングチームやコーディングエージェントがビルド成果物をどのように再利用しているかを確認するには、[Tuist の共有キャッシュ](https://tuist.dev/cache) をご覧ください。
