---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · コードカバレッジ · 機能 · ガイド · Tuist",
  "description": "バイナリキャッシュや選択的テストでスキップされたコードを含め、Tuistが生成したXcodeプロジェクトのコードカバレッジをファイルごと、コミットごとに測定します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-code-coverage}

コードカバレッジは、テストが実行したコードの行を示します。Tuistは `tuist test` の各実行の行カバレッジをアップロードし、コミット内の実行をプロジェクト、各ターゲット、および各ファイルごとに1つの数値に集約します。ダッシュボードの **コードカバレッジ** ページでは、コミットごとの値とブランチごとのトレンドが表示されます。

<!-- @snippet: ./_xcode-requirements -->

Tuistが処理をスキップしても、この数値は正確に保たれます。<.localized_link href="/guides/features/cache/module-cache">バイナリキャッシュ</.localized_link> から取得したターゲットはカバレッジカウンタ付きでビルドされるため、ソースからビルドしたコードと同様に測定されます。また、<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選択的テスト</.localized_link> がテストターゲットをスキップした場合、そのターゲットは以前の実行で持っていたカバレッジを維持します。これは、Tuistがすべての実行で記録する [ターゲットレベルのカバレッジ](#target-level-coverage) によるものです。

## セットアップ {#setup}

### カバレッジを有効にする {#turn-coverage-on}

`Tuist.swift` の生成オプションでカバレッジを有効にし、デフォルトで無効になっているカバレッジのアップロードもオンにします。

```swift
import ProjectDescription

let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

生成オプションを有効にすると：

- Tuistが生成するすべてのスキームのテストアクションはカバレッジを収集し、`coverage` を設定せずに定義したスキームのテストアクションも同様です。`.options(coverage: false)` または `.options(coverage: true)` を持つスキームはその値を保持します。テストプランは独自にカバレッジを決定します。Tuistが生成するテストプランの場合、`.testPlans(_:coverage:)` に `coverage: true` を渡してください。
- プロジェクト独自のターゲットは、Debug構成においてカバレッジカウンタ付きでバイナリキャッシュから読み取られ、ウォームアップされます。[仕組み](#instrumented-binaries) を参照してください。

`TUIST_COVERAGE_ENABLED` および `TUIST_COVERAGE_UPLOAD` 環境変数（`1` または `0`）は、`enabled` および `upload` より優先されます。キャッシュをウォームアップするコマンドと読み取るコマンドの一貫性を保つため、単一のコマンドではなく、CIワークフローなどの環境全体に対して設定してください。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成オプションは、プロジェクトのターゲットのキャッシュキーと、そのテストターゲットの選択的テストハッシュを変更します。キャッシュを共有するすべてのマシンで同じ値を使用し、環境（例えば `Environment.isCI` など）から導出しないでください。カバレッジをオフにした実行は、カバレッジをオンにした実行のバイナリや選択的テストの結果を再利用しません。

### スキームを除外する {#leave-schemes-out}

一部のスィートはカバレッジの対象外とするべきです。例えば、別のプロセスからアプリやCLIを操作する受け入れテストやエンドツーエンドテストは、カバレッジが検知できないコードを実行するため、収集しても低速化するだけです。それらのスキームのテストアクションでカバレッジをオフにします。

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

このスキームは、`Tuist.swift` オプションや `TUIST_COVERAGE_ENABLED` の設定に関わらずカバレッジをオフのまま維持し、その実行はコミットのカバレッジに計上されません。カバレッジはスキームごとに収集されるため、特定のテストターゲットを除外するには、それを独自のスキームに移してください。

### テストを実行する {#run-your-tests}

通常通り、`tuist test` でテストを実行します。

```sh
tuist test
```

Tuistは、実行で収集されたカバレッジをテスト結果とともにアップロードします。これには <.localized_link href="/guides/features/test-sharding/generated-xcode-project">シャード化された実行</.localized_link> や、`--without-building` を使用して別のジョブでビルドされた製品をテストする実行が含まれます。フォークからのプルリクエストを実行するジョブなど、Tuistに実行のカバレッジを含めたくない場合は、`TUIST_COVERAGE_UPLOAD=0` を設定してください。

### CIで各コミットを完了させる {#complete-each-commit}

コミットのカバレッジは、スキームごと、シャードごと、またはプラットフォームごとの複数のジョブから提供されることがよくあります。Tuistは最後のジョブが報告を終えたタイミングを自動で検知できないため、明示的に通知する必要があります。コミットのすべてのテストジョブが終了したら、それらすべてに依存するジョブで次のコマンドを実行します。

```sh
tuist coverage complete
```

このコマンドは、チェックアウトの `HEAD` （テストが実行されたコミット）からコミットを読み取ります。別のコミットを指定するには `--commit <sha>` を渡してください。コミットが完了するまで、そのカバレッジは **進行中** と表示され、ブランチのトレンドには含まれません。

### デフォルトブランチで全スィートを実行する {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 選択的テストは、スキップされたターゲットのカバレッジを引き継ぐための以前の実行が存在する場合にのみ、コミットのカバレッジを完全な状態に保ちます。デフォルトブランチで、選択的テストなしですべてのテストを実行するスケジュールを設定してください。
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> マージごとに1回実行するのが理想的です。変更の少ないリポジトリであれば、毎日または毎週でも十分な場合があります。記録されたカバレッジは31日後に期限切れになるため、それよりも頻繁に実行してください。

引き継がれたカバレッジは完全な実行に依存します。完全な実行は、期限切れ前に各ターゲットの記録済みカバレッジを更新し、選択的実行でビルドされないファイルの最新の状態をTuistに提供します。完全な実行の間にリポジトリの変更が多ければ多いほど、選択的実行は変更されたファイルを検出し、そのコミットのカバレッジは **不完全** になりやすくなります。

## ターゲットレベルのカバレッジ {#target-level-coverage}

実行のカバレッジは、実行全体が何を処理したかを示すものであり、各テストターゲットが何を処理したかを示すものではありません。選択的テストがターゲットをスキップする場合、Tuistはそのターゲットのカバレッジを引き継ぐために、以前の実行でそのターゲットが何を処理したかを知る必要があります。

そのため、Tuistはすべての実行において、各テストターゲットがどのファイルと行を実行したかも記録します。これはXcodeが各テストプロセス用に書き出すカバレッジから読み取られるため、リンクや設定は不要です。これはmacOSおよびiOSシミュレータ上で記録されますが、デバイス上では記録されません。UIテストは、操作対象のアプリに関する情報を一切記録しません。アプリのコードは独自のプロセスで実行されるためです。

## 仕組み {#how-it-works}

### インストルメント化されたバイナリ {#instrumented-binaries}

バイナリキャッシュからのターゲットは事前ビルドされたバイナリであり、テスト実行はそのバイナリがカバレッジカウンタ付きでビルドされている場合にのみコードを測定できます。カバレッジを有効にすると、バイナリキャッシュにはプロジェクト独自のターゲットのインストルメント化された変体が保持され、すべてのコマンドがその変体を読み取り、ウォームアップします。

- **Debug構成** はインストルメント化された変体を使用します。`tuist cache` がこれをウォームアップし、`tuist generate` および `tuist test` がこれを読み取ります。
- **Release構成** は常にプレーンな変体を使用するため、リリースする製品にはカバレッジカウンタが含まれません。
- **外部パッケージ** は常にプレーンな変体を使用します。Tuistはリポジトリのコードのみを測定します。

テストジョブと同じ環境でカバレッジを有効にしてキャッシュをウォームアップし、`tuist test` がインストルメント化されたバイナリを見つけられるようにしてください。実行がカバレッジを収集したが、ターゲットをプレーンなバイナリとしてキャッシュから取得した場合、Tuistは警告を発し、そのコードは測定されません。<.localized_link href="/guides/features/cache/module-cache#code-coverage">モジュールキャッシュ</.localized_link> には、これらの変体について詳細な説明があります。

### マシン間でのパス {#paths-across-machines}

インストルメント化されたバイナリは、ビルドされたチェックアウトに対する相対パスとしてソースパスを記録するため、CIでウォームアップされたバイナリは、どの開発者のマシンでも正しいファイルを測定します。

<.localized_link href="/guides/features/cache/xcode-cache">Xcodeキャッシュ</.localized_link>もプレフィックスマッピングによって同様に動作しますが、Xcode自体のカバレッジレポートはマッピングされたパスを解決できないため、Tuistはカバレッジを収集するビルドではこれをデフォルトで無効にします。Xcode 27以降では、`enableCaching`を有効にすると`prefixMapping: true`によってこれが維持されるため、カバレッジビルドでもチェックアウト間でコンパイル結果が共有されます：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuistのアップロードはマッピングされたパスを解決しますが、Xcodeのカバレッジレポートや`xccov`はそれらのファイルを除外する可能性があります。<.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">プレフィックスマッピングを使用したカバレッジ</.localized_link>をご覧ください。

### スキップされたテスト{#skipped-tests}

選択的テストは、以前の合格した実行が同じハッシュで既にそのターゲットをテストしていた場合、そのテストターゲットをスキップします。ハッシュにはターゲットのソース、そのテスト、およびすべての依存関係が含まれるため、同じハッシュは同じコードに対する同じテストを意味します。Tuistは、以前の実行がそのターゲットに対して記録した[ターゲットレベルのカバレッジ](#target-level-coverage)を再利用します。もし記録されていなかった場合（例えば、当時カバレッジが無効だったか、実行が31日以上前のものである場合）、引き継ぐデータがなく、コミットは**不完全**となります。

選択的実行もまた、すべてのファイルをビルドするわけではありません。コンパイルしなかったファイルについては、ファイルがその後変更されていない限り、Tuistは最も近い以前の完全な実行からの行数を採用します。これが、デフォルトブランチでの[完全な実行](#full-runs)が重要な理由です。

`--skip-test-targets`または`-skip-testing`を使用して自分でスキップしたテストは引き継がれません。それらを実行から除外したコミットは、そのコミットの他の実行がそれらを実行していない限り、**不完全**となります。検疫によってスキップされたテストはカバレッジの一部ではありません。Tuistはそれらを引き継ぐことも、それらのためにコミットを**不完全**とマークすることもありません。

### 完全なコミットと不完全なコミット{#commit-status}

ダッシュボード上の各コミットにはステータスがあります：

| ステータス | 意味 |
| --- | --- |
| 進行中 | 実行がカバレッジを報告していますが、`tuist coverage complete`がまだそのコミットに対して実行されていません。 |
| 完了 | コミットのスキームのすべてのテストが実行されたか、引き継がれました。 |
| 不完全 | 一部のカバレッジを決定できなかったため、数値は下限値となります。 |
| 未測定 | コミットに対してカバレッジを報告した実行がありません。 |

ブランチのトレンドには完全なコミットのみが含まれます。コミットは、例えば以下の場合に不完全となります：

- 選択的テストが引き継げないターゲットをスキップした場合：以前の実行がそのターゲットのカバレッジを記録していなかった、選択的実行がビルドしなかったファイルが最後の完全な実行以降に変更された、またはコミットが`Package.resolved`、`Project.swift`、あるいは`.xcconfig`など、すべてのターゲットに影響を与えるファイルを変更した場合。
- 実行が`--skip-test-targets`または`-skip-testing`でテストをスキップし、そのコミットの他の実行がそれらを実行しなかった場合。
- 実行がバイナリキャッシュからターゲットをプレーンなバイナリとして取得した場合。
- スキームのすべての実行が`-only-testing`で絞り込まれていた場合。
- スキームのカバレッジが、未コミットの変更があるチェックアウトでのCI実行からのみ来ていた場合。

## パフォーマンスへの影響{#performance-impact}

カバレッジの収集はオーバーヘッドを追加します。主にテスト終了後、Xcodeがカバレッジレポートを書き込み、Tuistがカバレッジをエクスポートしている間です。テストのビルドと実行にかかる時間は、カバレッジなしの場合とほぼ同じです。インストルメント化されたビルドは、DerivedDataおよびDebugバイナリキャッシュにより多くのディスクスペースを必要とします。Releaseビルドとアーカイブは影響を受けません。

## 制限事項{#limitations}

### カバレッジを収集するスキームのReleaseビルド{#release-builds}

スキームのテストアクションがカバレッジを収集する場合、Xcodeはそのスキーム用に`xcodebuild build`がソースからコンパイルするターゲットをインストルメント化します（Release構成を含む）。`xcodebuild archive`はこの設定を無視するため、アーカイブは決してインストルメント化されません。アーカイブを配布するか、`.options(coverage: false)`を持つスキームからRelease製品をビルドしてください。

### その他のカバレッジツール{#other-coverage-tools}

`-enableCodeCoverage YES`は、Xcodeと同様に、実行がカバレッジを収集するかどうかのみを決定します。Tuistがキャッシュからインストルメント化されたバイナリを読み取るようにはしないため、代わりに`Tuist.swift`オプションまたは`TUIST_COVERAGE_ENABLED`を使用してください。

他のカバレッジツールにデータを提供するには、`tuist test`に各実行のカバレッジをLCOVとして書き出させます。これはTuistがアップロードするものと同じカバレッジであり、リポジトリ相対パスとバイナリキャッシュからのコードが含まれています：

```sh
tuist test --coverage-output-path coverage
```

各実行は`coverage/<result bundle name>.lcov`を書き出します。シャード化された実行のファイルを`lcov -a`でマージしてください。このオプションにはカバレッジアップロードが有効である必要があります。

Xcode独自のカバレッジレポート、およびそれを読み取るツールは、その実行でXcodeがビルドしたターゲットのみを含み、バイナリキャッシュから来たコードは決して含みません。Tuistのアップロードは両方を測定します。Xcodeのレポートでターゲットのカバレッジを確認したい場合は、そのターゲットをソースからビルドしてプロジェクトを生成してください：`tuist generate MyTarget`は`MyTarget`をソースとして保持し、残りをキャッシュから取得します。

## カバレッジのクエリ{#querying}

`tuist coverage`コマンドは、ダッシュボードに表示される内容を読み取ります。`--commit`がない場合、それらは`--branch`の最新の完全なコミット、またはデフォルトブランチの最新のものを読み取ります：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

テスト実行自体のカバレッジは`tuist test show <test-run-id>`に表示されます。

すべてがスクリプト用に`--json`を受け入れます。同じデータは、<.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocolサーバー</.localized_link>を通じてエージェントでも利用可能です。
