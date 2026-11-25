---
{
  "title": "ランナー",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist ランナーは、GitHub Actions、Buildkite、GitLab CI、Bitrise 向けのマネージド macOS および Linux ランナーで、コンピューティング環境と同一場所に配置されたキャッシュを備え、ローカルマシンと共有されます。"
}
---
# Runners {#runners}

Tuist Runnersは、GitHub Actions、Buildkite、GitLab CI、Bitriseのパイプライン向けに管理されたmacOSおよびLinuxランナーです。CIプロバイダーのホスト型マシンでジョブを実行する代わりに、Tuistの<.localized_link href="/guides/features/runners/profiles">profile</.localized_link>を指定すると、Tuistのフリート上で実行され、チームがすでに利用している<.localized_link href="/guides/features/cache">cache</.localized_link>の隣で動作します。ランナーエージェントのインストールやインフラの維持管理は不要です。マシンを変更する前にCIコストの内訳を確認するには、[CI costs](https://tuist.dev/solutions/ci-costs)をご覧ください。

導入は通常、ジョブの設定を1行変更するだけです。

::: code-group

```diff [GitHub Actions]
 jobs:
   build:
-    runs-on: macos-latest
+    runs-on: tuist-macos
     steps:
       - uses: actions/checkout@v4
       - run: tuist test
```

```diff [Buildkite]
 steps:
   - label: "Test"
     command: tuist test
     agents:
-      queue: macos
+      queue: tuist-macos
```
<!-- -->
:::

## Linux上のAndroidエミュレーター {#android-emulators}

Linuxランナーは、デフォルトで`/dev/kvm`を通じてハードウェアアクセラレーションによる仮想化を提供します。`tuist-linux`などの通常のLinux<.localized_link href="/guides/features/runners/profiles">profile</.localized_link>を使用して、Gradle Managed Devicesを含むx86_64 Androidエミュレーターを実行できます。デバイスへのアクセスには、特別なランナープロファイル、KVMセットアップアクション、権限の変更、または`sudo`は必要ありません。

ランナーイメージにはAndroid SDKが含まれています。デバイスを起動する前に、エミュレーターとそのランタイムライブラリをインストールしてください。すでに`pixel6`という名前のGradle Managed Deviceを定義しているプロジェクトの場合、GitHub Actionsジョブは次のようになります。

```yaml
jobs:
  android-test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - name: Install emulator dependencies
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y --no-install-recommends \
            libx11-6 libxcomposite1 libxcursor1 libxi6 libxtst6 libxrandr2 \
            libxrender1 libpulse0 libnss3 libxkbcommon-x11-0 libxcb-cursor0 \
            libasound2 libglu1-mesa
          "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" 'emulator'
      - name: Check hardware acceleration
        run: |
          test -r /dev/kvm && test -w /dev/kvm
          "$ANDROID_HOME/emulator/emulator" -accel-check
      - name: Run instrumented tests
        run: ./gradlew :app:pixel6DebugAndroidTest
```

Android Gradle Pluginが必要とするJavaバージョンを使用し、テストタスクをプロジェクトのmanaged-deviceタスクに置き換えてください。**x86_64**システムイメージを設定します。Gradleとエミュレーターの両方に十分なメモリを持つランナーシェイプを選択してください。並列実行されるデバイスは、ジョブのCPUおよびメモリ割り当てを共有します。

エミュレーターは通常のランナーユーザーとして実行してください。この例での`sudo`は、オペレーティングシステムパッケージのインストールにのみ使用されます。

エミュレーターはネストされた仮想化を使用するため、タイミングは物理的なAndroidデバイスと異なる場合があります。エミュレーターのベンチマークは、物理デバイスのパフォーマンスではなく、そのCI環境での測定値として扱ってください。

## 同時実行数の制限 {#concurrency-limits}

各アカウントには、macOS用とLinux用の独立したvCPUおよびメモリの同時実行数制限があります。Tuistがジョブを受け入れる前に、そのプラットフォームで現在実行中のすべてのジョブに対して、ジョブの<.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shape</.localized_link>をチェックします。vCPUとメモリの両方が残容量内に収まる場合にのみジョブが開始され、そうでない場合は容量が利用可能になるまでキューに入ったままになります。あるプラットフォームでの作業が、他のプラットフォームの容量を消費することはありません。

Airアカウントには固定の同時実行数制限があります。ProおよびEnterpriseアカウントは、標準的なmacOSジョブ6つ（48 vCPU / 144 GB）とLinuxで64 vCPU / 128 GBから始まり、Tuistは定期的な使用状況と、アクティブなランナーと同時に実行できない最近のキュー待ち作業に基づいて自動的に余裕を追加します。制限が低い間（最大12の標準的なmacOSジョブ、またはLinuxで128 vCPU / 512 GB）、すべてのキュー待ち作業を収容できるように、1時間に1回の頻度で増加することがあります。それを超えると、安全上限まで、1日あたり最大1回、かつ一度に最大50%ずつ増加するため、急激なバーストによって無制限の同時実行が許可されることはありません。自動調整は制限を増加させるのみです。既存の付与分と契約上の最小容量は保持されます。アカウントの制限が高くても、すぐに利用可能なマシンが保証されるわけではありません。

Runnersダッシュボードの**Concurrency**セクションには、1時間ごとのピーク時の許可されたvCPUおよびメモリ使用量が示され、各時間の開始時に把握されていた制限値を表す階段状の線が表示されます。赤いバーはその履歴閾値に達したことを示しますが、それだけでジョブが待機していたことを証明するものではありません。1時間以内の増加により、ピークがバケット開始線を超えることがあります。現在の制限値は各チャートの横に表示されます。履歴追跡が開始される前の期間には、想定される履歴値ではなく、制限線は表示されません。

ワークフローが安全上限でキューに入り続ける場合は、アカウントハンドル、プラットフォーム、予想される並列ワークロードを添えて[contact us](mailto:contact@tuist.dev)までご連絡ください。必要な容量を確認いたします。

## ネットワークアクセス {#network-access}

ジョブはパブリックインターネットへのアウトバウンド接続を開くことができます。プライベートアドレス範囲（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）はブロックされており、ランナーはインバウンド接続を受け付けません。

| プラットフォーム | アウトバウンドポート |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP)、443 (HTTPS)、およびDNS |
| macOS | 全ポート |

