---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · コードカバレッジ · 機能 · ガイド · Tuist",
  "description": "バイナリキャッシュや選択的テストでスキップされたコードを含め、Tuistが生成したXcodeプロジェクトのファイルごとおよびコミットごとのコードカバレッジを測定します。"
}
---
# 生成された Xcode プロジェクト {#generated-xcode-project-code-coverage}

コードカバレッジは、テストが実行したコードの行を示します。Tuist は `tuist test` の各実行における行カバレッジをアップロードし、コミット内の複数の実行をプロジェクト全体、各ターゲット、および各ファイルごとに 1 つの数値に集約します。ダッシュボードの **コードカバレッジ** ページでは、コミットごとの結果とブランチごとの推移を確認できます。

<!-- @snippet: ./_xcode-requirements -->

Tuist が処理をスキップしても、この数値は正確さを保ちます。<.localized_link href="/guides/features/cache/module-cache">バイナリキャッシュ</.localized_link> から取得されるターゲットはカバレッジカウンター付きでビルドされるため、ソースからビルドした場合と同様にコードが計測されます。また、<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選択的テスト</.localized_link> でテストターゲットがスキップされた場合、そのターゲットは以前の実行で記録されたカバレッジを維持します。これは Tuist が各実行で記録する [ターゲットレベルのカバレッジ](#target-level-coverage) によって実現されます。

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

生成オプションを有効にすると:

- Tuist が生成するすべてのスキームのテストアクションはカバレッジを収集します。また、`coverage` を設定せずに定義したスキームのテストアクションも同様です。`.options(coverage: false)` または `.options(coverage: true)` を指定したスキームは、その設定値を維持します。テストプランは自身でカバレッジを決定します。Tuist が生成するテストプランの場合、`.testPlans(_:coverage:)` に `coverage: true` を渡してください。
- プロジェクト独自のターゲットは、Debug 構成においてカバレッジカウンター付きでバイナリキャッシュから読み込まれ、ウォームアップされます。詳細は [仕組み](#instrumented-binaries) を参照してください。

`TUIST_COVERAGE_ENABLED` および `TUIST_COVERAGE_UPLOAD` 環境変数（`1` または `0`）は、`enabled` および `upload` より優先されます。キャッシュをウォームアップするコマンドと読み取るコマンドの一貫性を保つため、単一のコマンドではなく、CI ワークフローなどの環境全体に対してこれらの変数を設定してください。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成オプションは、プロジェクトのターゲットのキャッシュキーと、テストターゲットの選択的テスト用ハッシュを変更します。キャッシュを共有するすべてのマシンで同じ値を使用し、環境（例: `Environment.isCI`）から導出しないようにしてください。カバレッジを無効にした実行は、カバレッジを有効にした実行のバイナリや選択的テストの結果を再利用しません。

### スキームを対象外にする {#leave-schemes-out}

一部のスィートはカバレッジの対象に含まれません。例えば、別のプロセスからアプリや CLI を操作する受け入れテストやエンドツーエンドテストは、カバレッジツールが見えないコードを実行するため、カバレッジを収集しても速度が低下するだけです。それらのスキームのテストアクションでカバレッジを無効にしてください。

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

このスキームは、`Tuist.swift` オプションや `TUIST_COVERAGE_ENABLED` の設定に関わらずカバレッジを無効のまま維持し、その実行結果はコミットのカバレッジに含まれません。カバレッジはスキームごとに収集されるため、特定のテストターゲットを対象外にするには、それを専用のスキームに移してください。

### テストを実行する {#run-your-tests}

通常通り `tuist test` でテストを実行してください。

```sh
tuist test
```

Tuist は、テスト結果とともに実行中に収集されたカバレッジをアップロードします。これには <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分割実行</.localized_link> や、`--without-building` を使用して別のジョブでビルドされた製品をテストする実行が含まれます。フォークからのプルリクエストを実行するジョブなど、Tuist にカバレッジを送信したくない場合は、`TUIST_COVERAGE_UPLOAD=0` を設定してください。

### CI で各コミットを完了させる {#complete-each-commit}

コミットのカバレッジ情報は、多くの場合複数のジョブ（スキームごと、シャードごと、またはプラットフォームごと）から提供されます。Tuist は最後に報告されたジョブを自動で検出できないため、明示的に通知する必要があります。コミットに関連するすべてのテストジョブが終了したら、それらすべてに依存するジョブで次のコマンドを実行してください。

```sh
tuist coverage complete
```

このコマンドは、チェックアウトまたは CI プロバイダーからコミット情報を読み取ります。別のコミットを指定するには `--commit <sha>` を渡してください。コミットが完了としてマークされるまで、そのカバレッジは **進行中** と表示され、ブランチの推移には含まれません。

### デフォルトブランチで全スィートを実行する {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 選択的テストは、スキップされたターゲットのカバレッジを引き継ぐための以前の実行が存在する場合にのみ、コミットのカバレッジを完全な状態に保ちます。デフォルトブランチでは、選択的テストなしで全テストを実行するスケジュールを設定してください。
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> マージごとに 1 回実行するのが理想的です。変更の少ないリポジトリであれば、毎日または毎週でも十分です。記録されたカバレッジは 31 日後に失効するため、それより頻繁に実行してください。

引き継がれたカバレッジは完全な実行に依存しています。完全な実行は、失効前に各ターゲットの記録済みカバレッジを更新し、選択的実行ではビルドされないファイルの最新の状態を Tuist に提供します。完全な実行の間に変更が多いリポジトリほど、選択的実行は変更されたファイルを多く検出し、そのコミットのカバレッジは **不完全** になりやすくなります。

## ターゲットレベルのカバレッジ {#target-level-coverage}

実行のカバレッジは、全体の実行内容を示すものであり、各テストターゲットが個別に実行した内容を示すものではありません。選択的テストでターゲットがスキップされた場合、Tuist はそのカバレッジを引き継ぐために、以前の実行でそのターゲットが実行した内容を把握する必要があります。

そのため、Tuist は各実行において、各テストターゲットが実行したファイルと行も記録します。これは Xcode が各テストプロセス用に書き出すカバレッジデータから読み取られるため、追加の設定やリンクは不要です。この記録は macOS および iOS シミュレーター上で行われ、実機では行われません。UI テストは、操作対象のアプリに関する情報を記録しません。これは、アプリのコードが独自のプロセスで実行されるためです。

## 仕組み {#how-it-works}

### インストルメント済みバイナリ {#instrumented-binaries}

バイナリキャッシュからのターゲットは事前ビルドされたバイナリであり、テスト実行はそのバイナリがカバレッジカウンター付きでビルドされている場合にのみコードを計測できます。カバレッジが有効な場合、バイナリキャッシュはプロジェクト独自のターゲットのインストルメント済み variant を保持し、すべてのコマンドがこの variant を読み取ってウォームアップします。

- **Debug 構成** ではインストルメント済み variant が使用されます。`tuist cache` がこれをウォームアップし、`tuist generate` および `tuist test` がこれを読み取ります。
- **Release 構成** では常にプレーンな variant が使用されるため、配布される製品にカバレッジカウンターが含まれることはありません。
- **外部パッケージ** は常にプレーンな variant を使用します。Tuist が計測するのは、あなた自身のリポジトリのコードのみです。

テストジョブと同じ環境でカバレッジを有効にしてキャッシュをウォームアップし、`tuist test` がインストルメント済みバイナリを見つけられるようにしてください。実行がカバレッジを収集しようとしても、キャッシュからプレーンなバイナリとしてターゲットを取得した場合、Tuist は警告を発し、そのコードは計測されません。詳細は <.localized_link href="/guides/features/cache/module-cache#code-coverage">モジュールキャッシュ</.localized_link> のドキュメントを参照してください。

### マシン間でのパス処理 {#paths-across-machines}

インストルメント済みバイナリは、ビルド時のチェックアウトに対する相対パスでソースパスを記録するため、CI でウォームアップされたバイナリは、どの開発者のマシン上でも正しいファイルを計測できます。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode キャッシュ</.localized_link> はプレフィックスマッピングによって同様に動作しますが、Xcode 自体のカバレッジレポートはマッピングされたパスを解決できないため、Tuist はカバレッジを収集するビルドでこれをデフォルトで無効にします。Xcode 27 以降では、`enableCaching` を有効にした状態で `prefixMapping: true` を設定することでこれを維持でき、カバレッジビルド間でコンパイル結果が共有されます。

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist のアップロードはマッピングされたパスを解決しますが、Xcode のカバレッジレポートや `xccov` はそれらのファイルを除外する場合があります。詳細は <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">プレフィックスマッピングを使用したカバレッジ</.localized_link> を参照してください。

### スキップされたテスト {#skipped-tests}

選択的テストは、以前の合格した実行が同じハッシュで既にテスト済みの場合、そのテストターゲットをスキップします。ハッシュはターゲットのソース、そのテスト、およびすべての依存関係を含むため、同じハッシュは同じコードに対する同じテストを意味します。Tuist は、以前の実行がそのターゲットに対して記録した [ターゲットレベルのカバレッジ](#target-level-coverage) を再利用します。もし記録されていなかった場合（例えば、当時カバレッジが無効だったか、実行が31日以上前である場合）、引き継ぐデータがなく、コミットは **不完全** となります。

選択的実行もまた、すべてのファイルをビルドするわけではありません。コンパイルされなかったファイルについては、ファイルがその後変更されていない限り、Tuist は直近の完全な実行からの行データを使用します。これが、デフォルトブランチでの [完全な実行](#full-runs) が重要な理由です。

`--skip-test-targets` や `-skip-testing` を使用して自分でスキップしたテストは引き継がれません。それらを除外した実行のみを持つコミットは、そのコミットの他の実行でそれらが実行されない限り **不完全** となります。検疫によってスキップされたテストはカバレッジに含まれません。Tuist はそれらを引き継がず、そのためにコミットを **不完全** とマークすることもありません。

### 完全および不完全なコミット {#commit-status}

ダッシュボード上の各コミットにはステータスがあります：

| ステータス | 意味 |
| --- | --- |
| 進行中 | 実行がカバレッジを報告していますが、`tuist coverage complete` がそのコミットに対してまだ実行されていません。 |
| 完了 | コミットのスキームのすべてのテストが実行されたか、引き継がれました。 |
| 不完全 | 一部のカバレッジを決定できなかったため、数値は下限値となります。 |
| 未計測 | コミットに対してカバレッジを報告した実行がありません。 |

ブランチのトレンドには完了したコミットのみが含まれます。コミットが不完全となるのは、例えば以下のケースです：

- 選択的テストが引き継げないターゲットをスキップした場合：以前の実行でそのターゲットのカバレッジが記録されていなかった、選択的実行がビルドしなかったファイルが最後の完全な実行以降に変更された、または `Package.resolved`、`Project.swift`、`.xcconfig` などすべてのターゲットに影響するファイルがコミットで変更された。
- 実行が `--skip-test-targets` または `-skip-testing` でテストをスキップし、そのコミットの他の実行でそれらが実行されなかった場合。
- 実行がバイナリキャッシュからプレーンなバイナリとしてターゲットを取得した場合。
- スキームのすべての実行が `-only-testing` で絞り込まれていた場合。
- スキームのカバレッジが、未コミットの変更があるチェックアウト上の CI 実行からのみ得られた場合。

## パフォーマンスへの影響 {#performance-impact}

カバレッジの収集はオーバーヘッドを追加します。主にテスト終了後、Xcode がカバレッジレポートを書き込み、Tuist がカバレッジをエクスポートする間に発生します。テストのビルドと実行にかかる時間は、カバレッジなしの場合とほぼ同じです。インストルメント済みビルドは、DerivedData および Debug バイナリキャッシュにより多くのディスク容量を消費します。Release ビルドおよびアーカイブは影響を受けません。

## 制限事項 {#limitations}

### カバレッジを収集するスキームの Release ビルド {#release-builds}

スキームのテストアクションがカバレッジを収集する場合、`xcodebuild build` はそのスキーム用にソースからコンパイルするターゲットを、Release を含むあらゆる構成でインストルメントします。`xcodebuild archive` はこの設定を無視するため、アーカイブは決してインストルメントされません。アーカイブを配布するか、`.options(coverage: false)` を指定したスキームから Release 製品をビルドしてください。

### その他のカバレッジツール {#other-coverage-tools}

`-enableCodeCoverage YES` は、Xcode と同様に、実行がカバレッジを収集するかどうかを決定するだけです。Tuist にキャッシュからインストルメント済みバイナリを読み取らせることはできないため、代わりに `Tuist.swift` オプションまたは `TUIST_COVERAGE_ENABLED` を使用してください。

別のカバレッジツールにデータを提供するには、`tuist test` に各実行のカバレッジを LCOV 形式で書き出させます。これは Tuist がアップロードするものと同じカバレッジであり、リポジトリ相対パスとバイナリキャッシュからのコードが含まれています：

```sh
tuist test --coverage-output-path coverage
```

各実行は `coverage/<result bundle name>.lcov` を書き出します。シャード化された実行のファイルは `lcov -a` でマージしてください。このオプションにはカバレッジのアップロードが有効になっている必要があります。

Xcode 自体のカバレッジレポート、およびそれを読み取るツールは、その実行で Xcode がビルドしたターゲットのみを含み、バイナリキャッシュから来たコードは決して含みません。Tuist のアップロードは両方を計測します。Xcode のレポートでターゲットのカバレッジを確認したい場合は、そのターゲットをソースからビルドするようにプロジェクトを生成してください：`tuist generate MyTarget` は `MyTarget` をソースとして保持し、残りはキャッシュから取得します。

## カバレッジのクエリ {#querying}

`tuist coverage` コマンドは、ダッシュボードに表示される内容を読み取ります。`--commit` なしの場合、`--branch` の最新の完了コミット、またはデフォルトブランチの最新完了コミットを読み取ります：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

テスト実行独自のカバレッジは `tuist test show <test-run-id>` で表示されます。

すべてがスクリプト用に `--json` を受け入れます。同じデータは、<.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol サーバー</.localized_link> を介してエージェントからも利用可能です。
