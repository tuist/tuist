---
{
  "title": "プロファイル",
  "titleTemplate": ":title · ランナー · 機能 · ガイド · Tuist",
  "description": "ランナープロファイルは、Tuist Runnerのプラットフォーム、サイズ、Xcodeバージョンを選択するためにruns-onで参照する名前付きのマシン形状です。"
}
---
# プロファイル {#profiles}

**プロファイル**は、アカウントスコープの名前付きマシンシェイプです。ワークフローの`runs-on`から参照すると、Tuist は一致するランナーにジョブをルーティングします。プロファイルを使用することで、プラットフォーム、サイズ、Xcode バージョンなどのインフラストラクチャ選択をすべてのワークフローファイルに散在させるのではなく、一箇所に集約でき、CI が参照するための安定したラベルを提供します。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

ラベルは、プロファイル名に`tuist-`プレフィックスを付けたものです。名前が`macos`のプロファイルは`runs-on: tuist-macos`となり、名前が`linux-large`のプロファイルは`runs-on: tuist-linux-large`となります。マッチングは大文字小文字を区別しません。

## デフォルトプロファイル {#default-profiles}

Runners が有効なすべてのアカウントには、何も設定せずにフリートを利用できるよう、2 つのプロファイルが最初から用意されています。

{{runner_default_profiles_table}}

どちらも、各プラットフォームのデフォルト<.localized_link href="/guides/features/runners/profiles#machine-shapes">マシンシェイプ</.localized_link>を指します。これらは**保護**されており、削除できないため、ワークフローが依存するラベルは常に解決されます。マシンシェイプやXcodeバージョンは変更でき、他のサイズやXcodeバージョン用の追加プロファイルを作成することもできます。

## マシンシェイプ {#machine-shapes}

Runner は macOS（Apple シリコン、Mac フリート上で仮想化）および Linux で利用可能です。各プロファイルは、以下のカタログから 1 つのマシンシェイプ、つまり`(vCPUs, memory)`ペアを固定します。

### Linux {#linux}

{{runner_linux_shapes_table}}

すべてのLinuxプロファイルは、`/dev/kvm`を介して<.localized_link href="/guides/features/runners#android-emulators">ハードウェアアクセラレーション対応のAndroidエミュレータ</.localized_link>をサポートしています。別途KVMプロファイルは必要ありません。

### macOS {#macos}

{{runner_macos_shapes_table}}

大きな macOS シェイプはフリート内の少数のマシンで実行されるため、そのようなシェイプを要求するジョブは、小さなシェイプの場合よりも開始までにより長く待つ可能性があります。ジョブが CPU に制限されている場合は大きなシェイプを選び、それ以外の場合はデフォルトのシェイプを使用してください。不明な場合は、両方でジョブを実行し、ダッシュボードで所要時間を比較してください。

macOS プロファイルはまた、**Xcode バージョン**も固定します。このバージョンにより、その Xcode がプリインストールされたランナーイメージが選択されるため、ジョブはツールチェーンが既に整った状態で開始されます。現在サポートされているバージョン:

{{runner_macos_xcode_versions}}

> [!NOTE]
> ハードウェアや Xcode のリリースを追加するにつれて、カタログは進化していきます。ダッシュボードの**新規プロファイル**フォームと`tuist runner profile catalog`には、常にアカウントで現在利用可能なシェイプと Xcode バージョンが表示されるため、これらを信頼できる情報源として扱ってください。

macOS ランナーの名前には、実行中の macOS バージョン、プロファイルの Xcode バージョン、およびシェイプが表示され、例えば`tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`のようになります。この名前は、GitHub 上のジョブの**ジョブのセットアップ**ステップおよび Tuist ダッシュボードのジョブ詳細に表示されます。

## プロファイルの作成 {#creating-a-profile}

1. アカウントダッシュボードの**Runners → Profiles**セクションを開きます。
2. **新規プロファイル**を選択します。
3. 名前を付け、プラットフォームを選び、シェイプを選択します。macOS の場合は、Xcode バージョンも選択します。
4. 保存し、ワークフローから`runs-on: tuist-<name>`で参照します。

コマンドラインからプロファイルを管理することもできます。プロファイルの作成、変更、削除には、ダッシュボードと同様のアカウント管理権限、または`account:runners:write`スコープを持つアカウントトークンが必要です。

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

エージェントは、<.localized_link href="/guides/features/agentic-coding/mcp">MCPサーバー</.localized_link>を通じて同じ操作を行えます。

例えば、8 vCPU / 32 GB シェイプ上の名前が`linux-large`のプロファイル:

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

または、Xcode `26.4.1`に固定された名前が`xcode-26-4`の macOS プロファイル。これにより、デフォルトの`macos`プロファイルが最新を追跡している間、ジョブを古いツールチェーンで実行できます。

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
