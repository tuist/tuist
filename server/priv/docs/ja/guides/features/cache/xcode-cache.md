---
{
  "title": "Xcode キャッシュ",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Tuist の Xcode キャッシュ統合により、ローカルおよび CI 環境での Xcode ビルドを高速化します。"
}
---
# Xcodeキャッシュ {#xcode-cache}

TuistはXcodeコンパイルキャッシュをサポートしており、ビルドシステムのキャッシング機能を活用してチームがコンパイル成果物を共有できるようにします。

XcodeキャッシュはXcode 26で導入されました。Xcodeビルドキャッシュと呼ばれることもあります。このキャッシュは入力に基づいてキー付けされたコンパイル成果物を再利用し、Tuistのリモートキャッシュにより、これらの成果物をマシン間で共有できます。DerivedDataやClangモジュールキャッシュとの関係については、<.localized_link href="/references/concepts/build-cache#xcode">Xcodeキャッシュとは？</.localized_link>をご覧ください。遅いビルドのどの部分をキャッシュが削減するのか、またプロジェクトで最初に修正すべき点については、[遅いビルド](https://tuist.dev/solutions/slow-builds)をご覧ください。

> [!TIP]
> **モジュールキャッシュと組み合わせる**
>
> Xcodeキャッシュと<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>は異なる粒度で動作し、互いを補完します。モジュールキャッシュはビルド実行前にモジュール全体を事前ビルド済みの`.xcframework`に置き換えますが、Xcodeキャッシュはビルド中にコンパイル出力を再利用します。

> [!TIP]
> **開発者マシンでは、クリーン時に`CompilationCache.noindex`を保持する**
>
> デフォルトでは、コンパイルキャッシュストアは`DerivedData`内に存在するため、`DerivedData`を削除するとビルド成果物と一緒にキャッシュも失われます。開発者マシンでは、ビルド成果物のみを削除することをお勧めします。これにより、再ビルド時にディスク上のストアからリプレイされ、何もフェッチする必要がありません。

## セットアップ {#setup}

Tuistアカウントとプロジェクトをまだ持っていない場合は、以下を実行して作成できます。

```bash
tuist init
```

`Tuist.swift`ファイルで`fullHandle`を参照できるようになったら、以下を実行してプロジェクトのキャッシングを設定できます。

```bash
tuist setup cache
```

このコマンドは、Swift[ビルドシステム](https://github.com/swiftlang/swift-build)がコンパイル成果物を共有するために使用するローカルキャッシュサービスを起動時に実行する[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)を作成します。最初は開発者マシンで実行し、各CIジョブのセットアップの一部として実行してください。

CIでキャッシュを設定するには、<.localized_link href="/guides/server/authentication#continuous-integration">認証済み</.localized_link>であることを確認してください。

### キャッシュコンポーネントの更新 {#updating-the-cache-components}

キャッシュプロキシは、最後にセットアップを実行したTuistインストールに固定されたパスではなく、安定したランチャーを使用します。インストール後、`tuist setup cache`およびキャッシュ有効化された`tuist generate`は、利用可能なターゲットを新しいTuistリリースに進めます。したがって、古いTuistに固定されたプロジェクトでも、共有プロキシのダウングレードは発生しません。生成は既存のランチャーターゲットのみを更新し、サービスのインストール、認証、プラグインの置換、またはプロキシの再起動は行いません。カスタムプラグイン、プロキシ、ソケット、またはレジストリのオーバーライドがある場合、自動的な進捗はスキップされます。

実行中のプロキシは、キャッシュリクエストが少なくとも30秒間なく、リクエストやバックグラウンド作業が進行中でなく、公開スプールが排出された後にのみ、新しいターゲットを採用します。その後終了し、launchdが選択されたCLIを起動し、サービスの引数と認証情報環境を維持します。実際にターゲットを採用したプロキシのみが、バンドルからディスク上のプラグインをアトミックに更新します。セットアップは、古いプロキシがまだ排出中である間は、新しいプラグインをインストールしません。インストールされたプラグインが見つからない場合、明示的なアイドル状態のセットアップが選択されたプロキシを再起動して更新を再試行します。レジストリとスプールを所有するプロキシは依然として1つだけです。利用できないターゲットまたは未排出のアップロードがある場合、アクティブなリクエストを中断するのではなく、切り替えを延期します。認証情報の更新は切り替えの前でも選択されたCLIに従うため、古いCLIインストールを削除しても、排出待ちのアップロードが行き場を失うことはありません。

安定したランチャーの前に作成された既存のインストールには、明示的な移行が1回必要です。ビルドが実行されていないときに以下を実行してください。

```bash
tuist setup cache
```

その移行後、Tuistを更新して通常の`tuist generate`を実行するだけで、プロキシとインストールされたプラグインを進めることができます。各CLIリリースごとにセットアップを再実行する必要はありません。異なるXcodeを選択するには、明示的なセットアップが必要です。これには、同じパスで更新されたXcodeも含まれます。設定が変更された場合、セットアップは共有サービスを置き換えることができるため、まずマシン上のすべてのビルドが完了するのを待ってください。プロキシは以前のプラグインプロトコルと現在のプロトコルの両方をサポートしているため、Xcodeにすでに読み込まれている互換性のあるプラグインは、プロキシのアップグレード後も動作し続けます。最新のプラグインを読み込むには、Xcodeを完全に終了して再開してください。ただし、互換性のある読み込み済みプラグインの場合、即時の再起動は必要ありません。リリースによって生成されたビルド設定が変更された場合は、プロジェクトを再生成してください。

選択したTuistインストールを利用可能な状態に保ってください。ランチャーは起動、構成、および認証情報の更新にこれを使用します。ランチャーが進んだ後、古いインストールは削除できます。選択された実行可能ファイルが削除されたか、実行可能ではなくなった場合、`tuist setup cache`は、利用可能なインストール（古いリリースであっても）を使用してターゲットを修復でき、キャッシュを事前に解体する必要はありません。安定した実行可能ファイルエイリアスはパッケージマネージャーのアップグレードを通じて保持され、シンボリックリンクはインストールIDを比較するときのみ解決されます。起動時、プロキシは実際に起動されたバージョン（インプレース更新や意図的なロールバックを含む）を記録し、関連のない古いチェックアウトが利用可能なインストールを切り替えるのを防ぐために、使用された最高バージョンを保持します。

リリースバージョンを持たないソースビルドされたCLIおよび明示的な`TUIST_CAS_PLUGIN_PATH`または`TUIST_CAS_PROXY_PATH`セットアップは、自動バージョン選択ではなく明示的な起動構成を使用します。それらのコンポーネントを再ビルドした後、セットアップを再実行してください。セットアップはそれらの新鮮さを確認し、置き換えが準備できてから管理対象ターゲットの進捗を無効にします。

`tuist teardown cache`はランチャーターゲットを削除する前にサービスを停止し、既存のプロジェクトのために安定したプラグインを保持します。サービスの停止に失敗した場合、そのランチャーは再起動および別のティアダウン試行のために利用可能なままになります。成功したティアダウン後、生成はサービスを再作成できません。

### Xcodeビルド設定の構成 {#configure-xcode-build-settings}

既存のXcodeプロジェクトの場合、`tuist setup cache`によって出力されるビルド設定をプロジェクトのビルド設定または既存の`.xcconfig`ファイルにコピーしてください。このコマンドはアカウントの構成を出力しますが、構成ファイルを生成したりXcodeプロジェクトを編集したりすることはしません。`OTHER_SWIFT_FLAGS`を拡張する際は`$(inherited)`を保持し、他のコンパイラオプションが保存されるようにしてください。

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

`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH`、および`COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`はXcodeのビルド設定UIで直接公開されていないため、**ユーザー定義ビルド設定**として追加する必要があることに注意してください。

> [!NOTE]
> **プラグインパス**
>
> `libtuist_cas_plugin.dylib`はTuistに同梱されているコンパイルキャッシュプラグインで、`tuist`実行ファイルの隣にあります。`tuist setup cache`はこのファイルを`$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`にコピーし、`COMPILATION_CACHE_PLUGIN_PATH`はそのコピーを指します。このパスはすべてのマシンで同じであり、Tuistを更新しても変更されないため、プロジェクトと一緒に設定をコミットできます。セットアップと newly launched proxy は、選択されたTuistバンドルからコピーを更新します。古いチェックアウトからセットアップを実行しても、新しいプラグインがダウングレードされることはありません。

> [!NOTE]
> **プロジェクトごとに1つのソケット**
>
> `tuist setup cache`はマシンごとに単一のキャッシュプロキシをインストールするため、すべてのプロジェクトが同じ`COMPILATION_CACHE_REMOTE_SERVICE_PATH`を使用します。プロジェクトを識別するのは`tuist-instance`プラグインオプションです。
>
> Xcodeは`OTHER_SWIFT_FLAGS`をSwiftコンパイラにのみ渡し、ビルドシステム自体が行うキャッシュルックアップには渡しません。これらのルックアップは、同じビルド内のSwiftコンパイラのオプションからプロジェクトを学習します。`tuist build`、`tuist test`、および`tuist xcodebuild`もプロジェクトを直接渡します。プレーンな`xcodebuild`やXcodeアプリなど、別の方法でビルドされるSwiftコードを含まないプロジェクトでは、ソケットパスの後にプロジェクトを追加できます：`COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock?tuist-instance=your-org/your-project`。そうしないと、CIマシンがジョブ間でリセットされるなど、キャッシュプロキシがまだプロジェクトを認識していないマシンでの最初のビルドにおいて、すでにキャッシュされている一部のファイルが再コンパイルされる可能性があります。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH`がC言語とObjective-Cを共有する仕組み**
>
> この設定を「キャッシュサービスの場所」と解釈し、任意扱いするのは簡単です。しかし、これはC言語、Objective-C、事前コンパイル済みモジュール、および事前コンパイル済みヘッダーを共有するかどうかを決定するスイッチでもあります。リモートキャッシュサービスが構成されている場合のみ、ビルドシステムはそれらのキャッシングを実行します。これを省略すると、Swiftコンパイルは引き続き共有されますが、以前にプロジェクトをビルドしたことのないマシンでは、すべてのC/Objective-Cファイルとすべてのモジュールが再コンパイルされます。

> [!NOTE]
> **並行キャッシュルックアップ**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`は、ビルドの実行レーンで一度に少数ずつ処理するのではなく、残りのビルドと同時に、ビルドシステムが各コンパイルに対して行うリモートキャッシュルックアップを実行します。リモートキャッシュから多くのコンパイルをミスしたり復元したりするビルドは、より早く完了します。

以下のフラグを追加することで、`xcodebuild`を実行する際にもこれらの設定を指定できます。例：

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
> **Xcode 27以降でのプレフィックスマッピング**
>
> Xcode 27以降では、`tuist setup cache`は`SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、および`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`も出力します。これらは、プロジェクトと`DerivedData`の場所に関係なくコンパイルキャッシュキーを独立させます。ユーザー定義ビルド設定として追加してください。有効にするとすべてのキャッシュキーが変更されるため、次のビルドでキャッシュが再び作成されます。`enableCaching`がオンの場合、`tuist generate`がこれらを自動的に設定します。
>
> コンパイラはマッピングされたパスをコードカバレッジデータにも書き込みますが、Xcodeはそれらを解決できないため、カバレッジレポートにはプレフィックスマッピングを使用してコンパイルされたすべてのソースが含まれなくなります。出力された設定と`TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`の設定により、コードカバレッジを収集するビルドではプレフィックスマッピングが無効になります。`tuist generate`も同様です。これらのビルドでもコンパイルキャッシュは使用されますが、そのキャッシュキーはプロジェクトと`DerivedData`のパスに依存します。
>
> コマンドラインでこれらの設定を`xcodebuild`に渡す場合は、上記の`OTHER_SWIFT_FLAGS`と同様に、`$(...)`を含む値をシングルクォートで囲んでください。そうしないと、シェルがそれらを空文字列に展開し、プレフィックスマッピングが無効になります：
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
> プロジェクトがTuistによって生成されている場合、設定を手動で行う必要はありません。
>
> その場合、必要なのは`Tuist.swift`ファイルに`enableCaching: true`を追加することだけです：
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

デフォルトでは、生成されたプロジェクトはXcodeのカバレッジレポートと`xccov`が機能するように、カバレッジビルド用のプレフィックスマッピングを無効にします。チェックアウト間でカバレッジコンパレーションを共有可能にするために、これを有効にすることができます：

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

`TUIST_COVERAGE_PREFIX_MAPPING`環境変数（`1`または`0`）は`prefixMapping`よりも優先されます。このオプションはXcode 27以降で適用され、`enableCaching`が必要です。カバレッジ`tuist test`アップロードはこれをサポートしています。Tuistは`llvm-cov`を使用して実行を測定し、マッピングされたパスでソースを読み取り、それをリポジトリのファイルに関連付けます。Xcode独自のカバレッジレポートと`xccov`は依然としてそれらのソースを除外することがあり、`llvm-cov`エクスポートが失敗したために結果バンドルの`xccov`レポートにフォールバックするアップロードでも同様です。マッピングされた`#filePath`値は、ソースファイルに対する相対パスでフィクスチャを探すテストにも影響を与える可能性があります。代わりに明示的なランタイムチェックアウトパスを通じてフィクスチャを解決してください。カバレッジを自分で処理する場合は、各計測済みバイナリをそのターゲットの`$(TARGET_TEMP_DIR)/compilation-prefix-map.json`とペアにしてください。これは仮想プレフィックスをローカルディレクトリにマッピングし直します。プロジェクトごとのマッピングが有効な場合、あるターゲットのマップをすべてのバイナリで再利用しないでください。

カバレッジプレフィックス設定は、カバレッジアーティファクトに書き込まれるパスを制御するため、バイナリキャッシュとセレクティブテストのハッシュに影響します。このオプションを変更するか、`TUIST_COVERAGE_PREFIX_MAPPING`を異なる値に設定すると、通常のビルドでもこれらのハッシュが無効になります。開発者とCIジョブ間でバイナリキャッシュとセレクティブテストの結果を共有する必要がある場合は、値を一貫させてください。

### 生成されたプロジェクトのデバッグ {#debugging-generated-projects}

復元されたネイティブモジュールには、リンクされたデバッグ情報だけでなく、コンパイルキャッシュへのアクセスも必要です。TuistはDebugおよびReleaseモジュールをdSYMとスライスごとのソースIDメタデータでウォームアップし、ターゲットを置き換える前に消費者の宣言されたソースに対してメタデータを検証します。メタデータが欠落しているか互換性がない場合、そのターゲットのソースは保持されます。スクリプト生成された`.generated(...)`ソースには、検証可能なコンテンツチェックサムではなく宣言フィンガープリントがあるため、それらのターゲットはソースビルドのままとなり、ネイティブモジュールキャッシュには公開されません。実際のコンテンツチェックサムを持つ生成されたリソースアクセサは対象となります。サポートされていないデバッグ情報は、関連のない製品をブロックすることなく、影響を受けるターゲットの公開をスキップしますが、ソースの変更とキャンセルは依然としてウォームアップを失敗させます。キャッシュ形式が変更されるため、古いバージョンでウォームアップされたアーティファクトは再ウォームアップが必要です。

検証済みの置き換えのために、Tuistは消費者所有のdSYM UUID plistにソースの再配置情報を準備し、静的なキャッシュコード用のデバッグ専用コンパニオンをリンクします。キャッシュされたバイナリを書き換えたり、LLDBの永続的なグローバルソースマップにプロデューサーのソースパスをインストールしたりすることはありません。明示的なデバッガ初期化子とモジュールローダー設定が優先されます。CI環境（`CI`または`JENKINS_URL`が設定されている場合）では、この処理を行うスキームのプレアクションは変更を加えずに終了します。これは、テストにデバッガがアタッチされないためです。デバッグシンボルとソースの再配置は、ソース相対のランタイムファイルアクセスやネイティブなXcodeカバレッジレポートを修復しません。カバレッジバリアントの選択とLLVMエクスポートは別個の機能として残ります。

`enableCaching: true`を使用すると、TuistはRunおよびTestアクション用にLLDBソースマップを設定します。アクションにカスタムLLDB初期化子がある場合、Tuistはまず解決されたソースマップを書き込み、その後カスタム初期化子をソースとして読み込み、マップを拡張または上書きできるようにします。それ以外の場合、ソースマップを置き換える前に、ファイルが存在すれば`~/.lldbinit-Xcode`を読み込み、存在しなければ`~/.lldbinit`にフォールバックします。ホームファイルは1つだけ読み込まれ、二重読み込みを防ぎながらユーザーごとのデバッガ設定を復元します。置き換えにより以前のランからの古いマッピングが削除され、ホームファイルのソースマップよりも優先されます。存続させるべきソースマップのエントリは、アクションのカスタム初期化子に記述してください。他のホーム設定は保持されます。Tuist固有のキャッシュ用モジュール検索パス、ローダー設定、およびClangフラグはその後適用され、それらの設定に関するユーザー値よりも優先されます。ホームファイルのエラーは表示され続け、後続のコマンドの読み込みを停止せず、コマンドはエコーされません。この初期化子の保持は、モジュールキャッシュから復元されたバイナリのデバッグをTuistが設定する場合にも適用され、`enableCaching`がない場合や古いXcodeバージョンでも同様です。

Xcode 27以降では、生成されたプロジェクトはプロジェクトが明示的に設定しない限り、Xcodeのプロジェクトごとのプレフィックスマッピング（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`および`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`）を無効にします。`/^src`などのプレフィックスはプロジェクトごとに異なるディレクトリを指し、LLDBはデバッグ対象のターゲットのプロジェクトに対してのみそれらを解決します。代わりに、ワークスペース全体のプレフィックスの下にソースが記録されます。Tuistルートディレクトリには`/^root`、Swiftパッケージのスクラッチディレクトリには`/^spm`、ビルド出力には`/^intermediates`および`/^products`が使用されます。これらはすべてのプロジェクトで同じディレクトリを指すため、ワークスペース内の任意のプロジェクトのソースでブレークポイントが解決されます。

Tuistルート外のパスはマッピングされません。ルート外のプロジェクトのキャッシュキーはチェックアウト場所に依存するため、他のチェックアウトやマシンではそのキャッシュが見つかりません。チェックアウト場所に依存しないキーにするには、そのプロジェクトのマニフェストでプロジェクトごとのマッピングを有効にします。

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

これらの設定をその`Project`に渡してください。別のプロジェクトのターゲットをデバッグする場合、LLDBはそのプロジェクトのソースを見つけられなくなります。マニフェストのプロジェクトベース設定はプロジェクトレベルのxcconfig値よりも優先されるため、マニフェスト自体で設定してください。

これらの設定を変更すると、コンパイルキャッシュキー、バイナリキャッシュハッシュ、およびセレクティブテストハッシュが変化するため、それらのキャッシュを再度ウォームアップする必要があります。チーム全体で一貫した選択を維持してください。

### キャッシュアップロードポリシー {#cache-upload-policy}

デフォルトでは、キャッシュサービスはリモートキャッシュへのアーティファクトのダウンロードとアップロードの両方を行います。`Tuist.swift`ファイルの`xcodeCache`オプションを使用してこれを制御し、アーティファクトはダウンロードされるがアップロードされない読み取り専用モードを有効にできます。

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

一般的なパターンは、ビルドが再現可能なCIからのみアーティファクトをプッシュし、ローカル環境を読み取り専用に保つことです。これは、ほとんどのCIプロバイダーによって設定される`CI`環境変数をチェックする`Environment.isCI`を使用して実現できます。

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

この設定により、ローカルビルドはアップロードなしでキャッシュされたアーティファクトの恩恵を受け、CIビルドはチームの他のメンバーのためにキャッシュを入力します。

アップロードポリシーは、`tuist setup cache`を実行するマシン上でプロジェクトごとに記録されます。変更するには、`upload`を更新して`tuist setup cache`を再度実行し、Tuistがプロジェクトを生成する場合は`tuist generate`も実行してください。その後、そのマシン上のキャッシュを再起動することなく、アップロードは新しいポリシーに従います。同じマシンで同時に実行される同じプロジェクトのジョブはそのポリシーを共有するため、最新の`tuist setup cache`がすべてに対して決定します。

### ストアサイズ制限 {#store-size-limit}

コンパイルキャッシュストアはビルドごとに増大します。プロジェクトのストアを制限するには、`Tuist.swift`ファイルで`storeSizeLimit`を設定してください。

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

Tuistは、キャッシュプロキシが開始されるとき（どのビルドも使用する前）、およびビルドが実行されていない間は10分ごとに、プロジェクトの各ストアをチェックします。`tuist setup cache`はプロキシが実行されていない場合にプロキシを開始するため、ビルドの前に`tuist setup cache`を実行し、後に`tuist teardown cache`を実行するCIジョブは、長寿命ランナーのストアを各ジョブの開始時に制限します。新しいビルドが制限の約半分を書き込むと、ストアの最も古いキャッシュ出力が削除されるため、ストアは制限付近で安定します。ビルドの実行中はストアが制限を超えることがあり、制限を設定した時点で既に大きかったストアは、新しいビルドがその量を書き込むと縮小します。複数のプロジェクトが同じストア（デフォルトの場所など）を使用する場合、それらの制限のうち最小値が適用されます。制限は`tuist setup cache`を実行するすべてのマシンに適用されるため、制限を変更した後は再度実行してください。すでに実行中のキャッシュプロキシは実行を続け、次のチェック時に新しい制限を適用します。

### モジュールキャッシュハッシュ {#module-cache-hashes}

コンパイルキャッシュ設定は<.localized_link href="/guides/features/projects/hashing">モジュールキャッシュハッシュ</.localized_link>の一部ではありません。Tuistはすべての`COMPILATION_CACHE_*`ビルド設定、および値を持つすべての`-cas-plugin-option`フラグをハッシュから除外します。`enableCaching`の有効化または無効化、あるいはアップロードポリシーの変更は、ターゲットのハッシュを維持するため、すでにウォームアップ済みの<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>バイナリは有効のままです。Xcodeキャッシュありとなしのビルドを、同じモジュールキャッシュに対して比較できます。

> [!NOTE]
> **プレフィックスマッピング設定はハッシュ化されます**
>
> Xcode 27以降では、`enableCaching: true`はさらに`SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`、および`TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`設定も設定します。これらの設定はモジュールキャッシュハッシュの一部であるため、Xcode 27以降では、`enableCaching`の有効化または無効化によりターゲットのハッシュが変化します。

### 大きな出力の一部の再利用 {#reusing-parts-of-large-outputs}

サーバーが対応している場合、Xcodeキャッシュは大きな出力をチャンク単位で転送し、以前のバージョンから変更されたチャンクのみを送信または取得します。チャンクは`DerivedData`とは別の小さなローカルキャッシュに保持されるため、コンパイルキャッシュのクリーニング後も残ります。小さな出力、古いサーバー、および古いクライアントは、通常の出力全体での転送を使用します。

これにより再コンパイルされる量ではなく、ダウンロードおよびアップロードされる量が削減されます。一致するチャンクがないコールドマシンでは、依然として出力全体がダウンロードされます。

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

トークンベースの認証や、Xcode Cloud、CircleCI、Bitrise、Codemagicなどの他のCIプラットフォームを含む詳細な例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link>をご覧ください。

### CI上のコンパイルキャッシュストア {#compilation-cache-store-on-ci}

コンパイルキャッシュストアは、Xcodeがコンパイル出力を保持するローカルディレクトリです。`COMPILATION_CACHE_CAS_PATH`ビルド設定はその場所を設定し、デフォルトでは`DerivedData`内の`CompilationCache.noindex`になります。

#### ステートフルストア {#stateful-store}

ビルド間でストアを維持するには、`COMPILATION_CACHE_CAS_PATH`（および`tuist cache`用の`TUIST_COMPILATION_CACHE_CAS_PATH`）を永続的なパスに向け、[ストアサイズ制限](#store-size-limit)でそのサイズを制限します。

## トラブルシューティング {#troubleshooting}

### Xcodeキャッシュプロキシが失敗したというビルド警告 {#cas-proxy-failed}

ビルドに以下のような警告が表示され、Xcodeが最初に失敗したコンパイルに応じて`CAS error:`または`CAS operation failed:`のプレフィックスを付けた場合：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

コンパイルキャッシュが`tuist setup cache`によってインストールされたローカルキャッシュプロキシに到達できませんでした。ビルド自体は成功しますが、影響を受けたコンパイルはリモートキャッシュヒットを得られないため、空のキャッシュでのビルドと同様に実行されます。これらのアップロードはディスク上に保持され、プロキシが再びリクエストを処理できるようになった時点で送信されます。同じビルド内で間に合えばその後に、そうでなければ同じマシンでの次のビルド中に送信されます。ジョブ終了後に破棄されるCIマシンでは、これらは失われます。警告はビルドごとに1回、XcodeのIssueナビゲーターおよび`xcodebuild`出力に表示されます。

プロキシが実行中かどうかを確認するには、警告に記載されたソケットでリスニングしているプロセスを探します：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

コマンドが何も出力しない場合は、`tuist setup cache`を実行してプロキシを再度起動してください。CIでは、各ジョブ内のあらゆる`xcodebuild`呼び出しの前に`tuist setup cache`を実行します。

### ビルドが極端に遅く、`CAS error: deadlineExceeded`警告が発生する {#cas-deadline-exceeded}

ビルドが予想よりもはるかに長くかかり、Xcodeビルドログに以下のような警告があふれている場合：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

または：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

`COMPILATION_CACHE_REMOTE_SERVICE_PATH`が誰もリスニングしていないソケットを指しています。通常これは、Tuistの旧バージョンが構成していたプロジェクトごとのソケット（`~/.local/state/tuist/<org>_<project>.sock`）です。Tuistはそのソケットをもう提供していません。Xcodeは高速に失敗するのではなく、コンパイルキャッシュのリクエストごとに接続を再試行するため、ビルドに1時間以上かかることがあり、Tuistはこの動作を変更できません。

修正方法：

- **生成されたプロジェクト**：`tuist generate`を再度実行します。
- **その他のプロジェクト**：`COMPILATION_CACHE_*`ビルド設定を、`tuist setup cache`が出力する設定に置き換えます。詳細は[Xcodeビルド設定の構成](#configure-xcode-build-settings)をご覧ください。

Xcodeキャッシュを使用していない場合は、代わりに`COMPILATION_CACHE_*`ビルド設定を削除し、`tuist teardown cache`を実行します。

### アップロードが無効でもローカルで`uploaded CAS output`が表示される {#uploaded-cas-output-with-upload-disabled}

`xcodeCache: .xcodeCache(upload: false)`（または非CIマシンでの`upload: Environment.isCI`）が設定されている場合、ビルドログに依然として`note: uploaded CAS output ...`が表示されることがあります。`xcodebuild`にはそれらの呼び出しをスキップする方法がないため、Tuistはそれらを受信しますが、Tuistサーバーには何も公開しません。ダッシュボードのメトリクスはこの点を考慮しているため、不正なアップロードトラフィックは報告されません。

## 関連項目 {#related}

エンジニアリングチームやコーディングエージェントがビルド成果物をどのように再利用しているかを確認するには、[Tuistの共有キャッシュ](https://tuist.dev/cache)をご覧ください。