SSHは`git@`依存関係、SSHサブモジュール、デプロイキー、および`ssh`または`scp`デプロイを対象とします。Linuxワークフローで他のアウトバウンドポートが必要な場合は、[contact us](mailto:contact@tuist.dev)までご連絡ください。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHubを接続し、runs-onをTuistプロファイルに向け、フリート上で最初のジョブを実行します。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="クラスターを接続し、Tuistプロファイルに合わせてキューに名前を付け、ステップから対象とします。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLabを1回接続し、パイプラインタグで各ジョブのマシンを選択します。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="ワークスペースを接続し、セルフホスト型ランナープールのビルドをTuistプロファイルで実行します。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="独自のgitフォージまたはオーケストレーターから1つのリクエストでジョブを実行し、Webhookで追跡します。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="Profiles"
    details="ジョブから参照する名前付きマシンプロファイルで、プラットフォーム、サイズ、Xcodeバージョンを選択します。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="Images"
    details="macOSおよびLinuxランナーにプリインストールされている内容を確認します。Xcode、シミュレーター、Metalツールチェーン、Docker、Android SDKなど。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="Cache volumes"
    details="ジョブ間でXcode、モジュール、Gradleのキャッシュおよびその他のディレクトリを保持し、各実行ごとにプライベートな書き込み可能なコピーを提供します。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struoグラフアクション {#struo-graph-actions}

<a id="once-graph-actions"></a>

アカウントでリモート実行が有効になっており、サーバーが互換性のあるワーカー機能を告知している場合、StruoはTuistのLinuxワーカー上で対象となるグラフコマンドアクションを実行できます。これは上記のCIプロバイダーのジョブとは別個のアクションレベルの実行です。セットアップ、イメージ要件、互換性チェックについては<.localized_link href="/guides/features/runners/struo">Struoリモート実行</.localized_link>をご覧ください。

## Tuist Runnersを選ぶ理由 {#why-tuist-runners}

多くのCIランナープロバイダーは、より強力なマシンと永続的なキャッシュ（通常はCI実行にマウントし直される共有ボリューム）を提供することでジョブを高速化します。これは役立ちますが、ボリュームは単なるディスクであり、以前のCI実行が残したものをそのまま保持するだけです。ビルド実行場所の近くに最新のアーティファクトだけを保持するためにレプリケーションされるわけではなく、コードがビルドされる他の場所には届きません。

ビルドはもはや一か所で行われるものではありません。同じコードが開発者のラップトップ、CI全体、そして increasingly コーディングエージェントやその他の自動化環境によってコンパイルされます。Tuist Runnersが異なるのは、使用するビルドシステムに関係なく、それらの環境すべてがすでに読み書きしている同じ<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>を共有するためです。チームメンバーがラップトップでウォームアップしたアーティファクト、エージェントが生成したアーティファクト、または以前のビルドが残したアーティファクトはランナー上でヒットし、その逆も同様です。ウォームアップが必要な別のCIキャッシュはなく、速度向上はCIに限定されません。

さらに、キャッシュはランナーと同じプライベートネットワーク上に共存しているため、キャッシュの読み書きはパブリックインターネットを横断せず、内部かつコンピューティングリソースに近い状態で完結します。

まとめると：

- **すべての環境で共有。** ランナーは開発者マシン、CI、コーディングエージェントと同じキャッシュを読み書きするため、どこで行われた作業もあらゆる場所のキャッシュをウォームアップします。
- **コンピューティングリソースとの共存。** キャッシュトラフィックはパブリックイングレスを経由せず、ランナー隣の内部ネットワーク上に留まります。
- **統合された単一システム。** キャッシング、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>、<.localized_link href="/guides/features/test-sharding">テストシャーディング</.localized_link>、および<.localized_link href="/guides/features/build-insights">ビルドインサイト</.localized_link>はすべて同じプロジェクトとアカウントに対して実行されるため、ランナーはビルドデータの独立したサイロにはなりません。
