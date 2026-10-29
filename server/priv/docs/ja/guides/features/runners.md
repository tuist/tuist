---
{
  "title": "Runners",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Tuist Runners are managed macOS and Linux runners for GitHub Actions and Buildkite, with a cache colocated next to the compute and shared with your local machines."
}
---
# Runners {#runners}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runnersは現在、キャパシティを拡大中のため招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティSlack](https://slack.tuist.dev)でご連絡ください。価格情報はまだ公開されていません。Runnersが一般提供開始となる今年後半に発表予定です。


Tuist Runnersは、GitHub ActionsワークフローやBuildkiteパイプライン向けの管理されたmacOSおよびLinuxランナーです。CIプロバイダーのホスト型マシンでジョブを実行する代わりに、ジョブをTuistの<.localized_link href="/guides/features/runners/profiles">プロフィール</.localized_link>に向けると、Tuistのフリート上で実行され、チームがすでに利用している同じ<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>の隣で動作します。ランナーエージェントのインストールやインフラの維持管理は不要です。

導入は通常、ジョブへの1行の変更で済みます。

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

Linuxランナーはデフォルトで`/dev/kvm`を通じてハードウェアアクセラレーションによる仮想化を提供します。通常のLinux<.localized_link href="/guides/features/runners/profiles">プロフィール</.localized_link>（例：`tuist-linux`）を使用して、Gradle Managed Devicesを含むx86_64 Androidエミュレーターを実行できます。デバイスにアクセスするために、特別なランナープロフィール、KVMセットアップアクション、権限変更、または`sudo`は必要ありません。

ランナーイメージにはAndroid SDKが含まれています。デバイスを起動する前に、エミュレーターとそのランタイムライブラリをインストールしてください。`pixel6`という名前のGradle Managed Deviceがすでに定義されているプロジェクトの場合、GitHub Actionsジョブは次のようになります。

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

Android Gradle Pluginが必要とするJavaバージョンを使用し、テストタスクをプロジェクトのmanaged-deviceタスクに置き換えてください。**x86_64**システムイメージを設定してください。Gradleとエミュレーターの両方に十分なメモリを備えたランナーシェイプを選択してください。同時実行されるデバイスは、ジョブのCPUおよびメモリ割り当てを共有します。

エミュレーターは通常のランナーユーザーとして実行してください。この例での`sudo`は、オペレーティングシステムパッケージのインストールのためにのみ使用されています。

エミュレーターはネステッド仮想化を使用するため、タイミングは物理的なAndroidデバイスとは異なる場合があります。エミュレーターのベンチマークは、物理デバイスのパフォーマンスではなく、そのCI環境の測定値として扱ってください。

## 同時実行数の制限 {#concurrency-limits}

各アカウントには、macOSとLinuxそれぞれに対して独立したvCPUおよびメモリの同時実行数制限があります。Tuistがジョブを受け入れる前に、そのプラットフォームで現在実行中のすべてのジョブに対して、ジョブの<.localized_link href="/guides/features/runners/profiles#machine-shapes">マシンシェイプ</.localized_link>をチェックします。ジョブは、vCPUとメモリの両方が残りのキャパシティ内に収まる場合にのみ開始されます。そうでない場合は、キャパシティが利用可能になるまでキューに入ったままになります。一方のプラットフォームでの作業が他方のプラットフォームのキャパシティを消費することはありません。

Runnersダッシュボードの**同時実行数**セクションには、1時間ごとのピーク時の承認済みvCPUおよびメモリ使用量が表示されます。赤いバーは、その時間の間に使用量が設定された制限に達したことを意味します。使用量はその線を超えることはありません。いずれかのリソースの制限を超えるジョブはキューに入ったままになるためです。

現在の制限値は各チャートの横に表示されます。ワークフローが定期的に制限値に達してキューで待機する時間が長い場合は、アカウントハンドル、プラットフォーム、想定される並列ワークロードを添えて[お問い合わせ](mailto:contact@tuist.dev)ください。必要なキャパシティを確認し、制限値の引き上げをサポートいたします。

## ネットワークアクセス {#network-access}

ジョブはパブリックインターネットへのアウトバウンド接続を開くことができます。プライベートアドレス範囲（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）はブロックされており、ランナーはインバウンド接続を受け付けません。

| プラットフォーム | アウトバウンドポート |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP)、443 (HTTPS)、およびDNS |
| macOS | すべてのポート |

SSHは`git@`依存関係、SSHサブモジュール、デプロイキー、および`ssh`または`scp`デプロイを対象とします。Linuxワークフローで他のアウトバウンドポートが必要な場合は、[お問い合わせ](mailto:contact@tuist.dev)ください。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHubを接続し、runs-onをTuistプロフィールに向け、フリート上で最初のジョブを実行します。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="クラスターを接続し、Tuistプロフィールの名前を付けたキューを作成し、ステップからそれをターゲットにします。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLabを一度接続し、パイプラインタグで各ジョブのマシンを選択します。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="プロフィール"
    details="ジョブから参照する名前付きのマシンプロフィールで、プラットフォーム、サイズ、Xcodeバージョンを選択します。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="キャッシュボリューム"
    details="Xcode、モジュール、Gradleのキャッシュやその他のディレクトリをジョブ間で保持し、各実行ごとにプライベートな書き込み可能なコピーを提供します。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Tuist Runnersを選ぶ理由 {#why-tuist-runners}

ほとんどのCIランナープロバイダーは、より強力なマシンと永続的なキャッシュ（通常はCI実行にマウントされる共有ボリューム）を提供することでジョブを高速化します。これは役立ちますが、ボリュームは単なるディスクであり、以前のCI実行が残したものをそのまま保持します。ビルド実行場所に最新のアーティファクトだけを近づけるために複製されることはなく、コードがビルドされる他の場所には決して届きません。

ビルドはもはや一か所で行われるものではありません。同じコードが開発者のラップトップ、CI全体、そして increasingly コーディングエージェントやその他の自動化環境でコンパイルされます。Tuist Runnersが異なるのは、使用するビルドシステムにかかわらず、それらの環境すべてがすでに読み書きしている同じ<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>を共有している点です。同僚がラップトップでウォームアップしたアーティファクト、エージェントが生成したアーティファクト、または以前のビルドが残したアーティファクトはランナーでヒットし、その逆も同様です。別途CIキャッシュをウォームアップする必要はなく、速度向上はCIに限定されません。

さらに、キャッシュは同じプライベートネットワーク上でランナーと同一場所に配置されているため、キャッシュの読み書きはパブリックインターネットを横断せず、内部にとどまり、コンピューティングリソースの近くで行われます。

まとめると：

- **すべての環境で共有。** ランナーは、開発者マシン、CI、コーディングエージェントと同じキャッシュを読み書きするため、どこで行われた作業もすべての場所のキャッシュをウォームアップします。
- **コンピューティングリソースと同一場所に配置。** キャッシュトラフィックはパブリックなイングレスを経由せず、ランナーの隣にある内部ネットワーク上に留まります。
- **追加機能ではなく、統合されたシステム。** キャッシング、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>、<.localized_link href="/guides/features/test-sharding">テストシャーディング</.localized_link>、および<.localized_link href="/guides/features/build-insights">ビルドインサイト</.localized_link>はすべて同じプロジェクトとアカウントに対して実行されるため、ランナーはビルドデータの独立したサイロにはなりません。
