---
{
  "title": "ランナー",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Runners は、GitHub Actions、Buildkite、GitLab CI、Bitrise 向けのマネージド macOS および Linux ランナーで、コンピューティング環境の隣に配置されたキャッシュを備え、ローカルマシンと共有されます。"
}
---
# ランナー {#runners}

Tuist Runners は、GitHub Actions、Buildkite、GitLab CI、Bitrise のパイプライン向けに管理された macOS および Linux ランナーです。CI プロバイダーのホスト型マシンでジョブを実行する代わりに、Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> を指定すると、Tuist のフリート上で実行され、チームがすでに利用している <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> の隣で動作します。ランナーエージェントのインストールやインフラの維持は不要です。マシンを変更する前に CI 費用の内訳を確認するには、[CI コスト](https://tuist.dev/solutions/ci-costs) を参照してください。

導入は通常、ジョブの 1 行変更だけで済みます。

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

## Linux 上の Android エミュレーター {#android-emulators}

Linux ランナーはデフォルトで `/dev/kvm` を介したハードウェアアクセラレーション仮想化を提供します。通常の Linux <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>（例：`tuist-linux`）を使用して、Gradle Managed Devices を含む x86_64 Android エミュレーターを実行できます。デバイスへのアクセスには、特別なランナープロファイル、KVM 設定アクション、権限変更、または `sudo` は必要ありません。

ランナーイメージには Android SDK が含まれています。デバイスを起動する前に、エミュレーターとそのランタイムライブラリをインストールしてください。すでに `pixel6` という名前の Gradle Managed Device を定義しているプロジェクトの場合、GitHub Actions ジョブは次のようになります。

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

Android Gradle Plugin で必要な Java バージョンを使用し、テストタスクをプロジェクトの managed-device タスクに置き換えてください。**x86_64** システムイメージを設定してください。Gradle とエミュレーターの両方に十分なメモリを持つランナーシェイプを選択してください。並列実行されるデバイスは、ジョブの CPU とメモリの割り当てを共有します。

エミュレーターは通常のランナーユーザーとして実行してください。この例での `sudo` は、オペレーティングシステムパッケージのインストールにのみ使用されます。

エミュレーターはネストされた仮想化を使用するため、タイミングは物理的な Android デバイスと異なる場合があります。エミュレーターのベンチマークは、物理デバイスのパフォーマンスではなく、その CI 環境の測定値として扱ってください。

## 同時実行数の制限 {#concurrency-limits}

各アカウントには、macOS と Linux 向けの独立した vCPU およびメモリの同時実行数制限があります。Tuist がジョブを受け入れる前に、そのプラットフォームで現在実行中のすべてのジョブに対して、ジョブの <.localized_link href="/guides/features/runners/profiles#machine-shapes">マシンシェイプ</.localized_link> をチェックします。vCPU とメモリの両方が残容量内に収まる場合にのみジョブが開始され、そうでない場合は容量が利用可能になるまでキューに残ります。あるプラットフォームでの作業が、他のプラットフォームの容量を消費することはありません。

Air アカウントには固定の同時実行数制限があります。Pro および Enterprise アカウントでは、Tuist が定期的な使用状況と、アクティブなランナーと併設できない最近のキュー待ち作業に基づいて、自動的に余裕を追加します。自動調整は制限を増やす方向にのみ行われ、既存の付与分や契約上の最小容量は保持されます。増加は段階的であり、安全上限によって制限されるため、急激なバーストが無制限の同時実行を許可することはありません。アカウントの制限が高くても、すぐに利用可能なマシンが保証されるわけではありません。

Runners ダッシュボードの **同時実行数** セクションには、時間ごとの承認済み vCPU およびメモリのピーク使用量が表示され、各時間の開始時に既知だった制限値を示す階段状の線が描かれます。赤いバーはその歴史的な閾値に達したことを示しますが、それだけでジョブが待機していたことを証明するものではありません。時間内の増加により、ピークがバケット開始線を超えることがあります。現在の制限値は各チャートの横に表示されます。履歴追跡が開始される前の期間には、仮定された歴史的値ではなく、制限線は表示されません。

ワークフローが安全上限でキューに残り続ける場合は、アカウントハンドル、プラットフォーム、予想される並列ワークロードを添えて [お問い合わせ](mailto:contact@tuist.dev) ください。必要な容量を検討いたします。

## ネットワークアクセス {#network-access}

ジョブはパブリックインターネットへのアウトバウンド接続を開くことができます。プライベートアドレス範囲（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）はブロックされており、ランナーはインバウンド接続を受け付けません。

| プラットフォーム | アウトバウンドポート |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP)、443 (HTTPS)、および DNS |
| macOS | すべてのポート |

