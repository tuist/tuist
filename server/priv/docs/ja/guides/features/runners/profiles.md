---
{
  "title": "プロファイル",
  "titleTemplate": ":title · Runners · 機能 · ガイド · Tuist",
  "description": "ランナープロファイルは、Tuist Runners のプラットフォーム、サイズ、Xcode バージョンを選択するために runs-on から参照する、名前付きのマシンシェイプです。"
}
---
# プロファイル {#profiles}

**プロファイル**は、アカウントスコープの名前付きマシンシェイプです。ワークフローの`runs-on`で参照すると、Tuist は一致するランナーにジョブをルーティングします。プロファイルを使用すると、プラットフォーム、サイズ、Xcode バージョンといったインフラストラクチャの選択を 1 か所に集約でき、すべてのワークフローファイルに散在させる必要がなくなります。また、CI が参照できる安定したラベルを提供します。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

ラベルは、プロファイル名に`tuist-`プレフィックスを付けたものです。名前が`macos`のプロファイルは`runs-on: tuist-macos`となり、名前が`linux-large`のプロファイルは`runs-on: tuist-linux-large`となります。マッチングは大文字と小文字を区別しません。

## デフォルトのプロファイル {#default-profiles}

Runners が有効になっているすべてのアカウントには、初期状態で 2 つのプロファイルが用意されており、設定なしでフリートを利用できます。

{{runner_default_profiles_table}}

どちらも、プラットフォームのデフォルト<.localized_link href="/guides/features/runners/profiles#machine-shapes">マシンシェイプ</.localized_link>を指します。これらは**保護**されており、削除できないため、ワークフローが依存するラベルは常に解決されます。マシンシェイプやXcodeのバージョンは変更でき、他のサイズやXcodeのバージョン用に追加のプロファイルを作成することもできます。

## マシンシェイプ {#machine-shapes}

Runner は macOS（Apple silicon、Mac フリート上で仮想化）および Linux で利用可能です。各プロファイルは、以下のカタログから 1 つのマシンシェイプ、つまり`(vCPUs, memory)`のペアを固定します。

### Linux {#linux}

{{runner_linux_shapes_table}}

すべてのLinuxプロファイルは、`/dev/kvm`を介して<.localized_link href="/guides/features/runners#android-emulators">ハードウェアアクセラレーション対応のAndroidエミュレータ</.localized_link>をサポートしています。別途KVMプロファイルは必要ありません。

### macOS {#macos}

{{runner_macos_shapes_table}}

大きな macOS シェイプはフリート内のマシン数が少ないため、そのシェイプを要求するジョブは、小さなシェイプの場合よりも開始までの待ち時間が長くなる可能性があります。ジョブが CPU に制約されている場合は大きなシェイプを選択し、それ以外の場合はデフォルトのシェイプを使用してください。不明な場合は、両方でジョブを実行し、ダッシュボードで所要時間を比較してください。

macOS プロファイルは、**Xcode バージョン**も固定します。このバージョンにより、その Xcode がプリインストールされたランナーイメージが選択されるため、ツールチェーンが整った状態でジョブが開始されます。現在サポートされているバージョンは次のとおりです。

{{runner_macos_xcode_versions}}

> [!NOTE]
> ハードウェアや Xcode のリリースを追加するにつれて、カタログは進化していきます。ダッシュボードの**新しいプロファイル**フォームと`tuist runner profile catalog`には、常にアカウントで現在利用可能なシェイプと Xcode バージョンが表示されるため、これらを信頼できる情報源として扱ってください。

macOS ランナーの名前には、実行中の macOS バージョン、プロファイルの Xcode バージョン、およびシェイプが表示されます。例：`tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`。この名前は、GitHub 上のジョブの**ジョブの設定**ステップと、Tuist ダッシュボードのジョブ詳細に表示されます。

## プロファイルの作成 {#creating-a-profile}

1. アカウントダッシュボードの**Runners → Profiles**セクションを開きます。
2. **新しいプロファイル**を選択します。
3. 名前を付け、プラットフォームを選び、シェイプを選択します。macOS の場合は、Xcode バージョンも選択します。
4. 保存し、ワークフローから`runs-on: tuist-<name>`で参照します。

コマンドラインからプロファイルを管理することもできます。プロファイルの作成、変更、削除には、ダッシュボードと同様にアカウント管理者権限、または`account:runners:write`スコープを持つアカウントトークンが必要です。

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

エージェントは、<.localized_link href="/guides/features/agentic-coding/mcp">MCPサーバー</.localized_link>を通じて同じ操作を実行できます。

例えば、8 vCPU / 32 GB シェイプ上で名前が`linux-large`のプロファイルの場合：

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

または、Xcode `26.4.1`に固定された名前が`xcode-26-4`の macOS プロファイルを使用すると、デフォルトの`macos`プロファイルが最新を追跡している間、古いツールチェーンでジョブを実行できます。

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
