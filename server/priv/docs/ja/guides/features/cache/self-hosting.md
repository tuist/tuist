---
{
  "title": "Self-hosted cache",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "Deploy self-hosted cache nodes and connect them to Tuist."
}
---

# セルフホスト型キャッシュ {#self-hosted-cache}

セルフホスト型キャッシュノードを使用すると、ビルド成果物とキャッシュメタデータを、ビルド出力を生成・消費するマシンの近くに保持できます。CI、開発者オフィス、リモートワークステーション、またはリージョナルなコンピューティングクラスター全体でキャッシュのレイテンシーが重要になる場合に使用してください。

目標は、中央キャッシュがたまたま近くにある単一の環境だけでなく、あらゆる場所で低レイテンシーのキャッシングを実現することです。各キャッシュノードはローカルディスクからの読み取りと書き込みを提供し、メッシュはピア間で成果物とメタデータを複製するため、他の場所でも時間とともに同じキャッシュの恩恵を受けることができます。

> [!NOTE]
> Tuist のセルフホスト型キャッシュノードは、Tuist の分散型キャッシュメッシュである [Kura](https://github.com/tuist/tuist/tree/main/kura) によって動作します。Kura はキャッシュノードのデータプレーンであり、キャッシュの読み取りと書き込みを提供し、ローカル状態をディスクに保存し、成果物とメタデータをピアノードに複製します。

## セルフホスト型キャッシュが Tuist とどのように連携するか {#how-self-hosted-cache-fits-with-tuist}

Tuist のマネージドキャッシュは `https://<account>.cache.tuist.dev` を使用します。セルフホスト型の Tuist サーバーでは、CLI はサーバーの `TUIST_CACHE_ENDPOINTS` 設定からキャッシュ URL を取得します。これをメインのキャッシュサーバーまたはロードバランサーの URL に設定してください。複数の URL が含まれている場合は、最初の URL が使用されます。

**ホストされた Tuist サーバー** に接続されたプライベート/カスタムキャッシュノードの場合、開発者シェルと CI で明示的なエンドポイントを設定してください:

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

このオーバーライドは両方のサーバータイプで優先され、セルフホスト型の Tuist サーバーではオプションです。Xcode キャッシュデーモンについては、設定後に `tuist setup cache` を再実行して、LaunchAgent が更新された環境を受け取るようにしてください。

セルフホスト型の Tuist サーバーは、静的な構成からエンドポイントを取得します。Tuist ホスト型サーバーでは、ノードは認証情報を使用して認証を行い、自身を登録します。まず以下の 2 つのセクションのいずれかを使用してノードをデプロイし、その後 [Tuist にノードを接続する](#connect-nodes-to-tuist) を参照してください。

## Kubernetes にデプロイする {#deploy-on-kubernetes}

Kura は、GitHub Container Registry 経由で Helm チャートとして配布されています。これは Kura を永続ボリュームを持つ `StatefulSet` としてデプロイし、ピア検出用のヘッドレスサービスと、HTTP および gRPC トラフィック用の通常のサービスを提供します。

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

同じクラスター内のセルフホスト型 Tuist サーバーの場合、メインのキャッシュエンドポイントを構成してください:

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

これにより、サーバーポッド内に `TUIST_CACHE_ENDPOINTS` が設定されます。開発者マシンと CI が到達できるアドレスを使用してください。上記のクラスターローカルなサービス名は、クラスター内で実行されているクライアントに適しています。

> [!IMPORTANT]
> すべての Kura ノードは独自の `KURA_DATA_DIR` を所有する必要があります。Kura はデータディレクトリに対してアプリケーションレベルのライターロックを取得し、それを所有するプロセスが正確に 1 つであることを想定しています。Kubernetes では、ポッドごとに 1 つの永続ボリュームを使用してください。Kubernetes 以外では、複数のプロセスを同じマウントディレクトリに向けないでください。

## Kubernetes なしでデプロイする {#deploy-without-kubernetes}

Kura は、VM またはベアメタルホスト上で通常のコンテナとしても実行できます。このモードでは、プロセスの監視、永続ストレージ、ルーティング、およびピア検出はあなたの責任となります。

最低限、各ノードには永続データディレクトリ、一時ディレクトリ、パブリックキャッシュポート（1 つのリスナーが HTTP キャッシュ API と REAPI gRPC の両方を提供）、内部ピア URL、そして静的なピアリストまたは検出メカニズムのいずれかが必要です:

```bash
docker run -d --name kura \
  -p 4000:4000 \
  -p 7443:7443 \
  -v /var/lib/kura:/var/cache/kura \
  -e KURA_PORT=4000 \
  -e KURA_INTERNAL_PORT=7443 \
  -e KURA_TENANT_ID=default \
  -e KURA_REGION=local \
  -e KURA_TMP_DIR=/var/cache/kura/tmp \
  -e KURA_DATA_DIR=/var/cache/kura \
  -e KURA_NODE_URL=http://kura-1.internal:7443 \
  -e KURA_PEERS=http://kura-1.internal:7443,http://kura-2.internal:7443 \
  ghcr.io/tuist/kura:<tag>
```

セルフホスト型の Tuist サーバーでは、開発者マシンと CI が到達できるメインのキャッシュ URL を構成してください:

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## ノードをロードバランサーの背後に配置する {#load-balancers}

クライアントは、HTTP と gRPC の両方に各キャッシュエンドポイント URL を使用します。HTTP はヘルスチェックと HTTP キャッシュ API に、gRPC はモジュールキャッシュと Bazel のリモートキャッシュに使用されます。クライアントと Kura の間のイングレス、ロードバランサー、または CDN は、同じホスト名とポートで両方を転送する必要があります。これはクライアントが受信するすべてのエンドポイントに適用されます。なぜなら、CLI は最も速く応答したものを選択するためです。gRPC が Kura に到達しない場合、CLI はリモートモジュールキャッシングが利用できないことを警告し、ローカルモジュールキャッシュのみを使用します。

これらのパスプレフィックスを HTTP/2 上の gRPC として Kura にルーティングし、その他すべてを HTTP としてルーティングしてください:

| パスプレフィックス | 使用者 |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | モジュールキャッシュ、Bazel |
| `/google.bytestream.` | モジュールキャッシュ、Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel ビルドイベント |

Kura は `KURA_PORT` でプレーンテキスト HTTP/2 (h2c) を受け入れ、`KURA_PUBLIC_TLS_CERT_PATH` と `KURA_PUBLIC_TLS_KEY_PATH` が設定されている場合、`KURA_HTTPS_PORT` で TLS 上の HTTP/2 を受け入れます。プロキシが入力.nginx のようにリクエスト間でアップストリーム接続を再利用する場合、`KURA_GATEWAY_GRPC_PORT` を設定し、代わりにそのポートに gRPC トラフィックを送信してください。これは gRPC のみを提供するため、HTTP/1.1 と gRPC リクエストが接続を共有することはありません。

gRPC ルートを以下のように構成してください:

- リクエストボディサイズ制限なし。アップロードは単一のリクエストで 1 つのファイルを送信し、最大 2 GiB です。
- リクエストとレスポンスのバッファリングをオフにします。
- 読み取り、送信、およびアイドルタイムアウトは少なくとも 300 秒に設定します。

Kura は gRPC ヘルスチェックサービスを提供しません。`/ready` で HTTP 経由でノードのヘルスチェックを行います。ロードバランサーが gRPC ヘルスチェックを必要とする場合、`/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` を呼び出し、gRPC ステータスコード `0` と `16` を受け入れます。承認が有効なノードは、トークンなしのリクエストに対して `16` (`UNAUTHENTICATED`) で応答します。

### ingress-nginx {#load-balancers-ingress-nginx}

Helm チャートを使用する場合、HTTP イングレスを `/` に維持し、同じホスト用に gRPC イングレスを追加します。TLS を宣言するのは HTTP イングレスのみです:

```yaml
service:
  gatewayGrpcPort: 4001

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: kura.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - kura.example.com
      secretName: kura-tls

grpcIngress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: kura.example.com
      paths:
        - path: /build\.bazel\.remote\.execution\.v2\.
          pathType: ImplementationSpecific
        - path: /google\.bytestream\.
          pathType: ImplementationSpecific
        - path: /build\.bazel\.remote\.asset\.v1\.
          pathType: ImplementationSpecific
        - path: /google\.devtools\.build\.v1\.
          pathType: ImplementationSpecific
```

### AWS Application Load Balancer {#load-balancers-aws-alb}

gRPC ターゲットグループには HTTPS リスナーが必要です。そのリスナーで:

1. デフォルトルールを、`KURA_PORT` 上のプロトコルバージョン `HTTP1` を持つターゲットグループに転送し、`/ready` で HTTP 経由でヘルスチェックを行います。
2. プロトコルバージョン `gRPC` の 2 番目のターゲットグループを作成し、`KURA_GATEWAY_GRPC_PORT` (または `KURA_PORT`) でプロトコル `HTTP` を使用するか、`KURA_HTTPS_PORT` でプロトコル `HTTPS` を使用します。ヘルスチェックは上記のように構成してください。
3. `/build.bazel.remote.execution.v2.*`、`/google.bytestream.*`、`/build.bazel.remote.asset.v1.*`、および `/google.devtools.build.v1.*` のパスパターンを 2 番目のターゲットグループに転送するルールを追加します。
4. ロードバランサーのアイドルタイムアウトを少なくとも 300 秒に引き上げます。

### CDN {#load-balancers-cdns}

ノードの前に配置される CDN は gRPC をサポートし、ファイアウォールルールで gRPC パスをブロックしてはいけません。クライアントは最大 2 MiB のチャンクで大きなアーティファクトをアップロードし、ノードがそれらを組み立てるため、大きなボディや長時間のアップロードを必要とするリクエストはありません。モジュールキャッシュと Xcode コンパイルキャッシュはこの動作を行い、Bazel は `--experimental_remote_cache_chunking` でビルドした場合にこれを行います（Bazel 8.7 および 9.1 以降）。このフラグがない場合、Bazel は各出力を単一のリクエストでアップロードするため、CDN も大きなリクエストボディと、最も遅いリンクで最大の出力に必要な時間がかかるアップロードを許可する必要があります。CDN がこれらの要件を満たせない場合は、それを回避するホスト名（例: DNS のみのレコード）をクライアントに提供してください。

#### Cloudflare {#load-balancers-cloudflare}

モジュールキャッシングは、どのプランでもプロキシされた Cloudflare ホスト名経由で機能します。ゾーン内では:

1. **ネットワーク** で **gRPC** を有効にします。
2. **SSL/TLS** で、暗号化モードを **Full** または **Full (strict)** に設定します。Cloudflare はポート 443 でオリジンに接続するため、オリジンはそこで TLS を提供し、ALPN を介して HTTP/2 をオファーする必要があります。
3. 上記の gRPC パスをブロックする WAF カスタムルールまたはマネージドルールがないことを確認してください。

Cloudflare は、オリジンが約 2 分間応答を開始しない場合にリクエストを終了します。`--experimental_remote_cache_chunking` なしの Bazel アップロードは最後のバイトが到着してから応答されるため、Cloudflare ではそれより長くかかるアップロードは失敗します。

## ノードを Tuist に接続 {#connect-nodes-to-tuist}

クライアントルーティングを構成し、ノードを Tuist に登録して、アドレス、準備状態、および使用状況がダッシュボードに表示されるようにします。

**セルフホスト型 Tuist サーバー** では、上記のデプロイメントセクションで示されているように、`TUIST_CACHE_ENDPOINTS` でエンドポイントを静的に宣言します。CLI は最初に構成された URL を使用します。`TUIST_CACHE_ENDPOINT` は個々のクライアントに対してその URL を上書きします。

**Tuist ホスト型サーバー** では、開発者シェルと CI で `TUIST_CACHE_ENDPOINT` を設定し、キャッシュリクエストをノードにルーティングします。各ノードは生成した資格情報で認証し、その後アドレスを登録して準備状態をダッシュボードに報告します。このセクションではノード登録について説明します。

> [!IMPORTANT]
> **エンタープライズプラン**
>
> セルフホスト型キャッシュノードはエンタープライズプランで利用可能です。以下で説明する **セルフホスト型サーバー** セクションは、そのプランのアカウントにのみ表示されます。

### ノード資格情報の生成 {#generate-a-node-credential}

Tuist ダッシュボードでアカウントを開き、**キャッシュ** に移動して **セルフホスト型サーバー** を見つけます。**資格情報の生成** を選択して、クライアント ID とシークレットを作成します。

この資格情報は、作成したアカウントのトラフィックのみを承認します。

シークレットは一度だけ表示され、ダイアログを閉じた後は回復できないため、ノードが読み取るシークレットストアに直接コピーしてください。資格情報の取り消しは、それを使用しているすべてのノードの認証を即座に停止するため、使用中のものを取り消す前に代替品を生成してください。

### 起動時のノード登録 {#enroll-the-node-on-boot}

登録はノードを立ち上げるための推奨方法です。`KURA_ENROLL_ON_BOOT` を設定し、ノードにその資格情報と独自のピア URL を指定します:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

ノードはローカルでキーペアを生成するため、秘密鍵が外部に出ることはなく、署名付きピア証明書、アカウント CA、テナント識別子、およびピアリストを受け取ります。これは手動で構成する必要のあるすべてです: 登録済みノードには `KURA_TENANT_ID`、`KURA_PEERS`、およびピア TLS 設定は不要です。

`KURA_INTERNAL_TLS_*` は未設定のままにしてください: 登録により、証明書マテリアルは `KURA_DATA_DIR` 下の `tls` ディレクトリに書き込まれます。これらのパスを設定するのは、登録ではなく証明書を供給する場合のみです（[キャッシュメッシュの構築](#build-a-cache-mesh) を参照）。

アカウントのメッシュに初めて参加するノードは、リングのサービスメンバーになる前に、アカウントの既存のキャッシュをプルします。データボリュームはキャッシュ全体に合わせてサイズ設定し、最初の参加は広域リンク上で時間がかかることを想定してください。ノードは追いつくまで `joining` を報告し、その後 `serving` を報告します。

### エンドポイントの公開 {#advertise-the-endpoint}

登録によりメッシュに参加します。登録はノードのクライアント向けアドレスと準備状態を Tuist に報告します。登録変数を設定します:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

ノードは 180 秒のリースに対して 60 秒ごとにハートビートを送信します。Tuist はリースが期限切れになると登録を利用不可とみなします。Tuist はノードを呼び出すことはないため、インターネットからではなく、クライアントから到達可能であれば十分です。

### ノードがサービス中であることを確認 {#verify-the-node-is-serving}

ダッシュボードの **キャッシュ** に戻ると、ノードはエンドポイント、リージョン、ステータス、および最後のハートビートとともに **登録済みノード** に表示されます。まったく表示されないノードは、登録エンドポイントに到達していないか、承認に失敗しています。表示されてから消えるノードは、ハートビートを停止したか、準備状態の報告を停止しています。

### テナント識別子をアカウントハンドルと一致させる {#match-the-tenant-identifier}

`KURA_TENANT_ID` は Tuist アカウントハンドルと一致する必要があります。コントロールプレーンは、ハートビートのテナントを資格情報から解決されたアカウントと比較し、不一致を `409 tenant_mismatch` で拒否するため、値が間違っているノードは認証に成功しても登録されません。

> [!IMPORTANT]
> Helm チャートとこのガイドの前半のコンテナ例の両方で、これを `default` にデフォルト設定しています。この値は、テナントがローカルラベルであるセルフホスト型 Tuist サーバーでは正しく、アカウント名を指定する必要がある Tuist ホスト型サーバーのアカウントでは誤っています。コントロールプレーンが値を提供するため、ノードを登録することでこの問題を完全に回避できます。

未設定の `KURA_TENANT_ID` はチェックをスキップしません。登録自体を無効にします: ノードはキャッシュトラフィックの提供を継続しますが、ダッシュボードには何も表示されず、エラーも報告されません。ノードが正常なのに **登録済みノード** に欠けている場合は、まずこの変数を確認してください。

### クライアントが到達できる公開 URL を選択 {#choose-an-advertised-url}

`KURA_ADVERTISED_HTTP_URL` および Tuist サーバーまたは CLI で構成されたキャッシュ URL には、クライアントが到達可能なアドレスを使用します。

内部専用のホスト名は、それを使用するように構成されたすべてのクライアントがその名前を解決して到達できる場合に適しています。異なるネットワーク上のクライアントの場合は、共有の到達可能なアドレスを使用するか、環境ごとに到達可能なキャッシュノードを構成してください。

## キャッシュメッシュの構築 {#build-a-cache-mesh}

キャッシュメッシュを使用すると、必要なコンピューティングリソースの近くにキャッシュ容量を配置できます。企業は、メインの CI ランナーの近くに 1 つのノードを、ヨーロッパの開発者の近くにもう 1 つのノードを、米国のオフィスや地域のビルドクラスターの近くにもう 1 つのノードを実行する場合があります。各ロケーションは最も近いノードに対して読み書きを行い、Kura はバックグラウンドでアーティファクトとメタデータを複製するため、他のロケーションでの後続のビルドが同じ出力を再利用できます。

メッシュは、ノードが Kura の内部ピアポートで相互に到達できる場合にのみ機能します。このピアプレーンは、Tuist クライアントが使用する公開キャッシュエンドポイントとは別です。Kura はこれを使用してメンバーシップを確認し、新しく参加したノードをバックフィルし、ローカル書き込みが受け入れられた後にアーティファクトを複製します。

ノードがリージョン、クラウド、VPC、オフィス、またはキャッシュデプロイメントに対して完全にプライベートではないネットワーク間で通信する場合、[mTLS](https://en.wikipedia.org/wiki/Mutual_authentication) でピアプレーンを保護することを強く推奨します。mTLS を有効にすると、Kura は構成された CA によって署名された証明書を提示するピアに対してのみ内部レプリケーションエンドポイントを提供します。ピア証明書は、ノードが相互に呼び出すために使用する DNS 名をカバーする必要があり、ピア URL は内部ポートで `https://` を使用する必要があります。

> [!NOTE]
> Tuist ホスト型コントロールプレーンに登録するノードは、登録中にピア証明書とアカウント CA を受け取るため、以下の手動手順は登録しないメッシュに適用されます。

たとえば、これはプライベート CA と、小規模なメッシュ内のすべてのノードでマウントできる 1 つのピア証明書を生成します。DNS 名を、`KURA_NODE_URL` および `KURA_PEERS` でノードが使用する内部名に置き換えてください。

```bash
mkdir -p kura-peer-tls
cd kura-peer-tls

openssl ecparam -genkey -name prime256v1 -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/CN=kura-peer-ca" \
  -out ca.pem

openssl ecparam -genkey -name prime256v1 -noout -out tls.key
openssl req -new -key tls.key \
  -subj "/CN=kura-peer" \
  -out peer.csr

cat > peer.ext <<'EOF'
subjectAltName = DNS:kura-0.kura-headless.kura.svc.cluster.local,DNS:kura-1.kura-headless.kura.svc.cluster.local,DNS:kura-2.kura-headless.kura.svc.cluster.local,DNS:kura-1.internal,DNS:kura-2.internal
extendedKeyUsage = serverAuth,clientAuth
keyUsage = digitalSignature,keyEncipherment
EOF

openssl x509 -req -in peer.csr \
  -CA ca.pem \
  -CAkey ca.key \
  -CAcreateserial \
  -out tls.crt \
  -days 730 \
  -sha256 \
  -extfile peer.ext
```

### ノード間のキャッチアップ {#catch-up-between-nodes}

メッシュに参加または再参加するノードは **バックフィル** を実行します: 各ピアのエントリを新しいものから順に走査し、不足しているものを取得します。一方、ライブレプリケーションは、ピアが表示されている間に行われた書き込みをカバーします。バックフィルパスは、ピアの最新のエントリから、ノードのセグメントリングのホライゾンと最後に完了したパスのうち古い方まで遡るため、ノードは最近のデータを保持することが保証されますが、必ずしもすべてを保持するわけではありません。`KURA_BACKFILL_MARGIN_PERCENT` は、ホライゾンがどの程度過去まで遡るかを設定します。

メッシュを実行する前に知っておくべき 2 つの結果があります:

- ノードは、セグメントリングが `KURA_BACKFILL_READY_RING_PERCENT` 満杯になった **か**、最初のバックフィルサイクルが安定した時点で `/ready` を報告し、その後プロセスの存続期間中はレディ状態が維持されます。後続のピアフラップによって、提供中のノードがローテーションから外れることはありません。
- ピアが十分に長い時間到達不能になった場合も、サイクルは安定します。唯一のピアがダウンしているノードは、したがって、ほとんどまたはまったくデータを保持していない状態で Ready になります。エラーではなくミスを処理します。差異に基づいてロールアウトを制御したい場合は、`/status/rollout` が `backfill_initial_cycle` (`pending`、`complete`、または `degraded`) を報告します。

**バックフィルの変更をまたぐメッシュのアップグレード。** バックフィル以前の Kura リリースは、現在削除された別のピアプロトコルを通じてキャッチアップしていました。バックフィルのみをサポートするリリースに移行する **前に**、すべてのノードをバックフィルを実行するリリースにローリング更新してください。2 つのプロトコル上のノードは相互にキャッチアップできません: ウォームノードはボリュームからの提供を継続しますが、ギャップの解消を停止し、そのウィンドウ中に空のボリュームで開始したノードは決して Ready になりません。チャートは `KURA_BACKFILL_ENABLED=true` を設定するため、チャートを先にアップグレードすることでこれをカバーします。チャートとイメージを同時に移動する単一の `helm upgrade` ではカバーされません。

mTLS に加えてネットワークレベルの制限を使用します。Kubernetes では、Kura を `StatefulSet` として実行し、ポッドごとに 1 つの永続ボリュームとピア検出用のヘッドレスサービスを用意し、同じキャッシュデプロイメントに属するポッド間のみで内部ピアポートを許可します (例: `NetworkPolicy` を使用)。Kubernetes の外部では、各ノードに安定した DNS 名または IP アドレスを割り当て、他のノードの内部 URL でメッシュをシードし、ファイアウォールルールまたはセキュリティグループを使用して、キャッシュノードのみがピアポートに到達できるようにします。公開キャッシュトラフィックは、内部ピアプレーンではなく、公開 HTTP または gRPC エンドポイント経由で入力する必要があります。

## 構成 {#configuration}

Helm チャートは `values.yaml` から一般的なランタイム設定をレンダリングします。Kubernetes なしで Kura を実行する場合は、プロセスに直接同じ変数を設定します。チャートが直接マップしない変数は、`extraEnv` または `extraEnvFrom` を介して注入できます。

| 環境変数 | 説明 | 必須 | デフォルト | Helm 値 |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | 公開キャッシュポート。1 つのリスナーが HTTP キャッシュ API、ヘルスエンドポイント、および Bazel/Buck2 REAPI gRPC (h2c) を提供します。 | はい | デフォルトなし | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Kura ピアが使用する内部 HTTP または mTLS ポート。 | はい | デフォルトなし | `peerTls.internalPort` |
| `KURA_TENANT_ID` | ノードのデフォルトテナント識別子。 | はい | デフォルトなし | `config.tenantId` |
| `KURA_REGION` | メトリクスおよびレプリケーション状態で使用されるリージョンラベル。 | はい | デフォルトなし | `config.region` |
| `KURA_TMP_DIR` | ステージングされたリクエストボディおよびマルチパートアセンブリ用の一時ディレクトリ。 | はい | デフォルトなし | `/var/cache/kura/tmp` に固定 |
| `KURA_TMP_DIR_MAX_BYTES` | リクエストがバックプレッシャーを受ける前に `KURA_TMP_DIR` に許可される最大ステージングバイト数。 | いいえ | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | メタデータ状態およびセグメントファイル用の永続ディレクトリ。 | はい | デフォルトなし | `/var/cache/kura` に固定 |
| `KURA_NODE_URL` | 他のピアがこのノードに到達するために使用する正規の内部 URL。 | はい | デフォルトなし | ポッドの DNS 名と `peerTls.internalPort` から派生 |
| `KURA_PEERS` | 検出が収束する前に使用されるシードピアリスト。 | いいえ | `KURA_NODE_URL` | StatefulSet のレプリカから派生 |
| `KURA_DISCOVERY_DNS_NAME` | 自動ピア検出に使用される DNS 名。 | いいえ | 無効 | `config.discovery.enabled` によって有効化 |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | ピア mTLS を検証するために使用される CA 証明書。 | いいえ | 無効、またはノードが登録時に `KURA_DATA_DIR` の下で派生 | `peerTls.enabled` および `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | 内部ピア mTLS リスナーによって使用される証明書。 | いいえ | 無効、またはノードが登録時に `KURA_DATA_DIR` の下で派生 | `peerTls.enabled` および `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | 内部ピア mTLS リスナーによって使用される秘密鍵。 | いいえ | 無効、またはノードが登録時に `KURA_DATA_DIR` の下で派生 | `peerTls.enabled` および `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | 共有 HTTPS リスナー (`KURA_HTTPS_PORT`) で TLS を終端するために使用される証明書。 | いいえ | 無効 | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | `KURA_PUBLIC_TLS_CERT_PATH` とペアになる秘密鍵。 | いいえ | 無効 | `extraEnv` |
| `KURA_HTTPS_PORT` | 同じ共有 HTTP + gRPC サーフェス (ALPN ネゴシエート) を提供する TLS ポート。公開 TLS パスが設定されている場合にのみバインドされます。 | いいえ | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | 上流接続を再利用するプロキシ向けに、gRPC API 専用を提供するプレーンテキスト HTTP/2 ポート。[ロードバランサの背後にノードを配置する](#load-balancers)を参照してください。 | いいえ | 無効 | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | リクエストおよびバックグラウンド I/O 用のファイルディスクリプタ予算。 | いいえ | 自動派生 | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | FD バックプレッシャーがチェックアウトを失敗させるまでリクエストが待機する時間。 | いいえ | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | ピン留めされたセグメント読み取りハンドルの最大数。 | いいえ | 自動派生 | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | シャットダウン中に進行中の HTTP および gRPC 処理のための猶予期間。 | いいえ | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Kura がオプションのメモリ使用量を削減し始めるソフトなメモリウォーターマーク。 | いいえ | 自動派生 | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Kura がレプリケーションを一時停止し、ホットキャッシュをトリムするハードなメモリウォーターマーク。 | いいえ | 自動派生 | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | インメモリマニフェストキャッシュの最大サイズ。 | いいえ | 自動派生 | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | リクエストごとの keyvalue ペイロードサイズの最大値。 | いいえ | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | メタデータストア用に予約されたファイルディスクリプタ予算。 | いいえ | 自動派生 | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | メタデータストアのバックグラウンドフラッシュおよびコンパクションの並行性。 | いいえ | 自動派生 | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | メタデータストアの読み取りキャッシュの容量。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | メタデータの書き込みバッファリング用に予約された総メモリ予算。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | フラッシュ前の各メタデータ書き込みバッファのサイズ。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | メモリ内に保持されるメタデータ書き込みバッファの最大数。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | 進行中のマルチパートアップロードが期限切れになるまで待機できる時間。 | いいえ | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Kura が期限切れのマルチパートアップロードをスキャンする頻度。 | いいえ | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | 最新のものから数えた、年齢順に並べられたセグメントリングの共有部分で、バックフィルパスがどの程度過去まで遡るかを制限します。 | いいえ | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | 最初のバックフィルサイクルを実行中のノードが自身を準備完了として報告するセグメントリングの満杯率。 | いいえ | `KURA_BACKFILL_MARGIN_PERCENT`の半分 | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | 1つのバックフィル本体バッチを構成するバイト数のしきい値、および単独でフェッチされるエントリのサイズ上限。 | いいえ | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio ワーカースレッドの数。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP トレースのエンドポイント。トレースを無効にするには空のままにしてください。 | いいえ | 無効 | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry サービス名。 | はい | デフォルトなし | Helm の Pod 名 |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry デプロイ環境。 | はい | デフォルトなし | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | パニックおよびエラー報告用の Sentry DSN。 | いいえ | 無効 | `extraEnv` または `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | ノードが実行されているデータセンターの ISO 3166-1 alpha-2 国コード。エクスポートされたトレースに `geo.country.iso_code` として付与されます。 | いいえ | プレフィックスが国コードの場合、`KURA_REGION` から派生 | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | そのデータセンターの ISO 3166-2 行政区分（例: `US-CA`）。`geo.region.iso_code` として付与されます。 | いいえ | 未設定 | `extraEnv` |
| `KURA_AUTH_ENABLED` | 呼び出し側が有効な Tuist トークンを提示することを要求します。`KURA_AUTH_TUIST_URL` を設定するとそれだけで認証が有効になり、これを `false` に設定しても無効にはなりません。認証なしでノードを実行するには URL を未設定にしてください。 | いいえ | 無効 | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | ノードが認証を行う Tuist サーバー。これを設定するだけで認証が有効になります。 | 認証が有効な場合に必須 | デフォルトなし | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | そのサーバーへの呼び出しの接続タイムアウト。 | いいえ | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | そのサーバーへの呼び出しのリクエストタイムアウト。 | いいえ | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | ノードが自身で読み取れるトークン用の共有シークレット。ラウンドトリップを省略できます。署名と検証の両方を行うため、ノードとサーバーが同じ信頼境界にある場合のみ使用してください。セルフホスト型ノードでは通常、これを未設定にします。 | いいえ | 無効 | `extraEnv` または `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | サーバーがキャッシュトークンの署名に使用する鍵ペアの公開側。1つ以上の連結されたPEMブロックとして指定します。トークンを発行することはできず、読み取りのみ可能です。インターネットから到達可能なノードが保持すべき設定です。`KURA_AUTH_JWT_SECRET` と排他的です。 | いいえ | 無効 | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | その鍵のアルゴリズム: シークレットを使用する場合は `HS256`、`HS384`、または `HS512`。公開鍵を使用する場合は `ES256`。 | いいえ | シークレットを使用する場合は `HS256`、公開鍵を使用する場合は `ES256` | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | トークンが必須とする発行者。 | いいえ | 未チェック | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | トークンが必須とする、カンマ区切りのオーディエンス。 | いいえ | 未チェック | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | 認証および認可キャッシュそれぞれに保持される最大エントリ数。 | いいえ | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | 起動ごとにコントロールプレーンにノードを登録し、ピア証明書をプロビジョニングして `KURA_TENANT_ID` および `KURA_PEERS` を供給します。 | いいえ | 無効 | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | ノードが登録を行う Tuist サーバー。 | 登録時に必須 | デフォルトなし | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | ダッシュボードで生成されたノード資格情報のクライアントID。 | 登録またはエンロール時に必須 | デフォルトなし | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | `KURA_CONTROL_PLANE_CLIENT_ID` に対応するクライアントシークレット。 | 登録またはエンロール時に必須 | デフォルトなし | `extraEnv` |
| `KURA_REGISTRATION_URL` | ノードが登録ハートビートを送信する絶対URL。クライアント向けエンドポイントを広告します。 | 登録時に必須 | デフォルトなし | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | コントロールプレーンがクライアントに提供する、クライアント向けのキャッシュURL。アカウント上のすべてのクライアントから到達可能である必要があります。 | 登録時に必須 | デフォルトなし | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | 登録ハートビートの間隔。リースは複数の欠落したハートビートを許容するため、単一のハートビート欠落でもエンドポイントは失われません。 | いいえ | `60000` | `extraEnv` |

内部ピアmTLSを有効にする場合は、`KURA_INTERNAL_TLS_CA_CERT_PATH`、`KURA_INTERNAL_TLS_CERT_PATH`、および `KURA_INTERNAL_TLS_KEY_PATH` を同時に設定してください。`KURA_NODE_URL` および `KURA_PEERS` のすべての値は、内部ピアポートを使用した `https://` を使用する必要があります。
