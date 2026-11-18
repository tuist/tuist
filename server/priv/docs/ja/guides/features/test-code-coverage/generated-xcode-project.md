---
{
  "title": "生成された Xcode プロジェクト",
  "titleTemplate": ":title · コードカバレッジ · 機能 · ガイド · Tuist",
  "description": "バイナリキャッシュと選択的テストでスキップされるコードを含め、Tuist が生成した Xcode プロジェクトのコードカバレッジをファイル単位およびコミット単位で測定します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-code-coverage}

コードカバレッジは、テストが実行したコードの行を示します。Tuistは `tuist test` の各実行における行カバレッジをアップロードし、コミットに含まれるすべての実行をプロジェクト全体、各ターゲット、各ファイルごとに1つの数値に集約します。ダッシュボードの **コードカバレッジ** ページでは、コミットごとの値とブランチごとの推移を確認できます。

<!-- @snippet: ./_xcode-requirements -->

Tuistが処理をスキップしても、この数値は正確に保たれます。<.localized_link href="/guides/features/cache/module-cache">バイナリキャッシュ</.localized_link> から取得したターゲットはカバレッジカウンタ付きでビルドされるため、ソースからビルドした場合と同様にコードが計測されます。また、<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選択的テスト</.localized_link> がテストターゲットをスキップした場合でも、そのターゲットは以前の実行で記録されたカバレッジを維持します。これは、Tuistが各実行で記録する [ターゲットレベルのカバレッジ](#target-level-coverage) によって実現されます。

## セットアップ {#setup}

### カバレッジを有効にする {#turn-coverage-on}

`Tuist.swift` の生成オプションでカバレッジを有効にし、デフォルトでは無効になっているカバレッジのアップロードもオンにしてください。

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

生成オプションを有効にすると、以下のようになります。

- Tuistが生成するすべてのスキームのテストアクションはカバレッジを収集します。また、あなたが定義したスキームのうち `coverage` を設定していないものについても同様です。`.options(coverage: false)` または `.options(coverage: true)` を指定したスキームはその値を保持します。テストプラン自体がカバレッジを決定します。Tuistが生成するテストプランの場合、`.testPlans(_:coverage:)` に `coverage: true` を渡してください。
- プロジェクト固有のターゲットは、Debug構成においてカバレッジカウンタ付きでバイナリキャッシュから読み込まれ、ウォームアップされます。詳細は [仕組み](#instrumented-binaries) を参照してください。

`TUIST_COVERAGE_ENABLED` および `TUIST_COVERAGE_UPLOAD` 環境変数（`1` または `0`）は、`enabled` および `upload` より優先されます。単一のコマンドではなく、CIワークフローなど環境全体に対して設定し、キャッシュをウォームアップするコマンドとそれを読み取るコマンドの間で整合性を取ってください。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成オプションは、プロジェクトのターゲットのキャッシュキーと、そのテストターゲットの選択的テスト用ハッシュを変更します。キャッシュを共有するすべてのマシンで同じ値を使用し、環境（例：`Environment.isCI`）から導出しないようにしてください。カバレッジを無効にした実行では、カバレッジを有効にした実行のバイナリや選択的テストの結果を再利用しません。

### スキームを対象外にする {#leave-schemes-out}

一部のスィートはカバレッジの対象に含めるべきではありません。例えば、別のプロセスからアプリやCLIを操作する受け入れテストやエンドツーエンドテストは、カバレッジツールが見ることができないコードを実行するため、収集しても遅くなるだけです。これらのスキームのテストアクションでカバレッジを無効にしてください。

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

`Tuist.swift` オプションや `TUIST_COVERAGE_ENABLED` の設定に関わらず、このスキームはカバレッジを無効のまま維持し、その実行結果はコミットのカバレッジにカウントされません。カバレッジはスキームごとに収集されるため、特定のテストターゲットを対象外にするには、それを独自のスキームに移してください。

### テストを実行する {#run-your-tests}

通常通り `tuist test` でテストを実行してください。

```sh
tuist test
```

Tuistは、実行中に収集されたカバレッジをテスト結果とともにアップロードします。これには <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分割実行</.localized_link> や、`--without-building` を使用して別のジョブでビルドされた製品をテストする実行も含まれます。フォークからのプルリクエストを実行するジョブなど、Tuistにカバレッジを含めたくない場合は、`TUIST_COVERAGE_UPLOAD=0` を設定してください。

### CI上で各コミットを完了させる {#complete-each-commit}

コミットのカバレッジは、スキームごと、シャードごと、またはプラットフォームごとの複数のジョブから寄せられることがよくあります。Tuistは最後のジョブが報告を終えたタイミングを自動検出できないため、明示的に通知する必要があります。コミットに関連するすべてのテストジョブが終了したら、それらすべてに依存するジョブで次のコマンドを実行してください。

```sh
tuist coverage complete
```

このコマンドは、チェックアウトまたはCIプロバイダーからコミットを読み取ります。別のコミットを指定するには `--commit <sha>` を渡してください。コミットが完了するまで、そのカバレッジは **進行中** と表示され、ブランチの推移には反映されません。

### デフォルトブランチで全スィートを実行する {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 選択的テストは、スキップされたターゲットのカバレッジを引き継ぐための以前の実行が存在する場合にのみ、コミットのカバレッジを「完了」として維持できます。デフォルトブランチでは、選択的テストを使わずにすべてのテストを実行するスケジュールを組みましょう。
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> マージごとに1回実行するのが理想的です。変更の少ないリポジトリであれば、毎日または毎週でも十分かもしれません。記録されたカバレッジは31日後に期限切れになるため、それより頻繁に実行してください。

引き継がれたカバレッジは完全な実行に依存しています。完全な実行は、期限切れ前に各ターゲットの記録済みカバレッジを更新し、選択的実行ではビルドされないファイルの最新状態をTuistに提供します。完全な実行の間にリポジトリの変更が多ければ多いほど、選択的実行は変更されたファイルを検出し、コミットのカバレッジが **不完全** になる頻度が高まります。

## ターゲットレベルのカバレッジ {#target-level-coverage}

ある実行のカバレッジは、その実行全体で何が実行されたかを示すものであり、各テストターゲットが何を実行したかを示すものではありません。選択的テストがターゲットをスキップする場合、Tuistはそのターゲットのカバレッジを引き継ぐために、以前の実行でそのターゲットが何を実行したかを知る必要があります。

そのため、Tuistは各実行において、各テストターゲットが実行したファイルと行も記録します。これはXcodeが各テストプロセス用に書き出すカバレッジから読み取られるため、追加の設定やリンクは不要です。記録はmacOSおよびiOSシミュレータ上で行われ、実デバイス上では行われません。UIテストは、操作対象のアプリに関する情報を一切記録しません。これは、アプリのコードが独自のプロセスで実行されるためです。

## 仕組み {#how-it-works}

### インストルメント済みバイナリ {#instrumented-binaries}

バイナリキャッシュ内のターゲットは事前ビルドされたバイナリであり、テスト実行はそのバイナリがカバレッジカウンタ付きでビルドされている場合にのみコードを計測できます。カバレッジが有効な場合、バイナリキャッシュはプロジェクト固有のターゲットのインストルメント済みバリアントを保持し、すべてのコマンドがそのバリアントを読み取り、ウォームアップします。

- **Debug構成** はインストルメント済みバリアントを使用します。`tuist cache` がこれをウォームアップし、`tuist generate` および `tuist test` がこれを読み取ります。
- **Release構成** は常にプレーンなバリアントを使用するため、リリースされる製品にカバレッジカウンタが含まれることはありません。
- **外部パッケージ** は常にプレーンなバリアントを使用します。Tuistはリポジトリ内のコードのみを計測します。

`tuist test` がインストルメント済みバイナリを見つけられるよう、テストジョブと同じ環境でカバレッジを有効にしてキャッシュをウォームアップしてください。実行がカバレッジを収集しようとしても、キャッシュからプレーンなバイナリとしてターゲットを取得した場合、Tuistは警告を発し、そのコードは計測されません。詳細は <.localized_link href="/guides/features/cache/module-cache#code-coverage">モジュールキャッシュ</.localized_link> を参照してください。

### マシン間でのパス {#paths-across-machines}

インストルメント済みバイナリは、ビルド時のチェックアウトに対する相対パスでソースパスを記録するため、CIでウォームアップされたバイナリは、どの開発者のマシン上でも正しいファイルを計測できます。

<.localized_link href="/guides/features/cache/xcode-cache">Xcodeキャッシュ</.localized_link>もプレフィックスマッピングを通じて同様に動作します。Xcode独自のカバレッジレポートはマッピングされたパスを解決できないため、Tuistはカバレッジを収集するビルドにおいてこれをデフォルトで無効にしています。Xcode 27以降では、`enableCaching` を有効にすると `prefixMapping: true` がこれを維持するため、カバレッジビルドでもチェックアウト間でコンパイル結果を共有できます。

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuistのアップロードはマッピングされたパスを解決しますが、Xcodeのカバレッジレポートや `xccov` はそれらのファイルを除外する可能性があります。<.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">プレフィックスマッピングを使用したカバレッジ</.localized_link> を参照してください。

### スキップされたテスト {#skipped-tests}

選択的テストは、以前の合格した実行が同じハッシュで既にテスト済みの場合、そのテストターゲットをスキップします。ハッシュにはターゲットのソース、そのテスト、およびすべての依存関係が含まれるため、同じハッシュは同じコードに対する同じテストを意味します。Tuistは、以前の実行がターゲットに対して記録した [ターゲットレベルのカバレッジ](#target-level-coverage) を再利用します。もし記録されていない場合（例えば、当時カバレッジが無効だったか、実行が31日以上前である場合）、引き継ぐデータがなく、コミットは **不完全** となります。

選択的実行もすべてのファイルをビルドするわけではありません。コンパイルしなかったファイルについては、Tuistはそれ以降に変更がない限り、直近の完全実行から行数を取得します。これが、デフォルトブランチでの [完全実行](#full-runs) が重要である理由です。

`--skip-test-targets` や `-skip-testing` を使用して自分でスキップしたテストは引き継がれません。それらを除外した実行しかないコミットは、そのコミットの別の実行でそれらが実行されない限り、**不完全** となります。検疫によってスキップされたテストはカバレッジに含まれません。Tuistはそれらを引き継がず、そのためにコミットを **不完全** とマークすることもありません。

### 完全なコミットと不完全なコミット {#commit-status}

ダッシュボード上の各コミットにはステータスがあります。

| ステータス | 意味 |
| --- | --- |
| 進行中 | 実行がカバレッジを報告していますが、`tuist coverage complete` がそのコミットに対してまだ実行されていません。 |
| 完了 | コミットのスキームにおけるすべてのテストが実行されたか、引き継がれました。 |
| 不完全 | 一部のカバレッジを特定できなかったため、数値は下限値となります。 |
| 未計測 | コミットに対してカバレッジを報告した実行がありません。 |

ブランチのトレンドには完全なコミットのみが含まれます。コミットが不完全となるのは、例えば以下のケースです。

- 選択的テストが引き継げないターゲットをスキップした場合：以前の実行でそのターゲットのカバレッジが記録されていなかった、選択的実行がビルドしなかったファイルが最後の完全実行以降に変更された、または `Package.resolved`、`Project.swift`、`.xcconfig` など、すべてのターゲットに影響するファイルがコミットで変更された。
- 実行が `--skip-test-targets` または `-skip-testing` でテストをスキップし、そのコミットの他の実行でもそれらが実行されなかった。
- 実行がバイナリキャッシュからプレーンなバイナリとしてターゲットを取得した。
- スキームのすべての実行が `-only-testing` で絞り込まれていた。
- スキームのカバレッジが、未コミットの変更があるチェックアウトでのCI実行からのみ得られた。

## パフォーマンスへの影響 {#performance-impact}

カバレッジの収集はオーバーヘッドを追加します。これは主にテスト終了後、Xcodeがカバレッジレポートを書き込み、Tuistがカバレッジをエクスポートする間に発生します。テストのビルドと実行にかかる時間は、カバレッジなしの場合とほぼ同じです。インストルメント済みビルドは、DerivedDataおよびDebugバイナリキャッシュにより多くのディスクスペースを占有します。Releaseビルドとアーカイブは影響を受けません。

## 制限事項 {#limitations}

### カバレッジを収集するスキームのReleaseビルド {#release-builds}

スキームのテストアクションがカバレッジを収集する場合、Xcodeはそのスキーム用に `xcodebuild build` がソースからコンパイルするターゲットも、Releaseを含むあらゆる構成でインストルメントします。`xcodebuild archive` はこの設定を無視するため、アーカイブは決してインストルメントされません。アーカイブを配布するか、`.options(coverage: false)` を持つスキームからRelease製品をビルドしてください。

### その他のカバレッジツール {#other-coverage-tools}

`-enableCodeCoverage YES` は、Xcodeと同様に、実行がカバレッジを収集するかどうかだけを決定します。Tuistがキャッシュからインストルメント済みバイナリを読み取るようにはならないため、代わりに `Tuist.swift` オプションまたは `TUIST_COVERAGE_ENABLED` を使用してください。

他のカバレッジツールにデータを提供するには、`tuist test` に各実行のカバレッジをLCOVとして書き出させます。これはTuistがアップロードするカバレッジと同じもので、リポジトリ相対パスとバイナリキャッシュからのコードが含まれています。

```sh
tuist test --coverage-output-path coverage
```

各実行は `coverage/<result bundle name>.lcov` を書き出します。シャード化された実行のファイルは `lcov -a` で結合してください。このオプションにはカバレッジアップロードが有効である必要があります。

Xcode独自のカバレッジレポート、およびそれを読み取るツールは、その実行中にXcodeがビルドしたターゲットのみを含み、バイナリキャッシュから取得したコードは決して含みません。Tuistのアップロードは両方を計測します。Xcodeのレポートでターゲットのカバレッジを確認したい場合は、そのターゲットをソースからビルドするようにプロジェクトを生成してください。`tuist generate MyTarget` は `MyTarget` をソースとして保持し、残りをキャッシュから取得します。

## カバレッジのクエリ {#querying}

`tuist coverage` コマンドは、ダッシュボードに表示される内容を読み取ります。`--commit` なしの場合、`--branch` またはデフォルトブランチの最新の完全なコミットを読み取ります。

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

すべてがスクリプト用途で `--json` を受け付けます。同じデータは、<.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocolサーバー</.localized_link> を介してエージェントでも利用可能です。
