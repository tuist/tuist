export default {
  home: {
    hero: {
      eyebrow: {
        en: "蔵 / A STOREHOUSE FOR YOUR ARTIFACTS",
        ja: "蔵 / あらゆる成果物のためのストアハウス",
      },
      title: {
        en: "A low-latency cache mesh shaped like a modern storehouse.",
        ja: "現代の蔵のように設計された、低レイテンシなキャッシュメッシュ。",
      },
      body: {
        en: "Kura keeps your artifacts and metadata close to the work, whether they come from builds, tests, or anything else. Reads stay local, writes become durable immediately, and replication moves in the background without turning the hot path into ceremony.",
        ja: "Kura は、ビルドでもテストでも、あらゆる成果物とメタデータを作業のすぐそばに置きます。読み取りはローカルに留まり、書き込みはすぐに永続化され、複製はホットパスを重くせず背後で進みます。",
      },
      note: {
        en: "The name comes from 蔵: a place built to protect value, survive seasons, and stay ready when the work returns.",
        ja: "名前の由来は「蔵」です。価値あるものを守り、季節を越えて保ち、必要なときにすぐ差し出せる場所を意味します。",
      },
      chips: [
        {
          en: "Decentralized",
          ja: "非中央集権",
          desc: {
            en: "No leader, no central coordinator. Every node accepts writes for its own clients and replicates to its peers in the background, so you can run it close to every team, in any region you like.",
            ja: "リーダーも中央の調整役もありません。どのノードも自分のクライアントの書き込みを受け付け、背後でピアへ複製します。どのチームの近くにも、好きなリージョンにも配置できます。",
          },
        },
        {
          en: "Client-agnostic",
          ja: "クライアント非依存",
          desc: {
            en: "Drop it in beside the build and test systems you already use, or reach for the generic API to wire up any other client. Kura stays out of the way of whatever produced the artifact.",
            ja: "すでに使っているビルド・テストシステムの隣に置くだけ。汎用 API を使えば、他のどんなクライアントも接続できます。Kura は成果物が何で作られたかを問いません。",
          },
        },
        {
          en: "Yours to run",
          ja: "自分で動かせる",
          desc: {
            en: "Open source under the MIT license and fully self-hosted. It runs on infrastructure you own, so your artifacts and cache traffic never leave your control.",
            ja: "MIT ライセンスのオープンソースで、完全に自己ホスト型。自分が所有・管理するインフラ上で動くため、成果物やキャッシュのやり取りが管理下から離れることはありません。",
          },
        },
      ],
      panelTitle: {
        en: "What the storehouse keeps",
        ja: "蔵が保つもの",
      },
      panelBody: {
        en: "Artifacts on local disk. Metadata in RocksDB. Replication intent in a durable outbox.",
        ja: "成果物はローカルディスクへ。メタデータは RocksDB へ。複製の意思は耐久性のあるアウトボックスへ。",
      },
      panelItems: [
        {
          en: "Each region writes for its own clients.",
          ja: "各リージョンは自分のクライアントのために書き込みます。",
        },
        {
          en: "Bootstrap warms new peers from healthy nodes.",
          ja: "ブートストラップは健全なノードから新しいピアを温めます。",
        },
        {
          en: "Readiness follows actual warm-up, not hope.",
          ja: "readiness は期待ではなく実際のウォームアップに従います。",
        },
      ],
    },
    why: {
      title: {
        en: "Why we built Kura",
        ja: "なぜ Kura を作ったのか",
      },
      intro: {
        en: "The work outgrew the machine, and the machine stopped staying put.",
        ja: "仕事は一台のマシンを越えて広がり、そのマシンさえ一つの場所にとどまらなくなった。",
      },
      story: {
        en: [
          "At Tuist we spend our days making builds and tests faster, and lately we have watched the shape of that work change. Coding agents now fan out dozens of builds and tests at once, and a single host runs out of cores and clock long before the team runs out of things to run. Where the work happens stopped being fixed too: it is CI today, a laptop tomorrow, an autonomous agent the day after.",
          "The usual advice is to rent a bigger runner or lean on a CI vendor's cache. Both tie how fast you move to someone else's environment, and both keep your artifacts far from where the work is actually happening. We did not want the speed of a team to depend on which CI it happened to be standing in.",
          "So we built Kura. A 蔵 is the storehouse Japanese households raised to keep what mattered safe and close through every season, always ready when hands returned to the work. Kura is that storehouse for software: a decentralized cache you run yourself, that keeps artifacts beside the work and replicates them quietly between regions, built for the parallelism coding agents have unlocked.",
          "A storehouse is only worth building if it can be trusted. So a write is acknowledged only once it is genuinely on disk: artifact bodies stream into packed, append-only segments while the metadata and replication intent commit together in a single synced step, leaving nothing that can disagree even after a crash. That packed-segment approach is drawn from content-addressable build caches like Buildbarn, and every node stays fully observable through its own traces, metrics, and logs.",
        ],
        ja: [
          "Tuist では日々、ビルドとテストを速くすることに取り組んでいます。そして最近、その仕事のかたちが変わってきたのを目にしてきました。コーディングエージェントは今や何十ものビルドとテストを一度に走らせ、一台のホストは、チームのやることが尽きるよりずっと早くコア数とクロックを使い果たします。仕事が起きる場所も固定ではなくなりました。今日は CI、明日は手元のマシン、明後日は自律エージェントです。",
          "よくある助言は、より大きなランナーを借りるか、CI ベンダーのキャッシュに頼ること。どちらも速さを他人の環境に縛りつけ、成果物を実際に仕事が起きる場所から遠ざけます。チームの速さが、たまたまどの CI にいるかで決まってほしくはありませんでした。",
          "そこで私たちは Kura を作りました。蔵とは、日本の家々がどの季節も大切なものを安全に、そして近くに保つために築いた保管庫です。人が仕事に戻るときにはいつでも備えています。Kura はソフトウェアのためのその蔵であり、自分で動かせる分散キャッシュとして成果物を仕事のそばに置き、リージョン間で静かに複製します。コーディングエージェントが解き放った並列性のために設計されています。",
          "蔵は、信頼できてこそ建てる価値があります。だから書き込みは、本当にディスクへ書かれて初めて確認されます。成果物本体はパック化された追記専用のセグメントへ流し込まれ、メタデータと複製の意図は同期された一度の処理でまとめてコミットされるため、クラッシュをまたいでも食い違うものは残りません。このパック化セグメントの方式は Buildbarn のようなコンテンツアドレス型ビルドキャッシュから着想を得ており、各ノードは自前のトレース・メトリクス・ログで完全に可観測なまま動きます。",
        ],
      },
    },
    hosted: {
      eyebrow: {
        en: "蔵 · Tended by Tuist",
        ja: "蔵 · Tuist が番をします",
      },
      title: {
        en: "Would rather not keep the storehouse yourself?",
        ja: "蔵の番は、私たちに任せませんか？",
      },
      body: {
        en: "Tuist will run Kura for you: a managed cache mesh placed close to your teams, kept warm, replicated, and watched. We go beyond hosting, layering on insights and tools that help you keep optimizing the rest of your development setup, so builds get fast and stay that way.",
        ja: "Tuist が Kura をマネージドで運用します。チームの近くに配置し、温かく保ち、複製し、見守ります。さらにホスティングにとどまらず、開発環境全体を最適化し続けるための知見とツールも提供し、ビルドを速く、速いまま保ちます。",
      },
      cta: {
        en: "Have Tuist host Kura",
        ja: "Tuist にホストしてもらう",
      },
    },
    languages: {
      title: {
        en: "Some of the languages Kura runs beside. It caches any artifact, not just code",
        ja: "Kura が共に走る言語の一部。コードに限らず、あらゆる成果物をキャッシュします",
      },
      caption: {
        en: "相棒 · the partner that speeds up compiling these languages",
        ja: "相棒 · これらの言語のコンパイルを加速する",
      },
      intro: {
        en: "Compiled-language builds are just one use case. Kura keeps any artifact close, whatever produced it: builds, tests, or anything else.",
        ja: "コンパイル言語のビルドは用途のひとつにすぎません。ビルドでもテストでも、何が生み出した成果物でも、Kura は近くに保ちます。",
      },
      items: [
        {
          name: "Swift",
          abbr: "Sw",
          color: "#f05138",
          ink: "#ffffff",
          note: {
            en: "Xcode build & module caches stay warm across the team.",
            ja: "Xcode のビルド・モジュールキャッシュをチーム全体で温かく保ちます。",
          },
        },
        {
          name: "Kotlin",
          abbr: "Kt",
          color: "#7f52ff",
          ink: "#ffffff",
          note: {
            en: "Gradle build cache for fast Android and JVM work.",
            ja: "Android と JVM の高速化のための Gradle ビルドキャッシュ。",
          },
        },
        {
          name: "Java",
          abbr: "Jv",
          color: "#e76f00",
          ink: "#ffffff",
          note: {
            en: "Gradle and Bazel caches without the round trips.",
            ja: "往復のない Gradle と Bazel のキャッシュ。",
          },
        },
        {
          name: "C / C++",
          abbr: "C++",
          color: "#00599c",
          ink: "#ffffff",
          note: {
            en: "Bazel and Buck2 remote execution caches over REAPI.",
            ja: "REAPI 経由の Bazel・Buck2 リモート実行キャッシュ。",
          },
        },
        {
          name: "TypeScript",
          abbr: "TS",
          color: "#3178c6",
          ink: "#ffffff",
          note: {
            en: "Nx task-graph caches for snappy monorepos.",
            ja: "軽快なモノレポのための Nx タスクグラフキャッシュ。",
          },
        },
        {
          name: "JavaScript",
          abbr: "JS",
          color: "#f0db4f",
          ink: "#3c322a",
          note: {
            en: "Metro bundler caches for React Native apps.",
            ja: "React Native アプリ向けの Metro バンドルキャッシュ。",
          },
        },
        {
          name: "Go",
          abbr: "Go",
          color: "#00add8",
          ink: "#ffffff",
          note: {
            en: "Bazel remote caches keep large builds quick.",
            ja: "大きなビルドを速く保つ Bazel リモートキャッシュ。",
          },
        },
        {
          name: "Rust",
          abbr: "Rs",
          color: "#b7410e",
          ink: "#ffffff",
          note: {
            en: "The language Kura itself is lovingly built in.",
            ja: "Kura 自身が愛を込めて書かれている言語です。",
          },
        },
      ],
    },
    blog: {
      title: {
        en: "From the team building Kura",
        ja: "Kura を作るチームから",
      },
      intro: {
        en: "Notes on the thinking behind Kura, and the small decisions that make a storehouse worth trusting.",
        ja: "Kura の背景にある考え方と、蔵を信頼に足るものにする小さな判断についての記録です。",
      },
      cta: {
        en: "Read the blog",
        ja: "ブログを読む",
      },
    },
  },
  blogIndex: {
    eyebrow: {
      en: "BLOG · FIELD NOTES",
      ja: "ブログ · 現場のノート",
    },
    title: {
      en: "Notes from the team building Kura.",
      ja: "Kura を作るチームの覚え書き。",
    },
    intro: {
      en: "Occasional writing on the thinking behind Kura: keeping caches close to the work, replicating without a leader, and the small decisions that make a storehouse worth trusting.",
      ja: "Kura の背景にある考え方についての、折にふれた記録です。キャッシュを仕事の近くに保つこと、リーダーなしで複製すること、そして蔵を信頼に足るものにする小さな判断について。",
    },
  },
};

