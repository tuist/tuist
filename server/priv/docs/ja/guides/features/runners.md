---
{
  "title": "ランナー",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist ランナーは、GitHub Actions と Buildkite 向けのマネージド macOS および Linux ランナーです。コンピューティングリソースと同一場所に配置されたキャッシュを備え、ローカルマシンとも共有されます。"
}
---
# ランナー {#runners}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、キャパシティを拡充中のため招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) でお知らせください。料金はまだ公開されていません。Runners が一般提供開始となる今年後半に発表予定です。


Tuist Runners は、GitHub Actions ワークフローや Buildkite パイプライン向けのマネージド macOS および Linux ランナーです。CI プロバイダーのホスト型マシンでジョブを実行する代わりに、ジョブを Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> に向けると、Tuist のフリート上で実行されます。チームがすでに利用している <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> と同じ場所に配置され、ランナーエージェントのインストールやインフラの管理は不要です。

導入は通常、ジョブの1行を変更するだけです。

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

Linux ランナーはデフォルトで `/dev/kvm` を介したハードウェアアクセラレーションによる仮想化を提供します。Gradle Managed Devices を含む x86_64 Android エミュレーターを実行するには、通常の Linux <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>（例: `tuist-linux`）を使用してください。デバイスにアクセスするために、特別なランナープロファイル、KVM セットアップアクション、権限変更、または `sudo` は必要ありません。

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

エミュレーターは通常のランナーユーザーとして実行してください。この例での `sudo` は、オペレーティングシステムのパッケージをインストールするためだけに使用されています。

エミュレーターはネストされた仮想化を使用するため、タイミングは物理的な Android デバイスと異なる場合があります。エミュレーターのベンチマークは、物理デバイスのパフォーマンスではなく、その CI 環境の測定値として扱ってください。

## 同時実行数の制限 {#concurrency-limits}

各アカウントには、macOS と Linux 向けの独立した vCPU およびメモリの同時実行数制限があります。Tuist がジョブを受け入れる前に、そのプラットフォームで現在実行中のすべてのジョブに対して、ジョブの <.localized_link href="/guides/features/runners/profiles#machine-shapes">マシンシェイプ</.localized_link> をチェックします。vCPU とメモリの両方が残りのキャパシティ内に収まる場合にのみジョブが開始され、そうでない場合はキャパシティが利用可能になるまでキューに残ります。あるプラットフォームでの作業が、他のプラットフォームのキャパシティを消費することはありません。

Runners ダッシュボードの **同時実行数** セクションには、毎時間のピーク時の承認済み vCPU およびメモリ使用量が表示されます。赤いバーは、その時間内のいつか使用量が設定された制限に達したことを意味します。使用量はその線を超えることはありません。いずれかのリソースの制限を超えるジョブはキューに残るためです。

現在の制限値は各チャートの横に表示されます。ワークフローが定期的に制限に達してキューで待機する時間が長い場合は、アカウントハンドル、プラットフォーム、予想される並列ワークロードを添えて [お問い合わせ](mailto:contact@tuist.dev) ください。必要なキャパシティを確認し、制限を引き上げるお手伝いをさせていただきます。

## ネットワークアクセス {#network-access}

ジョブはパブリックインターネットへのアウトバウンド接続を開くことができます。プライベートアドレス範囲（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）はブロックされており、ランナーはインバウンド接続を受け付けません。

| プラットフォーム | アウトバウンドポート |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP)、443 (HTTPS)、および DNS |
| macOS | すべてのポート |

SSH は `git@` 依存関係、SSH サブモジュール、デプロイキー、および `ssh` または `scp` デプロイをカバーします。Linux ワークフローで他のアウトバウンドポートが必要な場合は、[お問い合わせ](mailto:contact@tuist.dev) ください。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHub を接続し、runs-on を Tuist プロファイルに向け、フリート上で最初のジョブを実行します。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="クラスターを接続し、Tuist プロファイルに合わせてキューに名前を付け、ステップからターゲットを指定します。"
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
    title="プロファイル"
    details="ジョブから参照する名前付きマシンプロファイルで、プラットフォーム、サイズ、Xcode バージョンを選択します。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="キャッシュボリューム"
    details="Xcode、モジュール、Gradle のキャッシュおよびその他のディレクトリをジョブ間で保持し、各実行ごとにプライベートな書き込み可能なコピーを提供します。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Tuist Runners を選ぶ理由 {#why-tuist-runners}

ほとんどの CI ランナープロバイダーは、より強力なマシンと永続的なキャッシュ（通常は CI 実行にマウントされる共有ボリューム）を提供することで、ジョブを高速化します。これは役立ちますが、ボリュームは単なるディスクであり、以前の CI 実行が残したものをそのまま保持します。最新のアーティファクトだけをビルド実行場所の近くに保つためにレプリケートされることはなく、コードがビルドされる他の場所には届きません。

ビルドは今や一箇所で行われるものではありません。同じコードが開発者のラップトップ、CI、そして increasingly コーディングエージェントやその他の自動化環境でコンパイルされます。Tuist Runners が異なるのは、使用するビルドシステムに関係なく、それらの環境すべてが既に読み書きしている同じ <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を共有している点です。チームメンバーがラップトップでウォームアップしたアーティファクト、エージェントが生成したアーティファクト、または以前のビルドが残したアーティファクトはランナーでヒットし、その逆も同様です。別途ウォームアップが必要な CI キャッシュはなく、速度向上は CI に限定されません。

さらに、キャッシュはランナーと同じプライベートネットワーク上に配置されているため、キャッシュの読み書きはパブリックインターネットを通過せず、内部でコンピューティングリソースに近い場所で行われます。

まとめると：

- **すべての環境で共有。** ランナーは開発者マシン、CI、コーディングエージェントと同じキャッシュを読み書きするため、どこで行われた作業もすべての場所でキャッシュをウォームアップします。
- **コンピューティングリソースと同じ場所に配置。** キャッシュトラフィックはパブリックな入り口を経由せず、ランナーの隣にある内部ネットワーク上に留まります。
- **統合された単一システム。** キャッシング、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>、<.localized_link href="/guides/features/test-sharding">テストシャーディング</.localized_link>、および<.localized_link href="/guides/features/build-insights">ビルドインサイト</.localized_link>はすべて同じプロジェクトとアカウントに対して実行されるため、ランナーはビルドデータの独立したサイロにはなりません。
