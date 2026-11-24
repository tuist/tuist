---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · コードカバレッジ · 機能 · ガイド · Tuist",
  "description": "Tuistで生成されたXcodeプロジェクトのファイルごと、コミットごとのコードカバレッジを測定します。バイナリキャッシュや選択的テストでスキップされたコードも含みます。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-code-coverage}

コードカバレッジは、テストがコードのどの行を実行したかを示します。Tuistはすべての `tuist test` 実行の行カバレッジをアップロードし、コミットの実行をプロジェクト、各ターゲット、および各ファイルごとに1つの数値にまとめます。ダッシュボードの **コードカバレッジ** ページでは、コミットごとの値と各ブランチのトレンドとして表示されます。

<!-- @snippet: ./_xcode-requirements -->

Tuistが処理をスキップしても、この数値は正確に保たれます。<.localized_link href="/guides/features/cache/module-cache">バイナリキャッシュ</.localized_link> からのターゲットはカバレッジカウンター付きでビルドされるため、ソースからビルドされたコードと同様に測定されます。また、<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選択的テスト</.localized_link> がテストターゲットをスキップした場合、そのターゲットは以前の実行で持っていたカバレッジを維持します。これは、Tuistがすべての実行で記録する [ターゲットレベルのカバレッジ](#target-level-coverage) を介して実現されます。

## セットアップ {#setup}

### カバレッジを有効にする {#turn-coverage-on}

`Tuist.swift` の生成オプションでカバレッジを有効にし、デフォルトではオフになっているカバレッジのアップロードをオンにします。

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

生成オプションを有効にした場合：

- Tuistが生成するすべてのスキームのテストアクションはカバレッジを収集し、`coverage` が未設定のまま定義したすべてのスキームのテストアクションも同様です。`.options(coverage: false)` または `.options(coverage: true)` を持つスキームはその値を保持します。テストプランはカバレッジを独自に決定します。Tuistが生成するテストプランの場合、`coverage: true` を `.testPlans(_:coverage:)` に渡してください。
- プロジェクト独自のターゲットは、Debug構成でカバレッジカウンター付きでバイナリキャッシュから読み取られ、ウォームアップされます。[仕組み](#instrumented-binaries) を参照してください。

`TUIST_COVERAGE_ENABLED` および `TUIST_COVERAGE_UPLOAD` 環境変数（`1` または `0`）は、`enabled` および `upload` より優先されます。単一のコマンドではなく、CIワークフローなどの環境全体に対して設定し、キャッシュをウォームアップするコマンドと読み取るコマンドの間で整合性を取ってください。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成オプションは、プロジェクトのターゲットのキャッシュキーと、そのテストターゲットの選択的テストハッシュを変更します。キャッシュを共有するすべてのマシンで同じ値を使用し、環境（例えば `Environment.isCI` ）から導出しないようにしてください。カバレッジがオフの実行は、カバレッジがオンの実行のバイナリや選択的テストの結果を再利用しません。

### スキームを除外する {#leave-schemes-out}

一部のスーツはカバレッジの対象外とするべきです。例えば、別のプロセスからアプリやCLIを駆動する受け入れテストやエンドツーエンドテストは、カバレッジが見えないコードを実行するため、収集すると遅くなるだけです。それらのスキームのテストアクションでカバレッジをオフにします。

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

スキームは、`Tuist.swift` オプションや `TUIST_COVERAGE_ENABLED` の設定に関係なくカバレッジをオフのまま維持し、その実行はコミットのカバレッジにカウントされません。カバレッジはスキームごとに収集されるため、特定のテストターゲットを除外するには、それを独自のスキームに移してください。

### テストを実行する {#run-your-tests}

通常通り、`tuist test` でテストを実行します。

```sh
tuist test
```

Tuistは、実行が収集したカバレッジをテスト結果と一緒にアップロードします。これには、<.localized_link href="/guides/features/test-sharding/generated-xcode-project">分割実行</.localized_link> や、`--without-building` で別のジョブでビルドされた製品をテストする実行が含まれます。フォークからのプルリクエストを実行するジョブなど、Tuistに実行のカバレッジを含めたくない場合は、`TUIST_COVERAGE_UPLOAD=0` を設定してください。

### CIで各コミットを完了させる {#complete-each-commit}

コミットのカバレッジは、しばしば複数のジョブ（スキームごと、シャードごと、またはプラットフォームごと）から得られます。Tuistは最後に報告されたジョブを自動で検出できないため、明示的に通知する必要があります。コミットのすべてのテストジョブが終了したら、それらすべてに依存するジョブで以下を実行します。

```sh
tuist coverage complete
```

このコマンドは、チェックアウトの `HEAD` （テストが実行されたコミット）からコミットを読み取ります。別のコミットを指定するには `--commit <sha>` を渡してください。コミットが完了するまで、そのカバレッジは **進行中** と表示され、ブランチのトレンドには含まれません。

### デフォルトブランチで全スイートを実行する {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 選択的テストは、スキップされたターゲットを引き継ぐための以前の実行が存在する場合にのみ、コミットのカバレッジを完全な状態に保ちます。デフォルトブランチで、選択的テストなしですべてのテストを実行するようにスケジュールしてください。
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> マージごとに1回実行するのが理想的です。変更の少ないリポジトリでは、毎日または毎週でも十分な場合があります。記録されたカバレッジは31日後に期限切れになるため、それよりも頻繁に実行してください。

引き継がれたカバレッジは完全な実行に依存します。完全な実行は、期限切れ前に各ターゲットの記録されたカバレッジを更新し、選択的実行がビルドしないファイルの最新の状態をTuistに提供します。完全な実行の間にリポジトリの変更が多いほど、選択的実行は変更されたファイルを見つけやすくなり、そのコミットのカバレッジは **不完全** になります。

## ターゲットレベルのカバレッジ {#target-level-coverage}

実行のカバレッジは、全体の実行が何を実行したかを示し、各テストターゲットが何を実行したかは示しません。選択的テストがターゲットをスキップする場合、Tuistはそのターゲットのカバレッジを引き継ぐために、以前の実行でそのターゲットが何を実行したかを知る必要があります。

そのため、Tuistはすべての実行で、各テストターゲットが実行したファイルと行も記録します。これは各テストプロセスに対してXcodeが書き込むカバレッジから読み取られるため、リンクや設定は不要です。これはmacOSおよびiOSシミュレーターで記録され、デバイス上では記録されません。UIテストは、駆動するアプリに関する情報を何も記録しません。アプリのコードは独自のプロセスで実行されるためです。

## 仕組み {#how-it-works}

### インストルメント化されたバイナリ {#instrumented-binaries}

バイナリキャッシュからのターゲットは事前ビルドされたバイナリであり、テスト実行はそのバイナリがカバレッジカウンター付きでビルドされている場合にのみコードを測定できます。カバレッジが有効な場合、バイナリキャッシュはプロジェクト独自のターゲットのインストルメント化されたバリアントを保持し、すべてのコマンドはそのバリアントを読み取り、ウォームアップします。

- **Debug構成** はインストルメント化されたバリアントを使用します。`tuist cache` がこれをウォームアップし、`tuist generate` および `tuist test` がこれを読み取ります。
- **Release構成** は常にプレーンなバリアントを使用するため、出荷するものにカバレッジカウンターが含まれることはありません。
- **外部パッケージ** は常にプレーンなバリアントを使用します。Tuistはリポジトリのコードのみを測定します。

テストジョブと同じ環境でカバレッジを有効にしてキャッシュをウォームアップし、`tuist test` がインストルメント化されたバイナリを見つけられるようにしてください。実行がカバレッジを収集したが、キャッシュからプレーンなバイナリとしてターゲットを取得した場合、Tuistは警告を発し、そのコードは測定されません。<.localized_link href="/guides/features/cache/module-cache#code-coverage">モジュールキャッシュ</.localized_link> には、これらのバリアントの詳細な説明があります。

### マシン間のパス {#paths-across-machines}

インストルメント化されたバイナリは、ビルドされたチェックアウトに対する相対パスでソースパスを記録するため、CIでウォームアップされたバイナリは、どの開発者のマシンでも正しいファイルを測定します。

<.localized_link href="/guides/features/cache/xcode-cache">Xcodeキャッシュ</.localized_link>もプレフィックスマッピングを通じて同様に動作しますが、Xcode独自のカバレッジレポートはマッピングされたパスを解決できないため、Tuistはカバレッジを収集するビルドでこれをデフォルトで無効にします。Xcode 27以降では、`enableCaching` を有効にした状態で `prefixMapping: true` を使用すると、この設定が維持され、カバレッジビルドでもチェックアウト間でコンパイル結果を共有できます。

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuistのアップロードはマッピングされたパスを解決しますが、Xcodeのカバレッジレポートや `xccov` はそれらのファイルを除外する可能性があります。<.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">プレフィックスマッピングを使用したカバレッジ</.localized_link> を参照してください。

### スキップされたテスト {#skipped-tests}

選択的テストは、以前の成功した実行が同じハッシュで既にそのターゲットをテスト済みの場合、そのテストターゲットをスキップします。ハッシュにはターゲットのソース、そのテスト、およびすべての依存関係が含まれるため、同じハッシュは同じコードに対する同じテストを意味します。Tuistは、以前の実行がそのターゲットに対して記録した [ターゲットレベルのカバレッジ](#target-level-coverage) を再利用します。もし記録されていなかった場合（例えば、当時カバレッジが無効だったか、実行が31日以上前のものである場合など）、引き継ぐデータがなく、コミットは **不完全** となります。

選択的実行もまた、すべてのファイルをビルドするわけではありません。コンパイルされなかったファイルについては、Tuistはそれ以降に変更がない限り、最も近い以前の完全実行からの行数を採用します。これが、デフォルトブランチでの [完全実行](#full-runs) が重要な理由です。

`--skip-test-targets` や `-skip-testing` を使用して自分でスキップしたテストは引き継がれません。それらを実行しなかったコミットの実行は、そのコミットの他の実行でそれらが実行されていない限り、**不完全** となります。検疫によってスキップされたテストはカバレッジに含まれません。Tuistはそれらを引き継ぐことも、それらのためにコミットを **不完全** とマークすることもありません。

### 完了および未完了のコミット {#commit-status}

ダッシュボード上の各コミットにはステータスがあります。

| ステータス | 意味 |
| --- | --- |
| 進行中 | 実行がカバレッジを報告していますが、`tuist coverage complete` がそのコミットに対してまだ実行されていません。 |
| 完了 | コミットのスキームのすべてのテストが実行されたか、引き継がれました。 |
| 不完全 | 一部のカバレッジを特定できなかったため、数値は下限となります。 |
| 未測定 | コミットに対してカバレッジを報告した実行がありません。 |

ブランチのトレンドには完了したコミットのみが含まれます。コミットが不完全になる例としては、以下のような場合があります。

- 選択的テストが引き継げないターゲットをスキップした場合：以前の実行でそのターゲットのカバレッジが記録されていなかった、選択的実行がビルドしなかったファイルが最後の完全実行以降に変更された、あるいは `Package.resolved`、`Project.swift`、または `.xcconfig` のようにすべてのターゲットに影響するファイルがコミットで変更された。
- 実行が `--skip-test-targets` または `-skip-testing` でテストをスキップし、そのコミットの他の実行でそれらが実行されなかった。
- 実行がバイナリキャッシュからプレーンなバイナリとしてターゲットを取得した。
- スキームのすべての実行が `-only-testing` で絞り込まれていた。
- スキームのカバレッジが、未コミットの変更があるチェックアウトでのCI実行からのみ得られた。

## パフォーマンスへの影響 {#performance-impact}

カバレッジの収集はオーバーヘッドを追加しますが、主にテスト終了後、Xcodeがカバレッジレポートを書き込み、Tuistがカバレッジをエクスポートしている間です。テストのビルドと実行にかかる時間は、カバレッジなしの場合とほぼ同じです。インストルメント化されたビルドは、DerivedDataおよびDebugバイナリキャッシュにより多くのディスク容量を必要とします。Releaseビルドおよびアーカイブは影響を受けません。

## 制限事項 {#limitations}

### カバレッジを収集するスキームのReleaseビルド {#release-builds}

スキームのテストアクションがカバレッジを収集する場合、Xcodeはそのスキーム用に `xcodebuild build` がソースからコンパイルするターゲットもインストルメント化します（Release構成を含むあらゆる構成で）。`xcodebuild archive` はこの設定を無視するため、アーカイブは決してインストルメント化されません。アーカイブを配布するか、`.options(coverage: false)` を持つスキームからReleaseプロダクトをビルドしてください。

### その他のカバレッジツール {#other-coverage-tools}

`-enableCodeCoverage YES` は、Xcodeと同様に、実行がカバレッジを収集するかどうかだけを決定します。これによりTuistがキャッシュからインストルメント化されたバイナリを読み取るようになるわけではないため、代わりに `Tuist.swift` オプションまたは `TUIST_COVERAGE_ENABLED` を使用してください。

別のカバレッジツールにデータを提供するには、`tuist test` に各実行のカバレッジをLCOVとして書き出させます。これはTuistがアップロードするものと同じカバレッジであり、リポジトリ相対パスとバイナリキャッシュからのコードが含まれています。

```sh
tuist test --coverage-output-path coverage
```

各実行は `coverage/<result bundle name>.lcov` に書き出します。シャードされた実行のファイルは `lcov -a` でマージしてください。このオプションにはカバレッジアップロードが有効である必要があります。

Xcode独自のカバレッジレポート、およびそれを読み取るツールは、その実行中にXcodeがビルドしたターゲットのみを含み、バイナリキャッシュから来たコードは決して含みません。Tuistのアップロードは両方を測定します。Xcodeのレポートでターゲットのカバレッジを確認したい場合は、そのターゲットをソースからビルドするようにプロジェクトを生成してください。`tuist generate MyTarget` は `MyTarget` をソースとして保持し、残りはキャッシュから取得します。

## カバレッジのクエリ {#querying}

`tuist coverage` コマンドは、ダッシュボードに表示される内容を読み取ります。`--commit` なしの場合、`--branch` の最新の完了コミット、またはデフォルトブランチの最新完了コミットを読み取ります。

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

テスト実行自体のカバレッジは `tuist test show <test-run-id>` に表示されます。

すべてがスクリプト用に `--json` を受け入れます。同じデータは、<.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocolサーバー</.localized_link> を介してエージェントからも利用可能です。
