---
{
  "title": "Profiles",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Runner profiles are named machine shapes you reference from runs-on to choose a platform, size, and Xcode version for Tuist Runners."
}
---
# プロファイル {#profiles}

**プロファイル**は、アカウントスコープで名前付きのマシンシェイプです。ワークフローの`runs-on`から参照すると、Tuist は一致するランナーにジョブをルーティングします。プロファイルを使用することで、インフラストラクチャの選択（プラットフォーム、サイズ、Xcode バージョン）をすべてのワークフローファイルに散在させるのではなく、一箇所に集約でき、CI が参照するための安定したラベルを提供します。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

ラベルは、プロファイル名に`tuist-`プレフィックスを付けたものです。名前が`macos`のプロファイルは`runs-on: tuist-macos`となり、名前が`linux-large`のプロファイルは`runs-on: tuist-linux-large`となります。マッチングは大文字と小文字を区別しません。

## デフォルトのプロファイル {#default-profiles}

Runners が有効になっているすべてのアカウントには、2 つのプロファイルが最初から用意されているため、何も設定せずにフリートを利用できます。

{{runner_default_profiles_table}}

どちらも、各プラットフォームのデフォルトの<.localized_link href="/guides/features/runners/profiles#machine-shapes">シェイプ</.localized_link>を指しています。これらは**保護**されているため、削除できず、ワークフローが依存するラベルは常に解決されます。シェイプや Xcode バージョンは変更でき、他のサイズや Xcode バージョン用の追加プロファイルを作成することもできます。

## マシンシェイプ {#machine-shapes}

ランナーは macOS（Apple シリコン、Mac フリート上で仮想化）および Linux で利用可能です。各プロファイルは、以下のカタログから 1 つのマシンシェイプ、つまり`(vCPUs, memory)`ペアを固定します。

### Linux {#linux}

{{runner_linux_shapes_table}}

すべての Linux プロファイルは、`/dev/kvm`を介して<.localized_link href="/guides/features/runners#android-emulators">ハードウェアアクセラレーション対応の Android エミュレータ</.localized_link>をサポートしています。別途 KVM プロファイルは必要ありません。

### macOS {#macos}

{{runner_macos_shapes_table}}

より大きな macOS シェイプはフリート内の少数のマシンで実行されるため、そのシェイプを要求するジョブは、より小さなシェイプの場合よりも開始までに時間がかかることがあります。ジョブが CPU 律速の場合は大きなシェイプを選び、それ以外の場合はデフォルトのシェイプのままにしてください。迷った場合は、両方でジョブを実行し、ダッシュボードで所要時間を比較してください。

macOS プロファイルは、**Xcode バージョン**も固定します。このバージョンにより、その Xcode がプリインストールされたランナーイメージが選択されるため、ジョブはツールチェーンがすでに整った状態で開始されます。現在サポートされているバージョンは次のとおりです。

{{runner_macos_xcode_versions}}

> [!NOTE]
> ハードウェアや Xcode のリリースを追加するにつれて、カタログは進化していきます。ダッシュボードの**新しいプロファイル**フォームと`tuist runner profile catalog`には、常にアカウントで現在利用可能なシェイプと Xcode バージョンが表示されるため、これらを信頼できる情報源として扱ってください。

macOS ランナーの名前には、実行中の macOS バージョン、プロファイルの Xcode バージョン、およびシェイプが表示されます。例えば`tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`です。この名前は、GitHub 上のジョブの**ジョブの設定**ステップと、Tuist ダッシュボードのジョブ詳細に表示されます。

## プロファイルの作成 {#creating-a-profile}

1. アカウントダッシュボードの**Runners → Profiles**セクションを開きます。
2. **新しいプロファイル**を選択します。
3. 名前を付け、プラットフォームを選び、シェイプを選択します。macOS の場合は、Xcode バージョンも選択します。
4. 保存し、その後ワークフローから`runs-on: tuist-<name>`で参照します。

コマンドラインからプロファイルを管理することもできます。プロファイルの作成、変更、削除には、ダッシュボードと同様にアカウント管理権限、または`account:runners:write`スコープを持つアカウントトークンが必要です。

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

エージェントは、<.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link>を介して同じ操作を行えます。

例えば、8 vCPU / 32 GB のシェイプ上で名前が`linux-large`のプロファイルの場合。

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

あるいは、Xcode `26.4.1`に固定された名前が`xcode-26-4`の macOS プロファイルを使用すれば、デフォルトの`macos`プロファイルが最新を追跡している間、ジョブを古いツールチェーンで実行できます。

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
