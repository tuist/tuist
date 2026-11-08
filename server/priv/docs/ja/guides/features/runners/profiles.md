---
{
  "title": "プロファイル",
  "titleTemplate": ":title · ランナー · 機能 · ガイド · Tuist",
  "description": "ランナープロファイルは、Tuist Runner のプラットフォーム、サイズ、Ubuntu リリース、Xcode バージョンを選択するために runs-on で参照する、名前付きのマシンシェイプです。"
}
---
# プロファイル {#profiles}

**プロファイル**は、アカウントスコープで名前付きのマシンシェイプです。ワークフローの`runs-on`から参照すると、Tuist は一致するランナーにジョブをルーティングします。プロファイルを使えば、プラットフォーム、サイズ、Ubuntu リリース、Xcode バージョンといったインフラ選択を各ワークフローファイルに散らばらせることなく一箇所で管理でき、CI が参照できる安定したラベルを提供します。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

ラベルはプロファイル名に`tuist-`プレフィックスを付けたものです。名前が`macos`のプロファイルは`runs-on: tuist-macos`、名前が`linux-large`のプロファイルは`runs-on: tuist-linux-large`となります。マッチングは大文字小文字を区別しません。

## デフォルトプロファイル {#default-profiles}

Runners が有効なすべてのアカウントには、設定なしでフリートを利用できるように 2 つのプロファイルが用意されています。

{{runner_default_profiles_table}}

どちらも、そのプラットフォームのデフォルト<.localized_link href="/guides/features/runners/profiles#machine-shapes">シェイプ</.localized_link>を指しています。これらは**保護**されているため削除できず、ワークフローが依存するラベルは常に解決されます。シェイプや Xcode バージョンは変更でき、他のサイズや Xcode バージョン向けに追加のプロファイルを作成することもできます。

## マシンシェイプ {#machine-shapes}

Runner は macOS（Apple silicon、Mac フリート上で仮想化）および Linux で利用できます。各プロファイルは、以下のカタログから 1 つのマシンシェイプ、つまり`(vCPUs, memory)`のペアを固定します。

### Linux {#linux}

{{runner_linux_shapes_table}}

Linux プロファイルでは、macOS プロファイルが Xcode バージョンを選ぶのと同様に、**Ubuntu リリース**も選択します。

- **Ubuntu 24.04**（`ubuntu-24.04`）。新しいプロファイルのデフォルトです。
- **Ubuntu 22.04**（`ubuntu-22.04`）。引き続き必要なワークフロー向けです。GitHub は 22.04 のホストイメージを非推奨とし、2027 年 4 月 17 日に削除します。それまでに移行を計画してください。

プロファイルは変更するまで選択したリリースのまま維持されるため、新しいデフォルトが自動的にジョブを別の OS に移動することはありません。24.04 でビルドされたバイナリは新しい glibc（2.39）を必要とし、古いシステムでは実行できない場合があります。また、システム Python は仮想環境外での`pip install`を拒否します（PEP 668）。ランナーは GitHub ホストランナーと同様に`ImageOS`（`ubuntu24`または`ubuntu22`）を設定するため、セットアップアクションは適切なリリース向けのビルドを選択します。

すべての Linux プロファイルは、`/dev/kvm`を通じて<.localized_link href="/guides/features/runners#android-emulators">ハードウェアアクセラレーション対応の Android エミュレータ</.localized_link>をサポートしています。別途 KVM プロファイルは不要です。

### macOS {#macos}

{{runner_macos_shapes_table}}

大きな macOS シェイプはフリート内のマシン数が少ないため、そのシェイプを要求するジョブは、小さいシェイプの場合よりも開始までの待ち時間が長くなる可能性があります。ジョブが CPU 律速の場合は大きいシェイプを選び、それ以外はデフォルトシェイプのままにしてください。迷う場合は両方で実行し、ダッシュボードで所要時間を比較してください。

macOS プロファイルでは**Xcode バージョン**も固定します。バージョンにより、その Xcode がプリインストールされたランナーイメージが選択されるため、ジョブはツールチェーンが整った状態で開始されます。現在サポートされているバージョンは次のとおりです。

{{runner_macos_xcode_versions}}

> [!NOTE]
> ハードウェアや Xcode のリリースを追加するにつれてカタログは進化します。ダッシュボードの**新規プロファイル**フォームと`tuist runner profile catalog`には、アカウントで現在利用可能なシェイプ、Xcode バージョン、Ubuntu リリースが常に表示されるため、これらを信頼できる情報源として扱ってください。

macOS ランナーの名前には、実行中の macOS バージョン、プロファイルの Xcode バージョン、シェイプが含まれます。例：`tuist-macos-26.6-xcode-27.0-8vcpu-24gb-1a2b3c4d5e6f`。この名前は、GitHub 上のジョブの**Set up job**ステップと、Tuist ダッシュボードのジョブ詳細に表示されます。

## プロファイルの作成 {#creating-a-profile}

1. アカウントダッシュボードの**Runners → Profiles**セクションを開きます。
2. **新規プロファイル**を選択します。
3. 名前を付け、プラットフォームを選び、シェイプを選択します。Linux の場合は Ubuntu リリースも選択し、macOS の場合は Xcode バージョンを選択します。
4. 保存し、ワークフローから`runs-on: tuist-<name>`で参照します。

コマンドラインからプロファイルを管理することもできます。プロファイルの作成、変更、削除には、ダッシュボードと同様のアカウント管理者権限、または`account:runners:write`スコープを持つアカウントトークンが必要です。

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

エージェントは、<.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link>を通じて同じ操作を行えます。

例えば、8 vCPU / 32 GB シェイプで名前が`linux-large`のプロファイルの場合。

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
