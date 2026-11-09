---
{
  "title": "セルフホスト型キャッシュ",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "セルフホスト型キャッシュノードをデプロイし、Tuist に接続します。"
}
---

# セルフホスト型キャッシュ {#self-hosted-cache}

セルフホスト型キャッシュノードを使用すると、ビルド成果物とキャッシュメタデータを、ビルド出力を生成・消費するマシンの近くに配置できます。CI、開発者向けオフィス、リモートワークステーション、地域別コンピューティングクラスター全体でキャッシュのレイテンシーが重要な場合に活用してください。

目標は、中央キャッシュがたまたま近くにある環境だけでなく、あらゆる場所で低レイテンシーなキャッシングを実現することです。各キャッシュノードはローカルディスクからの読み書きを提供し、メッシュネットワークがピア間で成果物とメタデータを複製するため、他の場所でも時間とともに同じキャッシュの恩恵を受けられます。

> [!NOTE]
> Tuist のセルフホスト型キャッシュノードは、Tuist の分散型キャッシュメッシュである [Kura](https://github.com/tuist/tuist/tree/main/kura) によって動作します。Kura はキャッシュノードのデータプレーンとして機能し、キャッシュの読み書きを提供し、ローカル状態をディスクに保存し、成果物とメタデータをピアノードに複製します。

## セルフホスト型キャッシュと Tuist の統合 {#how-self-hosted-cache-fits-with-tuist}

Tuist のマネージドキャッシュは `https://<account>.cache.tuist.dev` を使用します。セルフホスト型の Tuist サーバーでは、CLI がサーバーの `TUIST_CACHE_ENDPOINTS` 設定からキャッシュ URL を取得します。これをメインのキャッシュサーバーまたはロードバランサーの URL に設定してください。複数の URL が含まれている場合は、最初の URL が使用されます。

**ホスト型 Tuist サーバー** に接続されたプライベート/カスタムキャッシュノードの場合、開発者シェルおよび CI で明示的なエンドポイントを設定します。

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

このオーバーライドは両方のサーバータイプで優先され、セルフホスト型の Tuist サーバーでは任意です。Xcode キャッシュデーモンについては、設定後に `tuist setup cache` を再実行して、LaunchAgent が更新された環境を受け取れるようにしてください。

セルフホスト型の Tuist サーバーは、静的な構成からエンドポイントを取得します。Tuist ホスト型サーバーでは、ノードが認証情報を使用して認証を行い、自身を登録します。まず以下の 2 つのセクションのいずれかを使用してノードをデプロイし、その後 [Tuist へのノード接続](#connect-nodes-to-tuist) を参照してください。

## Kubernetes へのデプロイ {#deploy-on-kubernetes}

Kura は GitHub Container Registry 経由で Helm チャートとして配布されています。永続ボリュームを持つ `StatefulSet` として Kura をデプロイし、ピア検出用のヘッドレスサービスと、HTTP および gRPC トラフィック用の通常のサービスを提供します。

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

同じクラスター内のセルフホスト型 Tuist サーバーの場合、メインのキャッシュエンドポイントを構成します。

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

これにより、サーバーポッド内に `TUIST_CACHE_ENDPOINTS` が設定されます。開発者用マシンや CI から到達可能なアドレスを使用してください。上記のクラスター内ローカルサービス名は、クラスター内で実行されるクライアントに適しています。

> [!IMPORTANT]
> すべての Kura ノードは独自の `KURA_DATA_DIR` を所有する必要があります。Kura はデータディレクトリに対してアプリケーションレベルのライターロックを取得し、それを所有するプロセスが正確に 1 つであることを想定しています。Kubernetes では、ポッドごとに 1 つの永続ボリュームを使用してください。Kubernetes 以外では、複数のプロセスを同じマウントディレクトリに向けないでください。

## Kubernetes なしでのデプロイ {#deploy-without-kubernetes}

Kura は VM やベアメタルホスト上で通常のコンテナとしても実行できます。このモードでは、プロセスの監視、永続ストレージ、ルーティング、ピア検出はお客様の責任となります。

最低限、各ノードには永続データディレクトリ、一時ディレクトリ、公開キャッシュポート（1 つのリスナーが HTTP キャッシュ API と REAPI gRPC の両方に対応）、内部ピア URL、そして静的ピアリストまたは検出メカニズムのいずれかが必要です。

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

セルフホスト型の Tuist サーバーでは、開発者用マシンや CI から到達可能なメインのキャッシュ URL を構成します。

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## ノードをロードバランサーの背後に配置 {#load-balancers}

クライアントは各キャッシュエンドポイント URL を HTTP と gRPC の両方に使用します。HTTP はヘルスチェックと HTTP キャッシュ API に、gRPC はモジュールキャッシュと Bazel のリモートキャッシュに使用されます。クライアントと Kura の間のイングレス、ロードバランサー、または CDN は、同じホスト名とポートで両方を転送する必要があります。これはクライアントが受け取るすべてのエンドポイントに適用されます。CLI は最も速く応答するものを選択するためです。gRPC が Kura に到達しない場合、CLI はリモートモジュールキャッシングが利用できないことを警告し、ローカルモジュールキャッシュのみを使用します。

これらのパスプレフィックスを HTTP/2 上の gRPC として Kura にルーティングし、その他すべてを HTTP としてルーティングします。

| パスプレフィックス | 使用者 |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | モジュールキャッシュ、Bazel |
| `/google.bytestream.` | モジュールキャッシュ、Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel ビルドイベント |

Kura は `KURA_PORT` でプレーンテキスト HTTP/2 (h2c) を受け入れ、`KURA_PUBLIC_TLS_CERT_PATH` と `KURA_PUBLIC_TLS_KEY_PATH` が設定されている場合、`KURA_HTTPS_PORT` で TLS 上の HTTP/2 を受け入れます。イングレス nginx のようにプロキシがリクエスト間でアップストリーム接続を再利用する場合、`KURA_GATEWAY_GRPC_PORT` を設定し、代わりにそのポートに gRPC トラフィックを送信してください。これは gRPC のみを提供するため、HTTP/1.1 と gRPC リクエストが接続を共有することはありません。

gRPC ルートを以下のように構成します。

- リクエストボディサイズ制限なし。アップロードは単一のリクエストで 1 つのファイルを送信し、最大 2 GiB です。
- リクエストとレスポンスのバッファリングを無効化。
- 読み取り、送信、アイドルタイムアウトを少なくとも 300 秒に設定。

Kura は gRPC ヘルスチェックサービスを提供しません。`/ready` で HTTP 経由でノードのヘルスチェックを行います。ロードバランサーが gRPC ヘルスチェックを必要とする場合、`/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` を呼び出し、gRPC ステータスコード `0` と `16` を許容してください。認証が有効なノードは、トークンなしのリクエストに対して `16` (`UNAUTHENTICATED`) で応答します。

### ingress-nginx {#load-balancers-ingress-nginx}

Helm チャートを使用する場合、HTTP イングレスを `/` に維持し、同じホスト用に gRPC イングレスを追加します。TLS を宣言するのは HTTP イングレスのみです。

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

gRPC ターゲットグループには HTTPS リスナーが必要です。そのリスナーで以下を行います。

1. デフォルトルールを、プロトコルバージョン `HTTP1` の `KURA_PORT` 上のターゲットグループに転送し、`/ready` で HTTP 経由のヘルスチェックを行います。
2. プロトコルバージョン `gRPC` の 2 番目のターゲットグループを作成し、`KURA_GATEWAY_GRPC_PORT` (または `KURA_PORT`) でプロトコル `HTTP` を使用するか、`KURA_HTTPS_PORT` でプロトコル `HTTPS` を使用します。ヘルスチェックは上記のように構成します。
3. パスパターン `/build.bazel.remote.execution.v2.*`、`/google.bytestream.*`、`/build.bazel.remote.asset.v1.*`、および `/google.devtools.build.v1.*` を 2 番目のターゲットグループに転送するルールを追加します。
4. ロードバランサーのアイドルタイムアウトを少なくとも 300 秒に引き上げます。

### CDN {#load-balancers-cdns}

ノードの前に配置される CDN は gRPC をサポートし、ファイアウォールルールで gRPC パスをブロックしてはいけません。クライアントは最大 2 MiB のチャンクで大きなアーティファクトをアップロードし、ノードがそれらを組み立てるため、大きなボディや長時間のアップロードを必要とするリクエストはありません。モジュールキャッシュと Xcode コンパイルキャッシュはこの動作を行い、`--experimental_remote_cache_chunking` でビルドされた Bazel (Bazel 8.7 および 9.1 以降) も同様です。このフラグがない場合、Bazel は各出力を単一のリクエストでアップロードするため、CDN は大きなリクエストボディと、最も遅いリンクで最大の出力に必要な時間만큼かかるアップロードも許可する必要があります。CDN がこれらの要件を満たせない場合は、DNS のみのレコードなど、それをバイパスするホスト名をクライアントに提供してください。

#### Cloudflare {#load-balancers-cloudflare}

モジュールキャッシングは、どのプランでもプロキシされた Cloudflare ホスト名を通じて機能します。ゾーン内で以下を行います。

1. **ネットワーク** で **gRPC** を有効にします。
2. **SSL/TLS** で、暗号化モードを **Full** または **Full (strict)** に設定します。Cloudflare はポート 443 でオリジンに接続するため、オリジンはそこで TLS を提供し、ALPN を介して HTTP/2 を利用可能にする必要があります。
3. 上記の gRPC パスをブロックする WAF カスタムルールまたはマネージドルールがないことを確認してください。

Cloudflare は、オリジンが約 2 分後に応答を開始しない場合にリクエストを終了します。`--experimental_remote_cache_chunking` なしの Bazel アップロードは最後のバイトが到着してから応答されるため、Cloudflare ではその時間を超えるアップロードは失敗します。

## ノードを Tuist に接続 {#connect-nodes-to-tuist}

クライアントルーティングを構成し、ノードを Tuist に登録して、アドレス、準備状態、使用状況がダッシュボードに表示されるようにします。

**セルフホスト型 Tuist サーバー** では、上記のデプロイメントセクションで示されているように、`TUIST_CACHE_ENDPOINTS` でエンドポイントを静的に宣言します。CLI は最初に構成された URL を使用します。`TUIST_CACHE_ENDPOINT` は個別のクライアントに対してその URL を上書きします。

**Tuist ホスト型サーバー** では、開発者シェルと CI で `TUIST_CACHE_ENDPOINT` を設定し、キャッシュリクエストをノードにルーティングします。各ノードは生成した資格情報で認証を行い、その後アドレスを登録して準備状態をダッシュボードに報告します。このセクションではノード登録について説明します。

> [!IMPORTANT]
> **Enterprise プラン**
>
> セルフホスト型キャッシュノードは Enterprise プランで利用可能です。以下で説明する **セルフホスト型サーバー** セクションは、そのプランのアカウントにのみ表示されます。

### ノード資格情報の生成 {#generate-a-node-credential}

Tuist ダッシュボードでアカウントを開き、**キャッシュ** に移動して **セルフホスト型サーバー** を見つけます。**資格情報の生成** を選択して、クライアント ID とシークレットを発行します。

この資格情報は、作成したアカウントのトラフィックのみを承認します。

シークレットは一度だけ表示され、ダイアログを閉じた後は回復できないため、ノードが読み取るシークレットストアに直接コピーしてください。資格情報の失効は、それを使用しているすべてのノードの認証を直ちに停止させるため、使用中のものを失効させる前に代替品を生成してください。

### 起動時のノード登録 {#enroll-the-node-on-boot}

登録はノードを立ち上げるための推奨方法です。`KURA_ENROLL_ON_BOOT` を設定し、ノードにその資格情報と独自のピア URL を指定します。

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

ノードはローカルでキーペアを生成するため、秘密鍵が外部に出ることはなく、署名付きピア証明書、アカウント CA、テナント識別子、およびピアリストを受け取ります。これは手動で構成する必要のあるすべてのものであり、登録済みのノードには `KURA_TENANT_ID`、`KURA_PEERS`、およびピア TLS 設定は不要です。

`KURA_INTERNAL_TLS_*` は未設定のままにしてください。登録処理により、証明書資料が `KURA_DATA_DIR` 下の `tls` ディレクトリに書き込まれます。[キャッシュメッシュの構築](#build-a-cache-mesh) で説明されているように、登録ではなく証明書を自分で提供する場合は、これらのパスを自分で設定してください。

アカウントのメッシュに初めて参加するノードは、リングの稼働メンバーになる前に、アカウントの既存のキャッシュを取得します。データボリュームはキャッシュ全体に合わせてサイズ調整し、広域リンクでの最初の参加には時間がかかることを想定してください。ノードは追いつくまで `joining` を報告し、その後 `serving` になります。

### エンドポイントの広告 {#advertise-the-endpoint}

登録によりメッシュに参加します。登録処理は、ノードのクライアント向けアドレスと準備状態を Tuist に報告します。登録変数を設定します。

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

ノードは 180 秒のリースに対して 60 秒ごとにハートビートを送信します。リースが期限切れになると、Tuist はその登録を利用不可とみなします。Tuist はノードを呼び出さないため、インターネットからではなく、クライアントから到達可能であれば十分です。

### ノードが稼働中であることを確認 {#verify-the-node-is-serving}

ダッシュボードの **キャッシュ** に戻ると、ノードは **登録済みノード** の下に、エンドポイント、リージョン、ステータス、最後のハートビートとともに表示されます。まったく表示されないノードは、登録エンドポイントに到達していないか、承認に失敗しています。表示された後に消えるノードは、ハートビートを停止しているか、準備状態の報告を停止しています。

### アカウントの永続的なテナント識別子を使用 {#match-the-tenant-identifier}

`KURA_TENANT_ID` はアカウントの永続的なキャッシュ識別子です。名前が変更されたことのないアカウントの場合、これはアカウントハンドルと一致します。名前変更後は、交換用ノードを含むすべてのノードで元の値を維持してください。これを変更すると異なるストレージネームスペースが選択され、アカウントの名前変更は保存されたアーティファクトを移行しません。アカウントの現在の URL から推測するのではなく、既存のノードからのテナントまたは登録によって返される `tenant_id` を再利用してください。

コントロールプレーンは、ハートビートのテナントを資格情報から解決されたアカウントと比較し、不一致を `409 tenant_mismatch` で拒否するため、間違った値を持つノードは認証に成功しても登録されることはありません。

> [!IMPORTANT]
> このガイドの前半にある Helm チャートとコンテナ例の両方は、これを `default` にデフォルト設定しています。ノードを登録する前に、これをアカウントのテナント識別子に置き換えてください。コントロールプレーンが値を提供するため、ノードを登録することでこの問題を完全に回避できます。

未設定の `KURA_TENANT_ID` はチェックをスキップしません。登録を完全に無効にします。ノードはキャッシュトラフィックの提供を継続しますが、ダッシュボードには何も表示されず、エラーも報告されません。ノードが正常なのに **登録済みノード** に表示されない場合は、まずこの変数を確認してください。

### クライアントが到達可能な広告 URL を選択 {#choose-an-advertised-url}

`KURA_ADVERTISED_HTTP_URL` および Tuist サーバーまたは CLI で構成されたキャッシュ URL には、クライアントが到達可能なアドレスを使用してください。

設定されたすべてのクライアントがその名前を解決して到達できる場合、内部専用のホスト名が適しています。異なるネットワーク上のクライアントには、共有の到達可能なアドレスを使用するか、環境ごとに到達可能なキャッシュノードを設定してください。

## キャッシュメッシュを構築 {#build-a-cache-mesh}

キャッシュメッシュを使用すると、必要とするコンピューティングリソースの近くにキャッシュ容量を配置できます。企業は、メインのCIランナーの近くに1つのノード、ヨーロッパの開発者の近くにもう1つ、米国のオフィスや地域のビルドクラスターの近くにもう1つを実行するかもしれません。各ロケーションは最も近いノードに対して読み書きを行い、Kuraはバックグラウンドでアーティファクトとメタデータを複製するため、他のロケーションでの後続のビルドが同じ出力を再利用できます。

メッシュが機能するのは、ノードがKuraの内部ピアポートで相互に到達できる場合のみです。このピアプレーンは、Tuistクライアントが使用するパブリックキャッシュエンドポイントとは別物です。Kuraはこれを使用してメンバーシップを確認し、新しく参加したノードをバックフィルし、ローカル書き込みが受け入れられた後にアーティファクトを複製します。

ノードがリージョン、クラウド、VPC、オフィス、またはキャッシュデプロイメントに完全にプライベートではないネットワーク間で通信する場合、[mTLS](https://en.wikipedia.org/wiki/Mutual_authentication)を使用してピアプレーンを保護することを強く推奨します。mTLSを有効にすると、Kuraは構成されたCAによって署名された証明書を提示するピアに対してのみ、内部複製エンドポイントを提供します。ピア証明書は、ノードが相互に呼び出すために使用するDNS名をカバーする必要があり、ピアURLは内部ポートで `https://` を使用する必要があります。

> [!NOTE]
> Tuistがホストするコントロールプレーンに登録するノードは、登録中にピア証明書とアカウントCAを受け取るため、以下の手動手順は登録しないメッシュに適用されます。

例えば、これはプライベートCAと、小規模なメッシュ内のすべてのノードでマウント可能な1つのピア証明書を生成します。DNS名を、`KURA_NODE_URL` および `KURA_PEERS` でノードが使用する内部名に置き換えてください。

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

メッシュに参加または再参加するノードは **バックフィル** を実行します。各ピアのエントリを最新から順に走査し、不足しているものを取得します。一方、ライブレプリケーションはピアが表示されている間に行われた書き込みをカバーします。バックフィルパスは、ピアの最新のエントリから、ノードのセグメントリングの_horizon_と最後に完了したパスのうち古い方まで遡るため、ノードは最近のデータを保持することが保証されますが、必ずしもすべてを保持するわけではありません。`KURA_BACKFILL_MARGIN_PERCENT` は、horizonがどの程度過去まで遡るかを設定します。

メッシュを実行する前に知っておくべき2つの結果があります。

- ノードは、セグメントリングが `KURA_BACKFILL_READY_RING_PERCENT` 満たされる **か**、最初のバックフィルサイクルが安定すると `/ready` を報告し、その後プロセスの寿命の間、準備状態が維持されます。後続のピアフラップによって、サービス提供中のノードがローテーションから外されることはありません。
- ピアが十分に長い時間到達不能になると、サイクルも安定します。唯一のピアがダウンしているノードは、ほとんどまたはまったくデータを持たない状態でReadyになります。エラーではなくミスを提供します。違いに基づいてロールアウトを制御したい場合は、`/status/rollout` が `backfill_initial_cycle` （`pending`、`complete`、または `degraded`）を報告します。

**バックフィルの変更を跨ぐメッシュのアップグレード。** バックフィル以前のKuraリリースは、現在削除された別のピアプロトコルを通じてキャッチアップしていました。バックフィルのみをサポートするリリースに移行する **前に**、すべてのノードをバックフィルを実行するリリースにローリングアップデートしてください。2つのプロトコル上のノードは相互にキャッチアップできません。ウォームノードはボリュームからの提供を継続しますが、ギャップを埋めるのを停止し、その期間中に空のボリュームで開始したノードは決してReadyになりません。チャートは `KURA_BACKFILL_ENABLED=true` を設定するため、チャートを先にアップグレードすることでこれをカバーします。チャートとイメージを同時に移動する単一の `helm upgrade` ではカバーされません。

mTLSに加えてネットワークレベルの制限を使用してください。Kubernetesでは、Kuraを `StatefulSet` として実行し、ポッドごとに1つの永続ボリュームとピア検出用のヘッドレスサービスを用意し、同じキャッシュデプロイメントに属するポッド間のみで内部ピアポートを許可します（例えば `NetworkPolicy` を使用）。Kubernetesの外では、各ノードに安定したDNS名またはIPアドレスを割り当て、他のノードの内部URLでメッシュをシードし、ファイアウォールルールまたはセキュリティグループを使用して、キャッシュノードのみがピアポートに到達できるようにします。パブリックキャッシュトラフィックは、内部ピアプレーンではなく、パブリックHTTPまたはgRPCエンドポイント経由で入力する必要があります。

## 設定 {#configuration}

Helmチャートは、`values.yaml` から一般的なランタイム設定をレンダリングします。KubernetesなしでKuraを実行する場合は、プロセス上で直接同じ変数を設定してください。チャートが直接マップしない変数は、`extraEnv` または `extraEnvFrom` を介して注入できます。

| 環境変数 | 説明 | 必須 | デフォルト | Helm値 |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | パブリックキャッシュポート。1つのリスナーがHTTPキャッシュAPI、ヘルスエンドポイント、およびBazel/Buck2 REAPI gRPC（h2c）を提供します。 | はい | デフォルトなし | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Kuraピアが使用する内部HTTPまたはmTLSポート。 | はい | デフォルトなし | `peerTls.internalPort` |
| `KURA_TENANT_ID` | ノードのデフォルトテナント識別子。 | はい | デフォルトなし | `config.tenantId` |
| `KURA_REGION` | メトリクスとレプリケーション状態で使用されるリージョンラベル。 | はい | デフォルトなし | `config.region` |
| `KURA_TMP_DIR` | ステージングされたリクエストボディとマルチパート組み立て用の一時ディレクトリ。 | はい | デフォルトなし | `/var/cache/kura/tmp` に固定 |
| `KURA_TMP_DIR_MAX_BYTES` | リクエストがバックプレッシャーを受ける前に `KURA_TMP_DIR` に admitted される最大ステージングバイト数。 | いいえ | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | メタデータ状態とセグメントファイル用の永続ディレクトリ。 | はい | デフォルトなし | `/var/cache/kura` に固定 |
| `KURA_NODE_URL` | 他のピアがこのノードに到達するために使用する正規の内部URL。 | はい | デフォルトなし | ポッドのDNS名と `peerTls.internalPort` から派生 |
| `KURA_PEERS` | 検出が収束する前に使用されるシードピアリスト。 | いいえ | `KURA_NODE_URL` | StatefulSetのレプリカから派生 |
| `KURA_DISCOVERY_DNS_NAME` | 自動ピア検出に使用されるDNS名。 | いいえ | 無効 | `config.discovery.enabled` によって有効化 |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | ピアmTLSの検証に使用されるCA証明書。 | いいえ | 無効、またはノードが登録時に `KURA_DATA_DIR` の下で派生 | `peerTls.enabled` および `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | 内部ピアmTLSリスナーが使用する証明書。 | いいえ | 無効、またはノードが登録時に `KURA_DATA_DIR` の下で派生 | `peerTls.enabled` および `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | 内部ピアmTLSリスナーが使用する秘密鍵。 | いいえ | 無効、またはノードが登録時に `KURA_DATA_DIR` の下で派生 | `peerTls.enabled` および `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | 共存HTTPSリスナー（`KURA_HTTPS_PORT`）でTLSを終端するために使用される証明書。 | いいえ | 無効 | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | `KURA_PUBLIC_TLS_CERT_PATH` とペアになる秘密鍵。 | いいえ | 無効 | `extraEnv` |
| `KURA_HTTPS_PORT` | 同じ共存HTTP + gRPCサーフェス（ALPNネゴシエーション済み）を提供するTLSポート。パブリックTLSパスが設定されている場合にのみバインドされます。 | いいえ | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | 上流接続を再利用するプロキシ向けに、gRPC APIのみを提供するプレーンテキストHTTP/2ポート。[ロードバランサの背後にノードを配置する](#load-balancers)を参照してください。 | いいえ | 無効 | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | リクエストおよびバックグラウンドI/O用のファイルディスクリプタ予算。 | いいえ | 自動派生 | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | リクエストがFDバックプレッシャーによってチェックアウトに失敗するまでの待機時間。 | いいえ | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | ピン留めされたセグメント読み取りハンドルの最大数。 | いいえ | 自動派生 | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | シャットダウン中に進行中のHTTPおよびgRPC処理のための猶予期間。 | いいえ | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Kuraがオプションのメモリ使用量を削減し始めるソフトメモリウォーターマーク。 | いいえ | 自動派生 | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Kuraがレプリケーションを一時停止し、ホットキャッシュをトリミングするハードメモリウォーターマーク。 | いいえ | 自動派生 | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | インメモリマニフェストキャッシュの最大サイズ。 | いいえ | 自動派生 | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | リクエストごとのキーバリューペイロードの最大サイズ。 | いいえ | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | メタデータストア用に予約されたファイルディスクリプタ予算。 | いいえ | 自動派生 | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | メタデータストアのバックグラウンドフラッシュおよびコンパクションの同時実行数。 | いいえ | 自動派生 | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | メタデータストア読み取りキャッシュの容量。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | メタデータ書き込みバッファリング用に予約された総メモリ予算。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | フラッシュ前の各メタデータ書き込みバッファのサイズ。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | メモリ内に保持されるメタデータ書き込みバッファの最大数。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | 進行中のマルチパートアップロードが期限切れになるまで保持できる時間。 | いいえ | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Kuraが期限切れのマルチパートアップロードをスキャンする頻度。 | いいえ | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | バックフィルパスが遡る範囲を制限する、最新から数えた年齢順セグメントリングの割合。 | いいえ | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | 最初のバックフィルサイクルを実行中のノードが準備完了と報告するセグメントリングの満杯率。 | いいえ | `KURA_BACKFILL_MARGIN_PERCENT` の半分 | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | 1回のバックフィル本体バッチを構成するバイト数のしきい値、およびエントリが個別にフェッチされるサイズの上限。 | いいえ | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio ワーカースレッドの数。 | いいえ | 自動派生 | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLPトレースエンドポイント。トレーシングを無効にする場合は空のままにしてください。 | いいえ | 無効 | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetryサービス名。 | はい | デフォルトなし | HelmでのPod名 |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetryデプロイ環境。 | はい | デフォルトなし | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | パニックおよびエラーレポート用のSentry DSN。 | いいえ | 無効 | `extraEnv` または `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | ノードが実行されているデータセンターのISO 3166-1 alpha-2国コード。エクスポートされたトレースに `geo.country.iso_code` として付与されます。 | いいえ | プレフィックスが国コードの場合、`KURA_REGION` から派生 | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | そのデータセンターのISO 3166-2区分（例: `US-CA`）。`geo.region.iso_code` として付与されます。 | いいえ | 未設定 | `extraEnv` |
| `KURA_AUTH_ENABLED` | 呼び出し元に有効なTuistトークンの提示を要求します。`KURA_AUTH_TUIST_URL` を設定するとそれだけで認証が有効になり、これを `false` に設定しても無効にはなりません。認証なしでノードを実行するには、URLを未設定にしてください。 | いいえ | 無効 | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | ノードが認証を行うTuistサーバー。これだけで認証が有効になります。 | 認証が有効な場合に必須 | デフォルトなし | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | そのサーバーへの呼び出しの接続タイムアウト。 | いいえ | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | そのサーバーへの呼び出しのリクエストタイムアウト。 | いいえ | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | ノードが自身で読み取れるトークンの共有シークレット。ラウンドトリップを省略します。署名と検証の両方を行うため、ノードとサーバーが同じ信頼境界内にある場合のみ使用してください。セルフホスト型ノードでは通常、これを未設定にします。 | いいえ | 無効 | `extraEnv` または `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | サーバーがキャッシュトークンの署名に使用する鍵ペアの公開側。1つ以上の連結されたPEMブロックとして指定します。トークンを生成することはできず、読み取りのみ可能です。インターネットから到達可能なノードが保持すべき構成です。`KURA_AUTH_JWT_SECRET` と排他的です。 | いいえ | 無効 | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | その鍵のアルゴリズム: シークレットを使用する場合は `HS256`、`HS384`、または `HS512`。公開鍵を使用する場合は `ES256`。 | いいえ | シークレットを使用する場合は `HS256`、公開鍵を使用する場合は `ES256` | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | トークンに含まれている必要がある発行者。 | いいえ | 未チェック | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | トークンに含まれている必要がある、カンマ区切りのオーディエンス。 | いいえ | 未チェック | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | 認証キャッシュと認可キャッシュのそれぞれに保持される最大エントリ数。 | いいえ | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | 起動時にノードをコントロールプレーンに登録し、ピア証明書をプロビジョニングして `KURA_TENANT_ID` と `KURA_PEERS` を供給します。 | いいえ | 無効 | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | ノードが登録を行うTuistサーバー。 | 登録時に必須 | デフォルトなし | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | ダッシュボードで生成されたノード資格情報のクライアントID。 | 登録時またはエンロール時に必須 | デフォルトなし | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | `KURA_CONTROL_PLANE_CLIENT_ID` に対応するクライアントシークレット。 | 登録時またはエンロール時に必須 | デフォルトなし | `extraEnv` |
| `KURA_REGISTRATION_URL` | ノードが登録ハートビートを送信する絶対URL。クライアント向けエンドポイントを広告します。 | 登録時に必須 | デフォルトなし | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | コントロールプレーンがクライアントに渡す、クライアント向けのキャッシュURL。アカウント上のすべてのクライアントから到達可能である必要があります。 | 登録時に必須 | デフォルトなし | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | 登録ハートビートの間隔。リースは複数のハートビート欠落を許容するため、単一のハートビート欠落でエンドポイントが削除されることはありません。 | いいえ | `60000` | `extraEnv` |

内部ピアmTLSを有効にする場合は、`KURA_INTERNAL_TLS_CA_CERT_PATH`、`KURA_INTERNAL_TLS_CERT_PATH`、および `KURA_INTERNAL_TLS_KEY_PATH` を同時に設定してください。`KURA_NODE_URL` および `KURA_PEERS` 内のすべての値は、内部ピアポートを使用した `https://` でなければなりません。
