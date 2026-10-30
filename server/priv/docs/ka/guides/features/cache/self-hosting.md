---
{
  "title": "საკუთარ სერვერზე განთავსებული ქეში",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "განათავსეთ საკუთარ სერვერზე ქეშის კვანძები და დააკავშირეთ ისინი Tuist-თან."
}
---

# თვითმასპინძელი ქეში {#self-hosted-cache}

თვითმასპინძელი ქეშის კვანძები გაძლევთ საშუალებას, ბილდის არტიფაქტები და ქეშის მეტამონაცემები შეინახოთ იმ მანქანებთან ახლოს, რომლებიც წარმოქმნიან და მოიხმარენ ბილდის გამომავალ მონაცემებს. გამოიყენეთ ისინი მაშინ, როცა ქეშის ლატენტობა მნიშვნელოვანია CI-ში, დეველოპერების ოფისებში, დაშორებულ სამუშაო სადგურებზე ან რეგიონულ საკომპიუტერო კლასტერებში.

მიზანია ყველგან დაბალი ლატენტობის ქეშირება, არა მხოლოდ იმ ერთ გარემოში, სადაც ცენტრალური ქეში შემთხვევით ახლოსაა. თითოეული ქეშის კვანძი ემსახურება წაკითხვებსა და ჩაწერებს ადგილობრივი დისკიდან, ხოლო mesh-ი არტიფაქტებსა და მეტამონაცემებს რეპლიცირებს პირებს შორის, რათა სხვა ლოკაციებმაც დროთა განმავლობაში მიიღონ იმავე ქეშის სარგებელი.