SSH は `git@` 依存関係、SSH サブモジュール、デプロイキー、および `ssh` または `scp` デプロイを対象とします。Linux ワークフローで他のアウトバウンドポートが必要な場合は、[お問い合わせ](mailto:contact@tuist.dev) ください。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHub を接続し、runs-on を Tuist プロファイルに向け、フリート上で最初のジョブを実行します。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="クラスターを接続し、Tuist プロファイルに合わせてキューに名前を付け、ステップから対象とします。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLab を一度接続し、パイプラインタグで各ジョブのマシンを選択します。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="ワークスペースを接続し、セルフホスト型ランナープールのビルドを Tuist プロファイルで実行します。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="独自の git フォージまたはオーケストレーターから 1 リクエストでジョブを実行し、Webhook で後続処理を行います。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="プロファイル"
    details="ジョブから参照する名前付きマシンプロファイルで、プラットフォーム、サイズ、Xcode バージョンを選択します。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="イメージ"
    details="macOS および Linux ランナーにプリインストールされている内容を確認します：Xcode、シミュレーター、Metal ツールチェーン、Docker、Android SDK など。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="キャッシュボリューム"
    details="ジョブ間で Xcode、モジュール、Gradle のキャッシュおよびその他のディレクトリを保持し、各実行ごとにプライベートな書き込み可能なコピーを提供します。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo グラフアクション {#struo-graph-actions}

<a id="once-graph-actions"></a>

アカウントでリモート実行が有効になっており、サーバーが互換性のあるワーカー機能を告知している場合、Struo は Tuist の Linux ワーカー上で対象となるグラフコマンドアクションを実行できます。これは上記の CI プロバイダージョブとは別個のアクションレベルの実行です。セットアップ、イメージ要件、および互換性チェックについては <.localized_link href="/guides/features/runners/struo">Struo リモート実行</.localized_link> を参照してください。

## Tuist Runners のメリット {#why-tuist-runners}

多くの CI ランナープロバイダーは、より強力なマシンと永続的なキャッシュ（通常は CI 実行にマウントされる共有ボリューム）を提供することでジョブを高速化します。これは役立ちますが、ボリュームは単なるディスクであり、以前の CI 実行が残したものをそのまま保持するだけです。ビルド実行場所に最新の成果物だけを近づけるためにレプリケートされるわけではなく、コードがビルドされる他の場所には届きません。

ビルドはもはや一箇所で行われるものではありません。同じコードが開発者のノートパソコン、CI 全体、そして increasingly コーディングエージェントやその他の自動化環境によってコンパイルされます。Tuist Runners が異なるのは、使用するビルドシステムに関係なく、それらの環境すべてが既に読み書きしている同じ <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を共有している点です。チームメンバーがノートパソコンでウォームアップした成果物、エージェントが生成した成果物、または以前のビルドが残した成果物はランナー上でヒットし、その逆も同様です。ウォームアップが必要な別の CI キャッシュはなく、速度向上は CI に限定されません。

さらに、キャッシュはランナーと同じプライベートネットワーク上に共存しているため、キャッシュの読み書きはパブリックインターネットを跨ぐことなく内部で、かつ計算リソースに近い状態で行われます。

まとめると：

- **すべての環境で共有。** ランナーは開発者マシン、CI、コーディングエージェントと同じキャッシュを読み書きするため、どこで行われた作業もあらゆる場所でキャッシュをウォームアップします。
- **計算リソースとの共存。** キャッシュトラフィックはパブリックイングレスを経由せず、ランナー隣の内部ネットワーク上に留まります。
- **統合された単一システム。** キャッシング、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>、<.localized_link href="/guides/features/test-sharding">テストシャーディング</.localized_link>、および <.localized_link href="/guides/features/build-insights">ビルドインサイト</.localized_link> はすべて同じプロジェクトとアカウントに対して実行されるため、ランナーはビルドデータの独立したサイロにはなりません。
