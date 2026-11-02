---
{
  "title": "ランナー",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist ランナーは、GitHub Actions と Buildkite 向けのマネージド macOS および Linux ランナーで、コンピューティング環境の隣に配置されたキャッシュを備え、ローカルマシンと共有されます。"
}
---
# ランナー {#runners}

> [!IMPORTANT]
> **招待制**
>
> Tuist Runners は現在、キャパシティ拡張に伴い招待制となっています。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。料金プランはまだ公開されていません。Runners が一般提供開始となる今年後半に発表予定です。


Tuist Runners は、GitHub Actions ワークフローや Buildkite パイプライン向けのマネージド macOS および Linux ランナーです。CI プロバイダーのホスト型マシンでジョブを実行する代わりに、ジョブを Tuist の <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link> に向けると、Tuist のフリート上で実行されます。チームがすでに利用している同じ <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> の隣で動作し、ランナーエージェントのインストールやインフラの維持管理は不要です。

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

## Linux 上の Android エミュレーター {#android-emulators}

Linux ランナーはデフォルトで `/dev/kvm` を介したハードウェアアクセラレーションによる仮想化を提供します。Gradle Managed Devices を含む x86_64 Android エミュレーターを実行するには、通常の Linux <.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>（例：`tuist-linux`）を使用してください。デバイスにアクセスするために、特別なランナープロファイル、KVM 設定アクション、権限変更、または `sudo` は必要ありません。

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

Android Gradle Plugin が必要とする Java バージョンを使用し、テストタスクをプロジェクトの managed-device タスクに置き換えてください。**x86_64** システムイメージを設定してください。Gradle とエミュレーターの両方に十分なメモリを備えたランナーシェイプを選択してください。同時実行されるデバイスは、ジョブの CPU およびメモリ割り当てを共有します。

エミュレーターは通常のランナーユーザーとして実行してください。この例での `sudo` は、OS パッケージのインストールのためにのみ使用されています。

エミュレーターはネストされた仮想化を使用するため、タイミングは物理的な Android デバイスと異なる場合があります。エミュレーターのベンチマークは、物理デバイスのパフォーマンスではなく、その CI 環境の測定値として扱ってください。

## 同時実行数の制限 {#concurrency-limits}

各アカウントには、macOS と Linux 向けに独立した vCPU およびメモリの同時実行数制限があります。Tuist がジョブを受け入れる前に、そのプラットフォームで現在実行中のすべてのジョブに対して、ジョブの <.localized_link href="/guides/features/runners/profiles#machine-shapes">マシンシェイプ</.localized_link> をチェックします。vCPU とメモリの両方が残りのキャパシティ内に収まる場合にのみジョブが開始され、そうでない場合はキャパシティが利用可能になるまでキューに入ったままになります。一方のプラットフォームでの作業が他方のプラットフォームのキャパシティを消費することはありません。

Runners ダッシュボードの **同時実行数** セクションには、毎時間のピーク時の許可された vCPU およびメモリ使用量が表示されます。赤いバーは、その時間中に使用量が設定された制限に達したことを意味します。制限を超えるリソースを必要とするジョブはキューに入ったままになるため、使用量が線を超えることはありません。

現在の制限値は各チャートの横に表示されます。ワークフローが定期的に制限に達してキューイング時間が発生する場合は、アカウントハンドル、プラットフォーム、および想定される並列ワークロードを記載して [お問い合わせ](mailto:contact@tuist.dev) ください。必要なキャパシティを確認し、制限引き上げをサポートします。

## ネットワークアクセス {#network-access}

ジョブはパブリックインターネットへの送信接続を開くことができます。プライベートアドレス範囲（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）はブロックされており、ランナーは受信接続を受け付けません。

| プラットフォーム | 送信ポート |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP)、443 (HTTPS)、および DNS |
| macOS | すべてのポート |

SSH は `git@` 依存関係、SSH サブモジュール、デプロイキー、および `ssh` または `scp` デプロイを対象とします。Linux ワークフローで他の送信ポートが必要な場合は、[お問い合わせ](mailto:contact@tuist.dev) ください。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHub を接続し、runs-on を Tuist プロファイルに向け、フリート上で最初のジョブを実行します。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="クラスターを接続し、Tuist プロファイルに合わせてキューに名前を付け、ステップからそれをターゲットにします。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLab を一度接続し、パイプラインタグで各ジョブのマシンを選択します。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="プロファイル"
    details="ジョブから参照する名前付きマシンプロファイルを使用して、プラットフォーム、サイズ、および Xcode バージョンを選択します。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="キャッシュボリューム"
    details="ジョブ間で Xcode、モジュール、Gradle のキャッシュおよびその他のディレクトリを保持し、各実行ごとにプライベートな書き込み可能なコピーを提供します。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Tuist Runners を選ぶ理由 {#why-tuist-runners}

ほとんどの CI ランナープロバイダーは、より強力なマシンと永続的なキャッシュ（通常は CI 実行にマウントバックされる共有ボリューム）を提供することでジョブを高速化します。これは役立ちますが、ボリュームは単なるディスクであり、以前の CI 実行が残したものをそのまま保持します。ビルド実行場所に最新のアーティファクトだけを近づけるために複製されることはなく、コードがビルドされる他の場所には決して届きません。

ビルドはもはや一箇所で行われるものではありません。同じコードが開発者のラップトップ、CI 全体、そして increasingly コーディングエージェントやその他の自動化環境でコンパイルされます。Tuist Runners が異なるのは、使用するビルドシステムに関係なく、それらの環境すべてがすでに読み書きしている同じ <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> を共有するためです。チームメンバーがラップトップでウォームアップしたアーティファクト、エージェントが生成したアーティファクト、または以前のビルドが残したアーティファクトはランナー上でヒットし、その逆も同様です。ウォームアップが必要な別の CI キャッシュはなく、速度向上は CI に限定されません。

さらに、キャッシュはランナーと同じプライベートネットワーク上に共存しているため、キャッシュの読み書きはパブリックインターネットを越えず、内部かつコンピューティングに近い場所で完結します。

まとめると：

- **すべての環境で共有。** ランナーは開発者マシン、CI、コーディングエージェントと同じキャッシュを読み書きするため、どこで行われた作業もあらゆる場所のキャッシュをウォームアップします。
- **コンピューティングと同一場所に配置。** キャッシュトラフィックはパブリックな入口を経由せず、ランナーに隣接する内部ネットワーク上に留まります。
- **単一のシステムであり、後付けではありません。** キャッシング、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>、<.localized_link href="/guides/features/test-sharding">テストシャーディング</.localized_link>、および<.localized_link href="/guides/features/build-insights">ビルドインサイト</.localized_link>はすべて同じプロジェクトとアカウントに対して実行されるため、ランナーはビルドデータの独立したサイロにはなりません。