> [!NOTE]
> Tuist-ის თვითმასპინძელი ქეშის კვანძები მუშაობენ [Kura](https://github.com/tuist/tuist/tree/main/kura)-ზე, Tuist-ის დეცენტრალიზებულ ქეშის mesh-ზე. Kura არის ქეშის კვანძების მონაცემთა ფენა: ის ემსახურება ქეშის წაკითხვებსა და ჩაწერებს, ინახავს ადგილობრივ მდგომარეობას დისკზე და რეპლიცირებს არტიფაქტებსა და მეტამონაცემებს პირ კვანძებთან.

## როგორ ერწყმის თვითმასპინძელი ქეში Tuist-ს {#how-self-hosted-cache-fits-with-tuist}

Tuist-ის მართული ქეში იყენებს `https://<account>.cache.tuist.dev`. თვითმასპინძელ Tuist სერვერთან, CLI იღებს ქეშის URL-ს სერვერის `TUIST_CACHE_ENDPOINTS` პარამეტრიდან. დააყენეთ ის თქვენი ძირითადი ქეშის სერვერის ან სატვირთო ბალანსერის URL-ზე. თუ ის შეიცავს რამდენიმე URL-ს, გამოიყენება პირველი.

**hosted Tuist server**-თან დაკავშირებული პირადი/მორგებული ქეშის კვანძებისთვის, დააყენეთ ცალსახა endpoint დეველოპერების shell-ებში და CI-ში:

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

ეს გადაფარვა უპირატესობას იღებს ორივე ტიპის სერვერზე და არის არასავალდებულო თვითმასპინძელი Tuist სერვერებისთვის. Xcode-ის ქეშის daemon-ისთვის, მისი დაყენების შემდეგ ხელახლა გაუშვით `tuist setup cache`, რათა LaunchAgent-მა მიიღოს განახლებული გარემო.

თვითმასპინძელი Tuist სერვერი იღებს endpoint-ებს სტატიკური კონფიგურაციიდან. Tuist-ის მიერ hosted სერვერზე, კვანძები ავთენტიფიცირდებიან credential-ით და რეგისტრირდებიან. ჯერ განათავსეთ კვანძი ქვემოთ მოცემული ორი სექციიდან ერთ-ერთით, შემდეგ იხილეთ [Connect nodes to Tuist](#connect-nodes-to-tuist).

## განთავსება Kubernetes-ზე {#deploy-on-kubernetes}

Kura ვრცელდება Helm chart-ის სახით GitHub Container Registry-ის მეშვეობით. ის განათავსებს Kura-ს როგორც `StatefulSet` persistent volume-ებით, headless სერვისით peer-ების აღმოსაჩენად და ჩვეულებრივი სერვისით HTTP და gRPC ტრაფიკისთვის.

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

იმავე კლასტერში არსებული თვითმასპინძელი Tuist სერვერისთვის, დააკონფიგურირეთ მისი ძირითადი ქეშის endpoint:

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

ეს აყენებს `TUIST_CACHE_ENDPOINTS` სერვერის pod-ში. გამოიყენეთ მისამართი, რომელზეც დეველოპერების მანქანებსა და CI-ს შეუძლიათ წვდომა; ზემოთ მოცემული კლასტერ-ლოკალური სერვისის სახელი შესაფერისია კლასტერის შიგნით მომუშავე კლიენტებისთვის.

> [!IMPORTANT]
> ყოველ Kura კვანძს უნდა ჰქონდეს საკუთარი `KURA_DATA_DIR`. Kura იღებს აპლიკაციის დონის writer lock-ს მონაცემთა დირექტორიაზე და ელის, რომ ზუსტად ერთი პროცესი ფლობდეს მას. Kubernetes-ში, გამოიყენეთ ერთი persistent volume თითო pod-ზე. Kubernetes-ის გარეთ, ნუ მიუთითებთ რამდენიმე პროცესს იმავე mounted დირექტორიაზე.

## განთავსება Kubernetes-ის გარეშე {#deploy-without-kubernetes}

Kura ასევე შეიძლება გაეშვას როგორც ჩვეულებრივი კონტეინერი VM-ებზე ან bare-metal ჰოსტებზე. ამ რეჟიმში, თქვენ ხართ პასუხისმგებელი პროცესების მართვაზე, persistent storage-ზე, მარშრუტიზაციაზე და peer-ების აღმოჩენაზე.

მინიმუმ, თითოეულ კვანძს სჭირდება persistent მონაცემთა დირექტორია, დროებითი დირექტორია, საჯარო ქეშის პორტი (ერთი listener ემსახურება როგორც HTTP cache API-ს, ასევე REAPI gRPC-ს), შიდა peer URL და ან სტატიკური peer-ების სია, ან აღმოჩენის მექანიზმი:

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

თვითმასპინძელ Tuist სერვერზე, დააკონფიგურირეთ ძირითადი ქეშის URL, რომელზეც დეველოპერების მანქანებსა და CI-ს შეუძლიათ წვდომა:

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## კვანძების სატვირთო ბალანსერის უკან განთავსება {#load-balancers}

კლიენტები იყენებენ თითოეულ ქეშის endpoint URL-ს როგორც HTTP-ის, ასევე gRPC-ისთვის: HTTP ჯანმრთელობის შემოწმებებისა და HTTP cache API-ისთვის, ხოლო gRPC მოდულის ქეშისა და Bazel-ის remote cache-ისთვის. ნებისმიერ ingress-ს, სატვირთო ბალანსერს ან CDN-ს კლიენტებსა და Kura-ს შორის უნდა გადაჰქონდეს ორივე იმავე hostname-სა და პორტზე. ეს ვრცელდება ყველა endpoint-ზე, რომელსაც კლიენტები იღებენ, რადგან CLI ირჩევს იმას, რომელიც ყველაზე სწრაფად პასუხობს. თუ gRPC ვერ აღწევს Kura-მდე, CLI აფრთხილებს, რომ remote module caching ხელმიუწვდომელია და იყენებს მხოლოდ ადგილობრივ მოდულის ქეშს.

გააგზავნეთ ეს path prefix-ები Kura-ზე როგორც gRPC HTTP/2-ზე, ხოლო ყველაფერი დანარჩენი როგორც HTTP:

| Path prefix | გამოიყენება |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | მოდულის ქეში, Bazel |
| `/google.bytestream.` | მოდულის ქეში, Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel build events |

Kura იღებს plaintext HTTP/2-ს (h2c) `KURA_PORT`-ზე და HTTP/2-ს TLS-ზე `KURA_HTTPS_PORT`-ზე, როცა `KURA_PUBLIC_TLS_CERT_PATH` და `KURA_PUBLIC_TLS_KEY_PATH` დაყენებულია. თუ თქვენი proxy ხელახლა იყენებს upstream კავშირებს მოთხოვნებს შორის, როგორც ingress-nginx აკეთებს, დააყენეთ `KURA_GATEWAY_GRPC_PORT` და გააგზავნეთ gRPC ტრაფიკი იმ პორტზე. ის ემსახურება მხოლოდ gRPC-ს, ამიტომ HTTP/1.1 და gRPC მოთხოვნები არასდროს იზიარებენ კავშირს.

დააკონფიგურირეთ gRPC მარშრუტები:

- მოთხოვნის სხეულის ზომის ლიმიტი არ არის. ატვირთვა აგზავნის ერთ ფაილს ერთ მოთხოვნაში, 2 GiB-მდე.
- მოთხოვნისა და პასუხის ბუფერიზაცია გამორთულია.
- წაკითხვის, გაგზავნის და idle timeout-ები მინიმუმ 300 წამი.

Kura არ ემსახურება gRPC ჯანმრთელობის შემოწმების სერვისს. შეამოწმეთ კვანძების ჯანმრთელობა HTTP-ზე `/ready`-ზე. თუ თქვენი სატვირთო ბალანსერი მოითხოვს gRPC ჯანმრთელობის შემოწმებას, გამოიძახეთ `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` და დაუშვით gRPC სტატუსის კოდები `0` და `16`. ავტორიზაციის ჩართული კვანძი პასუხობს მოთხოვნას token-ის გარეშე `16`-ით (`UNAUTHENTICATED`).

### ingress-nginx {#load-balancers-ingress-nginx}

Helm chart-ით, დატოვეთ HTTP ingress `/`-ზე და დაამატეთ gRPC ingress იმავე ჰოსტისთვის. მხოლოდ HTTP ingress აცხადებს TLS-ს:

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

gRPC target groups-ს სჭირდება HTTPS listener. იმ listener-ზე:

1. გადაამისამართეთ default rule target group-ზე protocol version-ით `HTTP1` `KURA_PORT`-ზე, ჯანმრთელობის შემოწმებით HTTP-ზე `/ready`-ზე.
2. შექმენით მეორე target group protocol version-ით `gRPC`, გამოიყენეთ პროტოკოლი `HTTP` `KURA_GATEWAY_GRPC_PORT`-ზე (ან `KURA_PORT`), ან პროტოკოლი `HTTPS` `KURA_HTTPS_PORT`-ზე. დააკონფიგურირეთ მისი ჯანმრთელობის შემოწმება ზემოთ აღწერილი წესით.
3. დაამატეთ წესი, რომელიც გადაამისამართებს path pattern-ებს `/build.bazel.remote.execution.v2.*`, `/google.bytestream.*`, `/build.bazel.remote.asset.v1.*` და `/google.devtools.build.v1.*` მეორე target group-ზე.
4. გაზარდეთ სატვირთო ბალანსერის idle timeout მინიმუმ 300 წამამდე.

### CDN-ები {#load-balancers-cdns}

კვანძის წინ მდებარე CDN-მა უნდა უჭერდეს მხარს gRPC-ს და არ უნდა ბლოკავდეს gRPC მარშრუტებს თავისი firewall-ის წესებში. კლიენტები ტვირავენ დიდ არტეფაქტებს მაქსიმუმ 2 MiB ზომის ნაწილებად და აწყობენ მათ კვანძზე, ამიტომ არცერთ მოთხოვნას არ სჭირდება დიდი სხეული ან ხანგრძლივი ატვირთვა. მოდულის cache და Xcode კომპილაციის cache ასე იქცევა, ისევე როგორც Bazel, თუ აგებულია `--experimental_remote_cache_chunking` ფლაგით (Bazel 8.7 და 9.1 ან უფრო ახალი). ამ ფლაგის გარეშე, Bazel ტვირავენ თითოეულ output-ს ერთ მოთხოვნაში, ამიტომ CDN-მა ასევე უნდა დაუშვას დიდი მოთხოვნის სხეულები და ატვირთვები, რომლებიც იმდენ ხანს გრძელდება, რამდენსაც თქვენი უდიდესი outputs საჭიროებენ თქვენს ყველაზე ნელ ბმულზე. თუ თქვენი CDN ვერ აკმაყოფილებს ამ მოთხოვნებს, მისცეთ კლიენტებს hostname, რომელიც აუვლის გვერდს, მაგალითად, მხოლოდ DNS ჩანაწერი.

#### Cloudflare {#load-balancers-cloudflare}

მოდულის caching მუშაობს proxied Cloudflare hostname-ის მეშვეობით ნებისმიერ პაკეტზე. ზონაში:

1. **Network**-ის ქვეშ, ჩართეთ **gRPC**.
2. **SSL/TLS**-ის ქვეშ, დააყენეთ encryption mode **Full**-ზე ან **Full (strict)**-ზე. Cloudflare უკავშირდება origin-ს 443 პორტზე, ამიტომ origin-მა უნდა მიჰყავდეს TLS იქ და შესთავაზოს HTTP/2 ALPN-ის მეშვეობით.
3. დარწმუნდით, რომ არცერთი WAF custom rule ან managed rule არ ბლოკავს ზემოთ ჩამოთვლილ gRPC მარშრუტებს.

Cloudflare ასრულებს მოთხოვნას, თუ origin-მა დაახლოებით ორი წუთის განმავლობაში არ დაიწყო პასუხის გაგზავნა. Bazel ატვირთვა `--experimental_remote_cache_chunking`-ის გარეშე იღებს პასუხს მხოლოდ მას შემდეგ, რაც მისი ბოლო ბაიტი მივა, ამიტომ Cloudflare-ზე ასეთი ატვირთვები ვერ ხერხდება, თუ ისინი იმაზე მეტ ხანს გრძელდება.

## კვანძების დაკავშირება Tuist-თან {#connect-nodes-to-tuist}

დააკონფიგურირეთ კლიენტის მარშრუტიზაცია და დაარეგისტრირეთ თქვენი კვანძები Tuist-ში, რათა მათი მისამართები, მზადყოფნა და გამოყენება გამოჩნდეს dashboard-ში.

**self-hosted Tuist server**-ზე, თქვენ აცხადებთ endpoint-ებს სტატიკურად `TUIST_CACHE_ENDPOINTS`-ის მეშვეობით, როგორც ეს ნაჩვენებია ზემოთ განლაგების სექციებში. CLI იყენებს პირველ კონფიგურირებულ URL-ს. `TUIST_CACHE_ENDPOINT` ცვლის ამ URL-ს ინდივიდუალური კლიენტისთვის.

**Tuist-hosted server**-ზე, დააყენეთ `TUIST_CACHE_ENDPOINT` developer shells-ში და CI-ში, რათა მიმართოთ cache მოთხოვნები თქვენს კვანძებზე. თითოეული კვანძი ავტორიზდება თქვენს მიერ შექმნილი credential-ით, შემდეგ ადარეგისტრირებს თავის მისამართს და აცნობებს თავის მზადყოფნას dashboard-ს. ეს სექცია ეხება კვანძის რეგისტრაციას.

> [!IMPORTANT]
> **Enterprise plan**
>
> Self-hosted cache კვანძები ხელმისაწვდომია Enterprise პაკეტზე. ქვემოთ აღწერილი **Self-hosted servers** სექცია ჩანს მხოლოდ იმ ანგარიშებისთვის, რომლებიც ამ პაკეტზე არიან.

### კვანძის credential-ის გენერირება {#generate-a-node-credential}

Tuist dashboard-ში, გახსენით თქვენი ანგარიში, გადადით **Cache**-ზე და იპოვეთ **Self-hosted servers**. აირჩიეთ **Generate credential** client ID-ის და secret-ის შესაქმნელად.

credential ავტორიზებს მხოლოდ იმ ანგარიშის ტრაფიკს, რომელმაც ის შექმნა.

secret ჩანს ერთხელ და არ არის აღდგენადი დიალოგის დახურვის შემდეგ, ამიტომ პირდაპირ დააკოპირეთ ის იმ secret store-ში, საიდანაც თქვენი კვანძები კითხულობენ. credential-ის გაუქმება მყისიერად აჩერებს ყველა კვანძს, რომელიც მას იყენებს, ავტორიზაციისგან, ამიტომ შექმენით ჩამნაცვლებელი სანამ გააუქმებთ მოქმედში მყოფს.

### კვანძის რეგისტრაცია გაშვებისას {#enroll-the-node-on-boot}

რეგისტრაცია არის კვანძის ამუშავების რეკომენდებული გზა. დააყენეთ `KURA_ENROLL_ON_BOOT` და მისცეთ კვანძს მისი credential და საკუთარი peer URL:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

კვანძი ადგილობრივად ქმნის თავის keypair-ს, ამიტომ private key არასდროს ტოვებს მას, და იღებს ხელმოწერილ peer certificate-ს, ანგარიშის CA-ს, მის tenant identifier-ს და peer-ების სიას. ეს არის ყველაფერი, რასაც წინააღმდეგ შემთხვევაში ხელით დააკონფიგურირებდით: რეგისტრირებულ კვანძს არ სჭირდება `KURA_TENANT_ID`, არ `KURA_PEERS` და არ peer TLS კონფიგურაცია.

დატოვეთ `KURA_INTERNAL_TLS_*` დაუყენებელი: რეგისტრაცია წერს certificate მასალას `tls` დირექტორიაში `KURA_DATA_DIR`-ის ქვეშ. დააყენეთ ეს გზები თავად მხოლოდ მაშინ, როცა თქვენ აწვდით certificate-ებს რეგისტრაციის ნაცვლად, როგორც ეს აღწერილია [Build a cache mesh](#build-a-cache-mesh)-ში.

კვანძი, რომელიც პირველად უერთდება ანგარიშის mesh-ს, იწევს ანგარიშის არსებულ cache-ს სანამ გახდება ring-ის მომსახურე წევრი. გაზომეთ data volume მთელი cache-ისთვის და ელოდეთ, რომ პირველი შეერთება გარკვეული დრო დასჭირდება wide-area ბმულზე. კვანძი აცნობებს `joining`-ს სანამ არ დაეწევა, შემდეგ `serving`-ს.

### endpoint-ის რეკლამირება {#advertise-the-endpoint}

რეგისტრაცია აერთებს mesh-ში. რეგისტრაცია აცნობებს კვანძის კლიენტისთვის ხელმისაწვდომ მისამართს და მზადყოფნას Tuist-ს. დააყენეთ რეგისტრაციის ცვლადები:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

კვანძი აგზავნის heartbeat-ს ყოველ 60 წამში 180-წამიანი lease-ის წინააღმდეგ. Tuist მიიჩნევს მის რეგისტრაციას მიუწვდომლად, როცა lease იწურება. Tuist არასდროს ურეკავს კვანძს, ამიტომ ის მხოლოდ თქვენი კლიენტებისთვის უნდა იყოს ხელმისაწვდომი, არა ინტერნეტიდან.

### შეამოწმეთ, რომ კვანძი ემსახურება {#verify-the-node-is-serving}

dashboard-ში **Cache**-ში დაბრუნებისას, კვანძი ჩანს **Registered nodes**-ის ქვეშ თავისი endpoint-ით, რეგიონით, სტატუსით და ბოლო heartbeat-ით. კვანძი, რომელიც არასდროს ჩანს, ვერ აღწევს რეგისტრაციის endpoint-ს ან ვერ ავტორიზდება. კვანძი, რომელიც ჩანს და შემდეგ ქრება, შეწყვიტა heartbeat-ის გაგზავნა ან შეწყვიტა თავისი მზადყოფნის შესახებ ანგარიშგება.

### tenant identifier-ის შედარება თქვენს ანგარიშის handle-თან {#match-the-tenant-identifier}

`KURA_TENANT_ID` უნდა ემთხვეოდეს თქვენს Tuist ანგარიშის handle-ს. control plane ადარებს heartbeat-ის tenant-ს credential-დან ამოხსნილ ანგარიშს და უარყოფს შეუსაბამობას `409 tenant_mismatch`-ით, ამიტომ კვანძი არასწორი მნიშვნელობით წარმატებით ავტორიზდება, მაგრამ მაინც ვერ რეგისტრირდება.

> [!IMPORTANT]
> როგორც Helm chart, ისეც ამ სახელმძღვანელოში ადრე მოყვანილი container მაგალითი ამას default-ად აყენებს `default`-ზე. ეს მნიშვნელობა სწორია self-hosted Tuist server-ისთვის, სადაც tenant არის ლოკალური label, და არასწორია Tuist-hosted server-ზე არსებული ანგარიშისთვის, სადაც მან უნდა დაასახელოს ანგარიში. კვანძის რეგისტრაცია სრულიად თავს არიდებს ამ საკითხს, რადგან control plane აწვდის მნიშვნელობას.

დაუყენებელი `KURA_TENANT_ID` არ ტოვებს შემოწმებას. ის სრულიად თიშავს რეგისტრაციას: კვანძი აგრძელებს cache ტრაფიკის მომსახურებას, dashboard-ში არაფერი ჩანს და არანაირი შეცდომა არ ანგარიშდება. თუ კვანძი ჯანმრთელია, მაგრამ აკლია **Registered nodes**-ს, პირველ რიგში შეამოწმეთ ეს ცვლადი.

### აირჩიეთ რეკლამირებული URL, რომელსაც თქვენი კლიენტები მიაღწევენ {#choose-an-advertised-url}

გამოიყენეთ კლიენტისთვის ხელმისაწვდომი მისამართი `KURA_ADVERTISED_HTTP_URL`-ისთვის და Tuist server-ზე ან CLI-ზე კონფიგურირებული cache URL-ისთვის.

მხოლოდ შიდა hostname შესაფერისია, როცა ყველა კლიენტი, რომელიც კონფიგურირებულია მის გამოყენებაზე, შეუძლია ამ სახელის გადარჩევა და მიღწევა. სხვადასხვა ქსელში მყოფი კლიენტებისთვის, გამოიყენეთ საერთო ხელმისაწვდომი მისამართი ან დააკონფიგურირეთ ხელმისაწვდომი cache კვანძი თითოეული გარემოსთვის.

## cache mesh-ის აგება {#build-a-cache-mesh}

cache mesh საშუალებას გაძლევთ cache-ის შესაძლებლობები განათავსოთ იმ გამოთვლითი რესურსების გვერდით, რომლებსაც ის სჭირდება. კომპანიამ შეიძლება ერთი კვანძი გაუშვას ძირითად CI runner-ებთან ახლოს, მეორე ევროპაში მყოფ დეველოპერებთან ახლოს, ხოლო მესამე აშშ-ის ოფისთან ან რეგიონულ build cluster-თან ახლოს. თითოეული ლოკაცია კითხულობს და წერს უახლოეს კვანძზე, ხოლო Kura ფონურად ახდენს არტიფაქტებისა და მეტამონაცემების რეპლიკაციას, რათა მოგვიანებით სხვა ლოკაციებში შესრულებულმა builds-მა შეძლოს იგივე გამომავალი მონაცემების ხელახლა გამოყენება.

mesh მხოლოდ მაშინ მუშაობს, თუ კვანძებს შეუძლიათ ერთმანეთთან დაკავშირება Kura-ს შიდა peer პორტზე. ეს peer სიბრტყე გამოყოფილია იმ საჯარო cache endpoint-ებისგან, რომლებსაც Tuist კლიენტები იყენებენ. Kura მას იყენებს წევრობის შესამოწმებლად, ახლად შემოერთებული კვანძების backfill-ისთვის და არტიფაქტების რეპლიკაციისთვის მას შემდეგ, რაც ლოკალური ჩაწერები მიღებული იქნება.

ჩვენ მკაცრად გირჩევთ peer სიბრტყის დაცვას [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication)-ით, როდესაც კვანძები ერთმანეთთან კომუნიკაციას ახდენენ რეგიონებს, cloud-ებს, VPC-ებს, ოფისებს ან ნებისმიერ ქსელს შორის, რომელიც არ არის სრულად იზოლირებული cache განლაგებისთვის. mTLS ჩართვისას, Kura შიდა რეპლიკაციის endpoint-ებს მხოლოდ იმ peer-ებს აწვდის, რომლებიც წარმოადგენენ კონფიგურირებული CA-ს მიერ ხელმოწერილ სერტიფიკატს. peer სერტიფიკატებმა უნდა მოიცვას DNS სახელები, რომლებსაც კვანძები ერთმანეთის გამოსაძახებლად იყენებენ, და peer URL-ებმა შიდა პორტზე უნდა გამოიყენონ `https://`.

> [!NOTE]
> კვანძები, რომლებიც რეგისტრირდებიან Tuist-hosted control plane-ზე, რეგისტრაციის დროს იღებენ თავიანთ peer სერტიფიკატს და ანგარიშის CA-ს, ამიტომ ქვემოთ მოყვანილი ხელით შესრულებული ნაბიჯები ეხება იმ mesh-ებს, რომლებიც არ რეგისტრირდებიან.

მაგალითად, ეს ქმნის პირად CA-ს და ერთ peer სერტიფიკატს, რომლის mount-იც შეუძლია მცირე mesh-ის ყოველ კვანძს. შეცვალეთ DNS სახელები იმ შიდა სახელებით, რომლებსაც თქვენი კვანძები იყენებენ `KURA_NODE_URL`-ში და `KURA_PEERS`-ში.

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

### კვანძებს შორის სინქრონიზაცია {#catch-up-between-nodes}

კვანძი, რომელიც join-დება ან ხელახლა join-დება mesh-ში, ასრულებს **backfill**-ს: ის გადახედავს თითოეული peer-ის ჩანაწერებს უახლესიდან დაწყებით და გადმოწერს იმას, რაც აკლია, ხოლო ცოცხალი რეპლიკაცია ფარავს ჩაწერებს, რომლებიც შესრულდა peer-ის ხილვადობის პერიოდში. backfill-ის ციკლი ბრუნდება peer-ის უახლესი ჩანაწერიდან კვანძის segment-ring ჰორიზონტამდე ან მის ბოლო დასრულებულ ციკლამდე (ვინაიდან უფრო ძველია), რაც ნიშნავს, რომ კვანძს გარანტირებულად აქვს უახლესი მონაცემები, თუმცა არა აუცილებლად ყველა მონაცემი. `KURA_BACKFILL_MARGIN_PERCENT` განსაზღვრავს, თუ რამდენად შორს მდებარეობს ჰორიზონტი.

ორი შედეგია, რომლის ცოდნაც ღირს mesh-ის გაშვებამდე:

- კვანძი ანგარიშობს `/ready`-ს, როგორც კი მისი segment ring შეივსება `KURA_BACKFILL_READY_RING_PERCENT`-ით **ან** მისი პირველი backfill ციკლი დასრულდება, და მზაობა ნარჩუნდება პროცესის სიცოცხლის დარჩენილ ნაწილში. მოგვიანებით peer-ის გათიშვა არასდროს გამოიყვანს მომსახურე კვანძს როტაციიდან.
- ციკლი ასევე სრულდება, როდესაც peer საკმარისად დიდი ხნით მიუწვდომელია. კვანძი, რომლის ერთადერთი peer გათიშულია, ამიტომ ხდება Ready, თუმცა მას თითქმის არ აქვს მონაცემები ან საერთოდ არ აქვს. ის ამუშავებს cache miss-ებს შეცდომების ნაცვლად. `/status/rollout` ანგარიშობს `backfill_initial_cycle`-ს (`pending`, `complete` ან `degraded`), თუ განლაგების განსხვავებაზე გსურთ rollout-ის შეჩერება.

**mesh-ის განახლება backfill-ის ცვლილების დროს.** Kura-ს იმ ვერსიებამდე, სადაც backfill იყო, სინქრონიზაცია ხდებოდა სხვა, ახლა უკვე ამოღებული peer პროტოკოლით. გადაიყვანეთ ყოველი კვანძი ისეთ ვერსიაზე, რომელიც ასრულებს backfill-ს **მანამ**, სანამ აიღებთ ვერსიას, რომელიც მხოლოდ backfill-ს იყენებს. ორივე პროტოკოლზე მყოფ კვანძებს ერთმანეთთან სინქრონიზაცია არ შეუძლიათ: „თბილი“ კვანძი აგრძელებს მომსახურებას თავისი volume-დან, მაგრამ წყვეტს სხვაობის აღმოფხვრას, ხოლო კვანძი, რომელიც ამ პერიოდში იწყება ცარიელი volume-ით, არასდროს ხდება Ready. chart თქვენთვის აყენებს `KURA_BACKFILL_ENABLED=true`-ს, ამიტომ chart-ის პირველადი განახლება ფარავს ამ საკითხს. ერთი `helm upgrade`, რომელიც ერთდროულად ცვლის chart-ს და image-ს, ამას არ აკეთებს.

გამოიყენეთ ქსელის დონის შეზღუდვები mTLS-ის დამატებით. Kubernetes-ში, გაუშვით Kura როგორც `StatefulSet`, თითოეული pod-ისთვის ერთი persistent volume-ით და headless service-ით peer-ების აღმოჩენისთვის, შემდეგ კი დაუშვით შიდა peer პორტი მხოლოდ იმ pod-ებს შორის, რომლებიც ერთი და იმავე cache განლაგებას ეკუთვნის, მაგალითად, `NetworkPolicy`-ის გამოყენებით. Kubernetes-ის გარეთ, მიანიჭეთ თითოეულ კვანძს სტაბილური DNS სახელი ან IP მისამართი, შეავსეთ mesh სხვა კვანძების შიდა URL-ებით და გამოიყენეთ firewall წესები ან security groups ისე, რომ მხოლოდ cache კვანძებს შეეძლოთ peer პორტთან მიღწევა. საჯარო cache ტრაფიკი უნდა შედიოდეს საჯარო HTTP ან gRPC endpoint-ების მეშვეობით და არა შიდა peer სიბრტყის მეშვეობით.

## კონფიგურაცია {#configuration}

Helm chart აგენერირებს ზოგად runtime პარამეტრებს `values.yaml`-დან. თუ Kura-ს Kubernetes-ის გარეშე აშვებთ, დააყენეთ იგივე ცვლადები პირდაპირ პროცესზე. ცვლადები, რომლებსაც chart პირდაპირ არ ასახავს, შეიძლება ჩაირთოს `extraEnv` ან `extraEnvFrom`-ის მეშვეობით.

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმები | Helm მნიშვნელობა |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | საჯარო cache პორტი. ერთი listener ემსახურება HTTP cache API-ს, health endpoint-ებს და Bazel/Buck2 REAPI gRPC-ს (h2c). | კი | ნაგულისხმები არ აქვს | `service.httpPort` |
| `KURA_INTERNAL_PORT` | შიდა HTTP ან mTLS პორტი, რომელსაც Kura peer-ები იყენებენ. | კი | ნაგულისხმები არ აქვს | `peerTls.internalPort` |
| `KURA_TENANT_ID` | კვანძის ნაგულისხმები tenant იდენტიფიკატორი. | კი | ნაგულისხმები არ აქვს | `config.tenantId` |
| `KURA_REGION` | რეგიონის label, რომელიც გამოიყენება მეტრიკებსა და რეპლიკაციის მდგომარეობაში. | კი | ნაგულისხმები არ აქვს | `config.region` |
| `KURA_TMP_DIR` | დროებითი დირექტორია staged request bodies-ისა და multipart assembly-ისთვის. | კი | ნაგულისხმები არ აქვს | ფიქსირებულია `/var/cache/kura/tmp`-ზე |
| `KURA_TMP_DIR_MAX_BYTES` | მაქსიმალური staged byte-ები, რომლებიც დაიშვება `KURA_TMP_DIR`-ში, სანამ requests მიიღებენ backpressure-ს. | არა | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | მუდმივი დირექტორია მეტამონაცემების მდგომარეობისა და segment ფაილებისთვის. | კი | ნაგულისხმები არ აქვს | ფიქსირებულია `/var/cache/kura`-ზე |
| `KURA_NODE_URL` | კანონიკური შიდა URL, რომელსაც სხვა peer-ები იყენებენ ამ კვანძთან მისასვლელად. | კი | ნაგულისხმები არ აქვს | მიღებულია pod-ის DNS სახელიდან და `peerTls.internalPort`-დან |
| `KURA_PEERS` | Seed peer-ების სია, რომელიც გამოიყენება discovery-ის კონვერგენციამდე. | არა | `KURA_NODE_URL` | მიღებულია StatefulSet-ის რეპლიკებიდან |
| `KURA_DISCOVERY_DNS_NAME` | DNS სახელი, რომელიც გამოიყენება ავტომატური peer discovery-ისთვის. | არა | გამორთულია | ჩართულია `config.discovery.enabled`-ით |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | CA სერთიფიკატი, რომელიც გამოიყენება peer mTLS-ის ვერიფიკაციისთვის. | არა | გამორთულია, ან მიღებულია `KURA_DATA_DIR`-ში, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | სერთიფიკატი, რომელიც გამოიყენება შიდა peer mTLS listener-ისთვის. | არა | გამორთულია, ან მიღებულია `KURA_DATA_DIR`-ში, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | კერძო გასაღები, რომელიც გამოიყენება შიდა peer mTLS listener-ისთვის. | არა | გამორთულია, ან მიღებულია `KURA_DATA_DIR`-ში, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | სერთიფიკატი, რომელიც გამოიყენება TLS-ის დასასრულებლად თანამონათავსებულ HTTPS listener-ზე (`KURA_HTTPS_PORT`). | არა | გამორთულია | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | კერძო გასაღები, რომელიც შეესაბამება `KURA_PUBLIC_TLS_CERT_PATH`-ს. | არა | გამორთულია | `extraEnv` |
| `KURA_HTTPS_PORT` | TLS პორტი, რომელიც ემსახურება იგივე თანამონათავსებულ HTTP + gRPC ზედაპირს (ALPN-შეთანხმებული). იბმება მხოლოდ მაშინ, როდესაც საჯარო TLS გზები დაყენებულია. | არა | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | Plaintext HTTP/2 პორტი, რომელიც ემსახურება მხოლოდ gRPC API-ებს, proxy-ებისთვის, რომლებიც ხელახლა იყენებენ upstream კავშირებს. იხილეთ [კვანძების load balancer-ის უკან განთავსება](#load-balancers). | არა | გამორთულია | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | File-descriptor ბიუჯეტი request-ებისა და ფონური I/O-სთვის. | არა | ავტომატურად მიღებული | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | რამდენ ხანს ელოდება request, სანამ FD backpressure ჩაშლის checkout-ს. | არა | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | პინირებული სეგმენტის წაკითხვის handle-ების მაქსიმალური რაოდენობა. | არა | ავტომატურად მიღებული | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | შეწყვეტის დროს in-flight HTTP და gRPC სამუშაოსთვის განკუთვნილი გრეის პერიოდი. | არა | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | მეხსიერების რბილი ზღვარი, სადაც Kura იწყებს არასავალდებულო მეხსიერების გამოყენების შემცირებას. | არა | ავტომატურად მიღებული | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | მეხსიერების მკაცრი ზღვარი, სადაც Kura აჩერებს რეპლიკაციას და ამცირებს ცხელ cache-ებს. | არა | ავტომატურად მიღებული | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | მეხსიერებაში მყოფი manifest cache-ის მაქსიმალური ზომა. | არა | ავტომატურად მიღებული | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | keyvalue payload-ის მაქსიმალური ზომა ერთ request-ზე. | არა | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | metadata store-ისთვის გამოყოფილი file descriptor ბიუჯეტი. | არა | ავტომატურად მიღებული | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | მეტამონაცემთა საცავის ფონური flush-ისა და კომპაქციის კონკურენტულობა. | არა | ავტომატურად მიღებული | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | მეტამონაცემთა საცავის წაკითხვის cache-ის ტევადობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | მეტამონაცემთა ჩაწერის ბუფერიზაციისთვის გამოყოფილი მეხსიერების საერთო ბიუჯეტი. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | თითოეული metadata write buffer-ის ზომა flush-ამდე. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | მეხსიერებაში შენახული metadata write buffer-ების მაქსიმალური რაოდენობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | რამდენ ხანს შეიძლება დარჩეს მიმდინარე multipart upload ვადის გასვლამდე. | არა | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | რამდენად ხშირად ამოწმებს Kura მოძველებულ multipart uploads-ებს. | არა | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | ასაკის მიხედვით დალაგებული სეგმენტური რგოლის წილი, რომელიც ითვლება უახლესიდან და განსაზღვრავს, თუ რამდენად შორს აღწევს backfill pass. | არა | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | სეგმენტური რგოლის შევსების დონე, რომლის დროსაც კვანძი, რომელიც ჯერ კიდევ ასრულებს თავის პირველ backfill ციკლს, საკუთარ თავს მზადყოფნაში აცხადებს. | არა | `KURA_BACKFILL_MARGIN_PERCENT`-ის ნახევარი | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | ბაიტების ზღვარი, რომლის მიხედვითაც იქმნება ერთი backfill bodies batch და ზომა, რომლის ზემოთაც ჩანაწერი ცალ-ცალკე იტვირთება. | არა | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio worker ძაფების რაოდენობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP traces endpoint. დატოვეთ ცარიელი tracing-ის გასათიშად. | არა | გამორთულია | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry სერვისის სახელი. | დიახ | ნაგულისხმები არ არსებობს | Pod-ის სახელი Helm-ში |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry განლაგების გარემო. | დიახ | ნაგულისხმები არ არსებობს | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | Sentry DSN panic-ისა და შეცდომების შესახებ ანგარიშგებისთვის. | არა | გამორთულია | `extraEnv` ან `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | ISO 3166-1 alpha-2 ქვეყანა, სადაც კვანძი მუშაობს, ექსპორტირებულ traces-ზე ბეჭდებავს როგორც `geo.country.iso_code`. | არა | მიღებულია `KURA_REGION`-დან, როცა მისი პრეფიქსი ქვეყნის კოდია | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | იმ მონაცემთა ცენტრის ISO 3166-2 ქვედანაყოფი (მაგ., `US-CA`), ბეჭდებავს როგორც `geo.region.iso_code`. | არა | არ არის მითითებული | `extraEnv` |
| `KURA_AUTH_ENABLED` | მოითხოვს, რომ გამომძახებელმა წარადგინოს მოქმედი Tuist ტოკენი. `KURA_AUTH_TUIST_URL`-ის დაყენება თავისთავად რთავს ავტორიზაციას და ამის `false`-ზე დაყენება არ თიშავს მას უკან — URL-ის გასუფთავება საჭიროა კვანძის ავტორიზაციის გარეშე გასაშვებად. | არა | გამორთულია | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | Tuist სერვერი, რომლის წინააღმდეგაც კვანძი ახდენს ავტორიზაციას. თავისთავად რთავს ავტორიზაციას. | სავალდებულოა, როცა ავტორიზაცია ჩართულია | ნაგულისხმები არ არსებობს | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | კავშირის timeout იმ სერვერთან ზარებისთვის. | არა | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | Request timeout იმ სერვერთან ზარებისთვის. | არა | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | გაზიარებული საიდუმლო ტოკენებისთვის, რომელთა წაკითხვაც კვანძს შეუძლია დამატებითი round trip-ის გარეშე. ის ასევე აწერს ხელს და ამოწმებს, ამიტომ გამოიყენეთ მხოლოდ იქ, სადაც კვანძი და სერვერი ერთი და იგივე ნდობის საზღვარშია. Self-hosted კვანძები ჩვეულებრივ ტოვებენ ამას მითითების გარეშე. | არა | გამორთულია | `extraEnv` ან `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | საჯარო ნახევარი იმ გასაღებების წყვილისა, რომლითაც სერვერი ხელს აწერს cache ტოკენებს, ერთი ან რამდენიმე შეერთებული PEM ბლოკის სახით. კითხულობს ამ ტოკენებს მათი შექმნის შესაძლებლობის გარეშე, რაც ინტერნეტიდან ხელმისაწვდომმა კვანძმა უნდა შეიცავდეს. ურთიერთგამომრიცხავია `KURA_AUTH_JWT_SECRET`-თან. | არა | გამორთულია | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | ალგორითმი იმ გასაღებისთვის: `HS256`, `HS384` ან `HS512` საიდუმლოსთან ერთად, `ES256` საჯარო გასაღებთან ერთად. | არა | `HS256` საიდუმლოსთან ერთად, `ES256` საჯარო გასაღებთან ერთად | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | გამომცემელი, რომელიც ტოკენებმა უნდა შეიცავდნენ. | არა | შეუმოწმებელი | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | მძიმეებით გამოყოფილი აუდიტორიები, რომლებიც ტოკენებმა უნდა შეიცავდნენ. | არა | შეუმოწმებელი | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | მაქსიმალური ჩანაწერები, რომლებიც ინახება ავთენტიკაციისა და ავტორიზაციის თითოეულ cache-ში. | არა | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | არეგისტრირებს კვანძს control plane-ზე ყოველ ჩატვირთვაზე, აწვდის peer სერტიფიკატს და აწვდის `KURA_TENANT_ID` და `KURA_PEERS`. | არა | გამორთულია | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | Tuist სერვერი, რომლის წინააღმდეგაც კვანძი რეგისტრირდება. | სავალდებულოა რეგისტრაციისას | ნაგულისხმები არ არსებობს | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | კვანძის კრედენციალის Client ID, რომელიც გენერირდება dashboard-ში. | სავალდებულოა რეგისტრაციის ან დარეგისტრირებისას | ნაგულისხმები არ არსებობს | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | Client secret, რომელიც შეწყვილებულია `KURA_CONTROL_PLANE_CLIENT_ID`-თან. | სავალდებულოა რეგისტრაციის ან დარეგისტრირებისას | ნაგულისხმები არ არსებობს | `extraEnv` |
| `KURA_REGISTRATION_URL` | აბსოლუტური URL, რომელზეც კვანძი აგზავნის რეგისტრაციის heartbeat-ებს, რეკლამირებს თავის client-facing endpoint-ს. | სავალდებულოა რეგისტრაციისას | ნაგულისხმები არ არსებობს | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | client-facing cache URL, რომელსაც control plane აწვდის კლიენტებს. უნდა იყოს ხელმისაწვდომი ანგარიშის ყოველი კლიენტისთვის. | სავალდებულოა რეგისტრაციისას | ნაგულისხმები არ არსებობს | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | რეგისტრაციის heartbeat-ის სიხშირე. lease მოიცავს რამდენიმე გამოტოვებულ heartbeat-ს, ამიტომ ერთი გამოტოვებული heartbeat არ აშორებს endpoint-ს. | არა | `60000` | `extraEnv` |

თუ შიდა peer mTLS-ს ჩართავთ, ერთად დააყენეთ `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH` და `KURA_INTERNAL_TLS_KEY_PATH`. `KURA_NODE_URL` და `KURA_PEERS`-ში ყოველი მნიშვნელობა მაშინ უნდა იყენებდეს `https://`-ს შიდა peer პორტთან ერთად.
