---
{
  "title": "თვითმასპინძელი ქეში",
  "titleTemplate": ":title | ქეში | სახელმძღვანელოები | Tuist",
  "description": "გაშალეთ თვითმასპინძელი ქეშის კვანძები და დააკავშირეთ ისინი Tuist-თან."
}
---

# თვითმასპინძელი ქეში {#self-hosted-cache}

თვითმასპინძელი ქეშის კვანძები საშუალებას გაძლევთ ბილდის არტეფაქტები და ქეშის მეტამონაცემები შეინახოთ იმ მანქანებთან ახლოს, რომლებიც წარმოქმნიან და მოიხმარენ ბილდის შედეგებს. გამოიყენეთ ისინი მაშინ, როცა ქეშის ლატენტობა მნიშვნელოვანია CI-ს, დეველოპერების ოფისების, დისტანციური სამუშაო სადგურების ან რეგიონული გამოთვლითი კლასტერების მასშტაბით.

მიზანია დაბალი ლატენტობის ქეშირება ყველგან, არა მხოლოდ იმ ერთ გარემოში, სადაც ცენტრალური ქეში შემთხვევით ახლოსაა. თითოეული ქეშის კვანძი ემსახურება წაკითხვებსა და ჩაწერებს ლოკალური დისკიდან, ხოლო mesh-ი ართეფაქტებსა და მეტამონაცემებს ასლების სახით გადასცემს პირებს შორის, რათა სხვა ლოკაციებმაც დროთა განმავლობაში მიიღონ სარგებელი იმავე ქეშიდან.

> [!NOTE]
> Tuist-ის თვითმასპინძელი ქეშის კვანძებს ამუშავებს [Kura](https://github.com/tuist/tuist/tree/main/kura), Tuist-ის დეცენტრალიზებული ქეშის mesh-ი. Kura არის ქეშის კვანძების მონაცემთა ფენა: ის ემსახურება ქეშის წაკითხვებსა და ჩაწერებს, ინახავს ლოკალურ მდგომარეობას დისკზე და ასლების სახით გადასცემს არტეფაქტებსა და მეტამონაცემებს მეზობელ კვანძებს.

## როგორ ერწყმის თვითმასპინძელი ქეში Tuist-ს {#how-self-hosted-cache-fits-with-tuist}

Tuist-ის მართული ქეში იყენებს `https://<account>.cache.tuist.dev`. თვითმასპინძელი Tuist სერვერის შემთხვევაში, CLI იღებს ქეშის URL-ს სერვერის `TUIST_CACHE_ENDPOINTS` პარამეტრიდან. მიანიჭეთ მას თქვენი ძირითადი ქეშის სერვერის ან load balancer-ის URL. თუ ის შეიცავს რამდენიმე URL-ს, გამოიყენება პირველი.

**hosted Tuist server**-თან დაკავშირებული პირადი/მორგებული ქეშის კვანძებისთვის, დააყენეთ ცალსახა endpoint დეველოპერების shell-ებში და CI-ში:

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

ეს გადაფარვა უპირატესობას იღებს ორივე ტიპის სერვერზე და არის არასავალდებულო თვითმასპინძელი Tuist სერვერებისთვის. Xcode ქეშის daemon-ისთვის, მისი დაყენების შემდეგ ხელახლა გაუშვით `tuist setup cache`, რათა LaunchAgent-მა მიიღოს განახლებული გარემო.

თვითმასპინძელი Tuist სერვერი იღებს endpoints სტატიკური კონფიგურაციიდან. Tuist-ის მიერ მასპინძელ სერვერზე, კვანძები ავტორიზაციას გადიან credential-ით და რეგისტრირდებიან. ჯერ განათავსეთ კვანძი ქვემოთ მოცემული ორი სექციიდან ერთ-ერთის გამოყენებით, შემდეგ იხილეთ [Connect nodes to Tuist](#connect-nodes-to-tuist).

## განთავსება Kubernetes-ზე {#deploy-on-kubernetes}

Kura ვრცელდება Helm chart-ის სახით GitHub Container Registry-ის მეშვეობით. ის აყენებს Kura-ს როგორც `StatefulSet` persistent volumes-ით, headless სერვისით peer-ების აღმოსაჩენად და ჩვეულებრივი სერვისით HTTP და gRPC ტრაფიკისთვის.

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

იმავე კლასტერში მყოფი თვითმასპინძელი Tuist სერვერისთვის, დააკონფიგურირეთ მისი ძირითადი ქეშის endpoint:

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

ეს აყენებს `TUIST_CACHE_ENDPOINTS` სერვერის pod-ში. გამოიყენეთ მისამართი, რომელზეც წვდომა აქვთ დეველოპერების მანქანებს და CI-ს; ზემოთ მოცემული კლასტერ-ლოკალური სერვისის სახელი შესაფერისია კლასტერის შიგნით მომუშავე კლიენტებისთვის.

> [!IMPORTANT]
> თითოეულ Kura კვანძს უნდა ჰქონდეს საკუთარი `KURA_DATA_DIR`. Kura იღებს აპლიკაციის დონის ჩაწერის ბლოკირებას მონაცემთა დირექტორიაზე და ელის, რომ ზუსტად ერთი პროცესი ფლობდეს მას. Kubernetes-ში, გამოიყენეთ ერთი persistent volume თითო pod-ზე. Kubernetes-ის გარეთ, არ მიუთითოთ რამდენიმე პროცესი ერთსა და იმავე mounted დირექტორიაზე.

## განთავსება Kubernetes-ის გარეშე {#deploy-without-kubernetes}

Kura ასევე შეიძლება გაეშვას როგორც ჩვეულებრივი კონტეინერი VM-ებზე ან bare-metal ჰოსტებზე. ამ რეჟიმში, თქვენ ხართ პასუხისმგებელი პროცესების მონიტორინგზე, მუდმივ შენახვაზე, მარშრუტიზაციაზე და peer-ების აღმოჩენაზე.

მინიმუმ, თითოეულ კვანძს სჭირდება მუდმივი მონაცემთა დირექტორია, დროებითი დირექტორია, საჯარო ქეშის პორტი (ერთი listener ემსახურება როგორც HTTP cache API-ს, ასევე REAPI gRPC-ს), შიდა peer URL და ან სტატიკური peer-ების სია, ან აღმოჩენის მექანიზმი:

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

თვითმასპინძელ Tuist სერვერზე, დააკონფიგურირეთ ძირითადი ქეშის URL, რომელზეც წვდომა აქვთ დეველოპერების მანქანებს და CI-ს:

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## კვანძების load balancer-ის უკან განთავსება {#load-balancers}

კლიენტები იყენებენ თითოეულ ქეშის endpoint URL-ს როგორც HTTP-ის, ასევე gRPC-ისთვის: HTTP ჯანმრთელობის შემოწმებებისა და HTTP cache API-ისთვის, ხოლო gRPC მოდულის ქეშისა და Bazel-ის remote cache-ისთვის. ნებისმიერ ingress-ს, load balancer-ს ან CDN-ს კლიენტებსა და Kura-ს შორის უნდა გადაამისამართოს ორივე ერთსა და იმავე hostname-ზე და პორტზე. ეს ვრცელდება ყველა endpoint-ზე, რომელსაც კლიენტები იღებენ, რადგან CLI ირჩევს იმას, რომელიც ყველაზე სწრაფად პასუხობს. თუ gRPC ვერ აღწევს Kura-ს, CLI აფრთხილებს, რომ remote module caching არ არის ხელმისაწვდომი და იყენებს მხოლოდ ლოკალურ მოდულის ქეშს.

მიმართეთ ეს path prefix-ები Kura-სკენ როგორც gRPC HTTP/2-ზე, ხოლო ყველაფერი დანარჩენი როგორც HTTP:

| Path prefix | გამოიყენება |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | Module cache, Bazel |
| `/google.bytestream.` | Module cache, Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel build events |

Kura იღებს plaintext HTTP/2-ს (h2c) `KURA_PORT`-ზე და HTTP/2-ს TLS-ზე `KURA_HTTPS_PORT`-ზე, როცა `KURA_PUBLIC_TLS_CERT_PATH` და `KURA_PUBLIC_TLS_KEY_PATH` დაყენებულია. თუ თქვენი proxy ხელახლა იყენებს upstream კავშირებს მოთხოვნებს შორის, როგორც ingress-nginx აკეთებს, დააყენეთ `KURA_GATEWAY_GRPC_PORT` და გაუგზავნეთ gRPC ტრაფიკი იმ პორტზე. ის ემსახურება მხოლოდ gRPC-ს, ამიტომ HTTP/1.1 და gRPC მოთხოვნები არასდროს იზიარებენ კავშირს.

დააკონფიგურირეთ gRPC მარშრუტები:

- მოთხოვნის სხეულის ზომის შეზღუდვის გარეშე. ატვირთვა აგზავნის ერთ ფაილს ერთ მოთხოვნაში, 2 GiB-მდე.
- მოთხოვნისა და პასუხის ბუფერიზაცია გამორთულია.
- წაკითხვის, გაგზავნის და idle timeout-ები მინიმუმ 300 წამი.

Kura არ ემსახურება gRPC ჯანმრთელობის შემოწმების სერვისს. შეამოწმეთ კვანძების ჯანმრთელობა HTTP-ით `/ready`-ზე. თუ თქვენი load balancer მოითხოვს gRPC ჯანმრთელობის შემოწმებას, გამოიძახეთ `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` და მიიღეთ gRPC სტატუსის კოდები `0` და `16`. ავტორიზაციის ჩართული კვანძი პასუხობს მოთხოვნას token-ის გარეშე `16`-ით (`UNAUTHENTICATED`).

### ingress-nginx {#load-balancers-ingress-nginx}

Helm chart-ის გამოყენებით, შეინარჩუნეთ HTTP ingress `/`-ზე და დაამატეთ gRPC ingress იმავე host-ისთვის. მხოლოდ HTTP ingress აცხადებს TLS-ს:

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

1. გადამისამართეთ default rule target group-ზე protocol version `HTTP1`-ით `KURA_PORT`-ზე, ჯანმრთელობის შემოწმებით HTTP-ით `/ready`-ზე.
2. შექმენით მეორე target group protocol version `gRPC`-ით, protocol `HTTP`-ის გამოყენებით `KURA_GATEWAY_GRPC_PORT`-ზე (ან `KURA_PORT`-ზე), ან protocol `HTTPS` `KURA_HTTPS_PORT`-ზე. დააკონფიგურირეთ მისი ჯანმრთელობის შემოწმება ზემოთ აღწერილი წესით.
3. დაამატეთ წესი, რომელიც გადაამისამართებს path patterns `/build.bazel.remote.execution.v2.*`, `/google.bytestream.*`, `/build.bazel.remote.asset.v1.*` და `/google.devtools.build.v1.*` მეორე target group-ზე.
4. გაზარდეთ load balancer-ის idle timeout მინიმუმ 300 წამამდე.

### CDN-ები {#load-balancers-cdns}

კვანძის წინ მდებარე CDN-მა უნდა მხარი დაუჭიროს gRPC-ს და არ დაბლოკოს gRPC მარშრუტები თავის firewall წესებში. კლიენტები ტვირავენ დიდ არტიფაქტებს მაქსიმუმ 2 MiB ზომის ნაწილებად და აწყობენ მათ კვანძზე, ამიტომ არცერთ მოთხოვნას არ სჭირდება დიდი სხეული ან ხანგრძლივი ატვირთვა. მოდულის ქეში და Xcode კომპილაციის ქეში ასე იქცევიან, ისევე როგორც Bazel, თუ აგებულია `--experimental_remote_cache_chunking` ფლაგით (Bazel 8.7 და 9.1 ან უფრო გვიანი). ამ ფლაგის გარეშე, Bazel ტვირავენ თითოეულ გამოტანას ერთ მოთხოვნაში, ამიტომ CDN-მა ასევე უნდა დაუშვას დიდი მოთხოვნის სხეულები და ატვირთვები, რომლებიც იმდენ ხანს გრძელდება, რამდენსაც თქვენი უდიდესი გამოტანები საჭიროებენ თქვენს ყველაზე ნელ ბმულზე. თუ თქვენი CDN ვერ აკმაყოფილებს ამ მოთხოვნებს, მიეცით კლიენტებს hostname, რომელიც აუვლის მას გვერდს, მაგალითად, მხოლოდ DNS ჩანაწერი.

#### Cloudflare {#load-balancers-cloudflare}

მოდულის ქეშირება მუშაობს proxied Cloudflare hostname-ის მეშვეობით ნებისმიერ გეგმაზე. ზონაში:

1. **Network**-ის ქვეშ, ჩართეთ **gRPC**.
2. **SSL/TLS**-ის ქვეშ, დააყენეთ encryption mode **Full**-ზე ან **Full (strict)**-ზე. Cloudflare უკავშირდება origin-ს 443 პორტზე, ამიტომ origin-მა უნდა მიწოდოს TLS იქ და შესთავაზოს HTTP/2 ALPN-ის მეშვეობით.
3. დარწმუნდით, რომ არცერთი WAF custom rule ან managed rule არ ბლოკავს ზემოთ ჩამოთვლილ gRPC მარშრუტებს.

Cloudflare ასრულებს მოთხოვნას, თუ origin-მა დაახლოებით ორი წუთის განმავლობაში არ დაიწყო პასუხის გაგზავნა. Bazel ატვირთვა `--experimental_remote_cache_chunking`-ის გარეშე იღებს პასუხს მხოლოდ მისი ბოლო ბაიტის მიღების შემდეგ, ამიტომ Cloudflare-ზე ასეთი ატვირთვები ვერ ხერხდება, თუ ისინი ამ დროზე მეტს გრძელდება.

## კვანძების დაკავშირება Tuist-თან {#connect-nodes-to-tuist}

დააკონფიგურირეთ კლიენტის მარშრუტიზაცია და დარეგისტრირეთ თქვენი კვანძები Tuist-ში, რათა მათი მისამართები, მზადყოფნა და გამოყენება გამოჩნდეს dashboard-ზე.

**self-hosted Tuist server**-ზე, თქვენ აცხადებთ endpoint-ებს სტატიკურად `TUIST_CACHE_ENDPOINTS`-ის მეშვეობით, როგორც ნაჩვენებია ზემოთ განლაგების სექციებში. CLI იყენებს პირველ კონფიგურირებულ URL-ს. `TUIST_CACHE_ENDPOINT` გადაფარავს ამ URL-ს ინდივიდუალური კლიენტისთვის.

**Tuist-hosted server**-ზე, დააყენეთ `TUIST_CACHE_ENDPOINT` developer shells-ში და CI-ში, რათა მიმართოთ ქეშის მოთხოვნები თქვენს კვანძებზე. თითოეული კვანძი ავტორიზდება თქვენს მიერ შექმნილი credential-ით, შემდეგ რეგისტრირებს თავის მისამართს და აცნობებს თავის მზადყოფნას dashboard-ს. ეს სექცია ეხება კვანძის რეგისტრაციას.

> [!IMPORTANT]
> **Enterprise plan**
>
> Self-hosted cache კვანძები ხელმისაწვდომია Enterprise გეგმაზე. ქვემოთ აღწერილი სექცია **Self-hosted servers** ჩნდება მხოლოდ იმ ანგარიშებისთვის, რომლებიც ამ გეგმაზე არიან.

### კვანძის credential-ის გენერირება {#generate-a-node-credential}

Tuist dashboard-ში, გახსენით თქვენი ანგარიში, გადადით **Cache**-ზე და იპოვეთ **Self-hosted servers**. აირჩიეთ **Generate credential** client ID-ის და secret-ის შესაქმნელად.

credential ავტორიზებს მხოლოდ იმ ანგარიშის ტრაფიკს, რომელმაც ის შექმნა.

secret ჩანს ერთხელ და არ არის აღდგენადი დიალოგის დახურვის შემდეგ, ამიტომ პირდაპირ დააკოპირეთ ის იმ secret store-ში, საიდანაც თქვენი კვანძები კითხულობენ. credential-ის გაუქმება მყისიერად აჩერებს ყველა კვანძს, რომელიც მას იყენებს, ავტორიზაციისგან, ამიტომ შექმენით ჩამნაცვლებელი, სანამ გააუქმებთ მოქმედებაში მყოფს.

### კვანძის რეგისტრაცია ჩატვირთვისას {#enroll-the-node-on-boot}

რეგისტრაცია არის კვანძის ამუშავების რეკომენდებული გზა. დააყენეთ `KURA_ENROLL_ON_BOOT` და მიეცით კვანძს მისი credential და საკუთარი peer URL:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

კვანძი ადგილობრივად ქმნის თავის keypair-ს, ამიტომ private key არასდროს ტოვებს მას, და იღებს ხელმოწერილ peer certificate-ს, ანგარიშის CA-ს, მის tenant identifier-ს და peer list-ს. ეს არის ყველაფერი, რასაც წინააღმდეგ შემთხვევაში ხელით დააკონფიგურირებდით: რეგისტრირებულ კვანძს არ სჭირდება `KURA_TENANT_ID`, არ `KURA_PEERS` და არც peer TLS კონფიგურაცია.

დატოვეთ `KURA_INTERNAL_TLS_*` დაუყენებელი: რეგისტრაცია წერს certificate მასალას `tls` დირექტორიაში `KURA_DATA_DIR`-ის ქვეშ. დააყენეთ ეს გზები თავად მხოლოდ მაშინ, როცა თქვენ აწვდით certificate-ებს რეგისტრაციის ნაცვლად, როგორც აღწერილია [Build a cache mesh](#build-a-cache-mesh)-ში.

კვანძი, რომელიც პირველად უერთდება ანგარიშის mesh-ს, იწევს ანგარიშის არსებულ ქეშს, სანამ გახდება ring-ის მომსახურე წევრი. გამოყავით მონაცემთა მოცულობა მთელი ქეშისთვის და ელოდეთ, რომ პირველი შეერთება გარკვეულ დროს წაიღებს wide-area ბმულზე. კვანძი აცნობებს `joining`-ს, სანამ არ დაეწევა, შემდეგ `serving`-ს.

### endpoint-ის რეკლამირება {#advertise-the-endpoint}

რეგისტრაცია აერთიანებს mesh-ში. რეგისტრაცია აცნობებს კვანძის კლიენტისთვის ხილულ მისამართს და მზადყოფნას Tuist-ს. დააყენეთ რეგისტრაციის ცვლადები:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

კვანძი აგზავნის heartbeat-ს ყოველ 60 წამში 180-წამიანი lease-ის წინააღმდეგ. Tuist მიიჩნევს მის რეგისტრაციას ხელმიუწვდომლად, როცა lease იწურება. Tuist არასდროს უკავშირდება კვანძს, ამიტომ ის მხოლოდ თქვენი კლიენტებისთვის უნდა იყოს ხელმისაწვდომი, არა ინტერნეტიდან.

### დაადასტურეთ, რომ კვანძი ემსახურება {#verify-the-node-is-serving}

dashboard-ის **Cache**-ში დაბრუნებისას, კვანძი ჩანს **Registered nodes**-ის ქვეშ თავის endpoint-ით, რეგიონით, სტატუსით და ბოლო heartbeat-ით. კვანძი, რომელიც არასდროს ჩანს, ვერ აღწევს რეგისტრაციის endpoint-ს ან ვერ ავტორიზდება. კვანძი, რომელიც ჩანს და შემდეგ ქრება, შეწყვიტა heartbeat-ის გაგზავნა ან შეწყვიტა თავისი მზადყოფნის შეტყობინება.

### tenant identifier-ის შედარება თქვენს ანგარიშის handle-თან {#match-the-tenant-identifier}

`KURA_TENANT_ID` უნდა ემთხვეოდეს თქვენს Tuist ანგარიშის handle-ს. control plane ადარებს heartbeat-ის tenant-ს credential-დან ამოხსნილ ანგარიშს და უარყოფს შეუსაბამობას `409 tenant_mismatch`-ით, ამიტომ კვანძი არასწორი მნიშვნელობით წარმატებით ავტორიზდება, მაგრამ მაინც არასდროს რეგისტრირდება.

> [!IMPORTANT]
> როგორც Helm chart, ასევე ამ სახელმძღვანელოში ადრე მოყვანილი container მაგალითი ამას default-ად აყენებს `default`-ზე. ეს მნიშვნელობა სწორია self-hosted Tuist server-ისთვის, სადაც tenant არის local label, და არასწორია Tuist-hosted server-ის ანგარიშისთვის, სადაც მან უნდა დაასახელოს ანგარიში. კვანძის რეგისტრაცია სრულიად თავს არიდებს ამ საკითხს, რადგან control plane აწვდის მნიშვნელობას.

დაუყენებელი `KURA_TENANT_ID` არ ტოვებს შემოწმებას. ის სრულიად თიშავს რეგისტრაციას: კვანძი აგრძელებს ქეშის ტრაფიკის მომსახურებას, dashboard-ზე არაფერი ჩანს და არც შეცდომა იგზავნება. თუ კვანძი ჯანმრთელია, მაგრამ აკლია **Registered nodes**-ს, პირველ რიგში შეამოწმეთ ეს ცვლადი.

### აირჩიეთ რეკლამირებული URL, რომელსაც თქვენი კლიენტები მიაღწევენ {#choose-an-advertised-url}

გამოიყენეთ კლიენტისთვის ხელმისაწვდომი მისამართი `KURA_ADVERTISED_HTTP_URL`-ისთვის და Tuist server-ზე ან CLI-ზე კონფიგურირებული ქეშის URL-ისთვის.

მხოლოდ შიდა hostname შესაფერისია, როცა ყველა კლიენტი, რომელიც მის გამოყენებაზეა კონფიგურირებული, შეუძლია ამ სახელის გარჩევა და მიღწევა. სხვადასხვა ქსელში მყოფი კლიენტებისთვის, გამოიყენეთ საერთო ხელმისაწვდომი მისამართი ან დააკონფიგურირეთ ხელმისაწვდომი ქეშის კვანძი თითოეული გარემოსთვის.

## ააგეთ ქეშის mesh {#build-a-cache-mesh}

ქეშის mesh საშუალებას გაძლევთ, ქეშის სიმძლავრე განათავსოთ იმ გამოთვლითი რესურსების გვერდით, რომლებსაც ის სჭირდება. კომპანიამ შეიძლება ერთი კვანძი გაუშვას ძირითად CI runner-ებთან ახლოს, მეორე ევროპაში მყოფ დეველოპერებთან ახლოს, ხოლო მესამე — აშშ-ის ოფისთან ან რეგიონულ build cluster-თან ახლოს. თითოეული ლოკაცია კითხვებს და ჩაწერებს უახლოეს კვანძთან ასრულებს, ხოლო Kura ფონურ რეჟიმში ახდენს არტიფაქტებისა და მეტამონაცემების რეპლიკაციას, რათა სხვა ლოკაციებში მოგვიანებით შესრულებულმა builds-მა შეძლოს იგივე შედეგების ხელახლა გამოყენება.

mesh მხოლოდ მაშინ მუშაობს, თუ კვანძებს შეუძლიათ ერთმანეთთან დაკავშირება Kura-ს შიდა peer პორტზე. ეს peer სიბრტყე გამოყოფილია იმ საჯარო ქეშის endpoint-ებისგან, რომლებსაც Tuist კლიენტები იყენებენ. Kura მას იყენებს წევრობის შესამოწმებლად, ახლად შემოერთებული კვანძების backfill-ისთვის და არტიფაქტების რეპლიკაციისთვის მას შემდეგ, რაც ლოკალური ჩაწერები მიღებული იქნება.

ჩვენ მკაცრად გირჩევთ, peer სიბრტყე დაიცვათ [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication)-ით, როდესაც კვანძები ერთმანეთთან კომუნიკაციას ახდენენ რეგიონებს, ღრუბლებს, VPC-ებს, ოფისებს ან ნებისმიერ ისეთ ქსელს შორის, რომელიც არ არის სრულად იზოლირებული ქეშის განლაგებისთვის. mTLS-ის ჩართვისას, Kura შიდა რეპლიკაციის endpoint-ებს მხოლოდ იმ peer-ებს უწევს, რომლებიც წარმოადგენენ კონფიგურირებული CA-ს მიერ ხელმოწერილ სერტიფიკატს. Peer სერტიფიკატებმა უნდა მოიცვას DNS სახელები, რომლებსაც კვანძები ერთმანეთთან დასაკავშირებლად იყენებენ, ხოლო peer URL-ებმა შიდა პორტზე უნდა გამოიყენონ `https://`.

> [!NOTE]
> კვანძები, რომლებიც რეგისტრირდებიან Tuist-hosted control plane-თან, რეგისტრაციის დროს იღებენ თავიანთ peer სერტიფიკატს და ანგარიშის CA-ს, ამიტომ ქვემოთ მოყვანილი ხელით შესრულებული ნაბიჯები ეხება იმ mesh-ებს, რომლებიც არ რეგისტრირდებიან.

მაგალითად, ეს ქმნის პირად CA-ს და ერთ peer სერტიფიკატს, რომლის დამაგრებაც შეუძლია მცირე mesh-ის ყველა კვანძს. შეცვალეთ DNS სახელები იმ შიდა სახელებით, რომლებსაც თქვენი კვანძები იყენებენ `KURA_NODE_URL`-ში და `KURA_PEERS`-ში.

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

კვანძი, რომელიც უერთდება ან ხელახლა უერთდება mesh-ს, ასრულებს **backfill**-ს: ის გადახედავს თითოეული peer-ის ჩანაწერებს უახლესიდან დაწყებით და ჩამოიტანს იმას, რაც აკლია, ხოლო ცოცხალი რეპლიკაცია ფარავს იმ ჩაწერებს, რომლებიც peer-ის ხილვადობის პერიოდში შესრულდა. Backfill-ის ერთი ციკლი ვრცელდება peer-ის უახლესი ჩანაწერიდან კვანძის segment-ring-ის ჰორიზონტამდე ან ბოლო დასრულებულ ციკლამდე (რომელიც უფრო ძველია), რაც გარანტიას იძლევა, რომ კვანძს ექნება უახლესი მონაცემები, თუმცა არა აუცილებლად ყველა. `KURA_BACKFILL_MARGIN_PERCENT` განსაზღვრავს, თუ რამდენად შორს ვრცელდება ეს ჰორიზონტი.

ორი შედეგია, რომლის ცოდნაც ღირს mesh-ის გაშვებამდე:

- კვანძი აცხადებს `/ready`-ს მას შემდეგ, რაც მისი segment ring `KURA_BACKFILL_READY_RING_PERCENT`-ით ივსება **ან** მისი პირველი backfill ციკლი სრულდება, და მზაობა ნარჩუნდება პროცესის სიცოცხლის ბოლომდე. peer-ის მოგვიანებითი რყევა არასდროს აგდებს მომსახურე კვანძს როტაციიდან.
- ციკლი ასევე სრულდება, როდესაც peer საკმარისად დიდი ხნით მიუწვდომელია. შესაბამისად, კვანძი, რომლის ერთადერთი peer გამორთულია, ხდება Ready, თუმცა მას ცოტა ან საერთოდ არ აქვს მონაცემები. ის ემსახურება გამოტოვებებს (misses) და არა შეცდომებს. `/status/rollout` აცხადებს `backfill_initial_cycle`-ს (`pending`, `complete` ან `degraded`), თუ განსხვავებაზე დაყრდნობით გსურთ rollout-ის შეჩერება.

**Mesh-ის განახლება backfill-ის ცვლილების გადაკვეთით.** Backfill-ამდე გამოშვებული Kura ვერსიები სინქრონიზაციას ახდენდნენ სხვა, ახლა უკვე წაშლილი peer პროტოკოლის მეშვეობით. გადაიყვანეთ ყველა კვანძი ისეთ ვერსიაზე, რომელიც ასრულებს backfill-ს, **სანამ** გადახვალთ ისეთ ვერსიაზე, რომელიც მხოლოდ backfill-ს იყენებს. ორ სხვადასხვა პროტოკოლზე მყოფ კვანძებს ერთმანეთთან სინქრონიზაცია არ შეუძლიათ: "თბილი" კვანძი აგრძელებს მომსახურებას თავისი დისკიდან, მაგრამ წყვეტს სხვაობის აღმოფხვრას, ხოლო კვანძი, რომელიც ამ პერიოდში ცარიელი დისკით იწყებს მუშაობას, არასდროს ხდება Ready. Chart აყენებს `KURA_BACKFILL_ENABLED=true`-ს თქვენთვის, ამიტომ chart-ის პრიორიტეტული განახლება ფარავს ამ საკითხს. ერთი `helm upgrade`, რომელიც ერთდროულად ანახლებს chart-სა და image-ს, ამას არ აკეთებს.

გამოიყენეთ ქსელის დონის შეზღუდვები mTLS-ის დამატებით. Kubernetes-ში, გაუშვით Kura როგორც `StatefulSet`, თითოეული pod-ისთვის ერთი persistent volume-ით და headless service-ით peer-ების აღმოსაჩენად, შემდეგ კი დაუშვით შიდა peer პორტი მხოლოდ იმ pod-ებს შორის, რომლებიც ერთსა და იმავე ქეშის განლაგებას ეკუთვნის, მაგალითად, `NetworkPolicy`-ის გამოყენებით. Kubernetes-ის გარეთ, მიანიჭეთ თითოეულ კვანძს სტაბილური DNS სახელი ან IP მისამართი, შეავსეთ mesh სხვა კვანძების შიდა URL-ებით და გამოიყენეთ firewall-ის წესები ან security groups, რათა მხოლოდ ქეშის კვანძებმა შეძლონ peer პორტთან მიღწევა. საჯარო ქეშის ტრაფიკი უნდა შედიოდეს საჯარო HTTP ან gRPC endpoint-ების მეშვეობით და არა შიდა peer სიბრტყის გავლით.

## კონფიგურაცია {#configuration}

Helm chart აგენერირებს ზოგად runtime პარამეტრებს `values.yaml`-დან. თუ Kura-ს Kubernetes-ის გარეშე აწარმოებთ, დააყენეთ იგივე ცვლადები პირდაპირ პროცესზე. ცვლადები, რომლებსაც chart პირდაპირ არ ასახავს, შეიძლება ჩაირთოს `extraEnv`-ის ან `extraEnvFrom`-ის მეშვეობით.

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმები | Helm მნიშვნელობა |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | საჯარო ქეშის პორტი. ერთი listener ემსახურება HTTP ქეშის API-ს, health endpoint-ებს და Bazel/Buck2 REAPI gRPC-ს (h2c). | კი | ნაგულისხმები არ არის | `service.httpPort` |
| `KURA_INTERNAL_PORT` | შიდა HTTP ან mTLS პორტი, რომელსაც Kura peer-ები იყენებენ. | კი | ნაგულისხმები არ არის | `peerTls.internalPort` |
| `KURA_TENANT_ID` | კვანძის ნაგულისხმები tenant იდენტიფიკატორი. | კი | ნაგულისხმები არ არის | `config.tenantId` |
| `KURA_REGION` | რეგიონის ლეიბლი, რომელიც გამოიყენება მეტრიკებსა და რეპლიკაციის სტატუსში. | კი | ნაგულისხმები არ არის | `config.region` |
| `KURA_TMP_DIR` | დროებითი დირექტორია staged request body-ებისა და multipart assembly-ისთვის. | კი | ნაგულისხმები არ არის | მიმაგრებულია `/var/cache/kura/tmp`-ზე |
| `KURA_TMP_DIR_MAX_BYTES` | მაქსიმალური staged byte-ები, რომლებიც `KURA_TMP_DIR`-ში დაიშვება, სანამ requests backpressure-ს მიიღებენ. | არა | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | მუდმივი დირექტორია მეტამონაცემების სტატუსისა და segment ფაილებისთვის. | კი | ნაგულისხმები არ არის | მიმაგრებულია `/var/cache/kura`-ზე |
| `KURA_NODE_URL` | კანონიკური შიდა URL, რომელსაც სხვა peer-ები იყენებენ ამ კვანძთან დასაკავშირებლად. | კი | ნაგულისხმები არ არის | მიღებულია pod-ის DNS სახელიდან და `peerTls.internalPort`-დან |
| `KURA_PEERS` | Seed peer-ების სია, რომელიც გამოიყენება discovery-ის შეჯერებამდე. | არა | `KURA_NODE_URL` | მიღებულია StatefulSet რეპლიკებიდან |
| `KURA_DISCOVERY_DNS_NAME` | DNS სახელი, რომელიც გამოიყენება ავტომატური peer discovery-ისთვის. | არა | გათიშულია | ჩართულია `config.discovery.enabled`-ით |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | CA სერთიფიკატი, რომელიც გამოიყენება peer mTLS-ის დასადასტურებლად. | არა | გათიშულია, ან მიღებულია `KURA_DATA_DIR`-ქვეშ, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | სერთიფიკატი, რომელსაც იყენებს შიდა peer mTLS listener. | არა | გათიშულია, ან მიღებულია `KURA_DATA_DIR`-ქვეშ, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | პირადი გასაღები, რომელსაც იყენებს შიდა peer mTLS listener. | არა | გათიშულია, ან მიღებულია `KURA_DATA_DIR`-ქვეშ, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | სერთიფიკატი, რომელიც გამოიყენება TLS-ის დასასრულებლად ერთობლივ HTTPS listener-ზე (`KURA_HTTPS_PORT`). | არა | გათიშულია | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | პირადი გასაღები, რომელიც შეესაბამება `KURA_PUBLIC_TLS_CERT_PATH`-ს. | არა | გათიშულია | `extraEnv` |
| `KURA_HTTPS_PORT` | TLS პორტი, რომელიც ემსახურება იგივე ერთობლივ HTTP + gRPC ზედაპირს (ALPN-ით შეთანხმებული). იბმება მხოლოდ მაშინ, როდესაც დაყენებულია საჯარო TLS გზები. | არა | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | Plaintext HTTP/2 პორტი, რომელიც ემსახურება მხოლოდ gRPC API-ებს, პროქსებისთვის, რომლებიც ხელახლა იყენებენ upstream კავშირებს. იხილეთ [კვანძების განთავსება load balancer-ის უკან](#load-balancers). | არა | გათიშულია | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | File-descriptor ბიუჯეტი request-ებისა და ფონური I/O-სთვის. | არა | ავტომატურად მიღებული | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | რამდენ ხანს ელოდება request, სანამ FD backpressure ჩაშლის checkout-ს. | არა | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | პინირებული სეგმენტის წაკითხვის handle-ების მაქსიმალური რაოდენობა. | არა | ავტომატურად მიღებული | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | შეწყვეტის დროს შესრულების პროცესში მყოფი HTTP და gRPC სამუშაოსთვის განკუთვნილი გრეის პერიოდი. | არა | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | მეხსიერების რბილი ზღვარი, სადაც Kura იწყებს არააუცილებელი მეხსიერების გამოყენების შემცირებას. | არა | ავტომატურად მიღებული | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | მეხსიერების მკაცრი ზღვარი, სადაც Kura აჩერებს რეპლიკაციას და ამცირებს ცხელ კეშებს. | არა | ავტომატურად მიღებული | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | მეხსიერებაში მანტიფესტის კეშის მაქსიმალური ზომა. | არა | ავტომატურად მიღებული | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | ერთი request-ის keyvalue payload-ის მაქსიმალური ზომა. | არა | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | File descriptor ბიუჯეტი, რომელიც გამოყოფილია მეტამონაცემთა საცავისთვის. | არა | ავტომატურად მიღებული | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | ფონური flush-ისა და compaction-ის კონკურენტულობა მეტამონაცემთა საცავისთვის. | არა | ავტომატურად მიღებული | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | მეტამონაცემთა საცავის წაკითხვის კეშის ტევადობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | მეტამონაცემთა ჩაწერის ბუფერირებისთვის გამოყოფილი მთლიანი მეხსიერების ბიუჯეტი. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | თითოეული მეტამონაცემთა ჩაწერის ბუფერის ზომა flush-ამდე. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | მეტამონაცემთა ჩაწერის ბუფერების მაქსიმალური რაოდენობა, რომელიც ინახება მეხსიერებაში. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | რამდენ ხანს შეიძლება დარჩეს მიმდინარე multipart upload ვადის გასვლამდე. | არა | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | რამდენად ხშირად აკეთებს Kura სკანირებას მოძველებული multipart uploads-ისთვის. | არა | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | ასაკის მიხედვით დალაგებული სეგმენტების რგოლის წილი, რომელიც ითვლება უახლესიდან და განსაზღვრავს, თუ რამდენად შორს აღწევს backfill pass. | არა | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | სეგმენტების რგოლის შევსებულობა, რომლის დროსაც კვანძი, რომელიც ჯერ კიდევ ასრულებს პირველ backfill ციკლს, საკუთარ თავს მზადყოფნაში აცხადებს. | არა | `KURA_BACKFILL_MARGIN_PERCENT`-ის ნახევარი | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | ბაიტური ზღვარი, რომლის მიხედვითაც იქმნება ერთი backfill bodies batch, და ზომა, რომლის ზემოთაც ჩანაწერი ცალკე იტვირთება. | არა | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio worker ძაფების რაოდენობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP traces endpoint. დატოვეთ ცარიელი ტრეისინგის გასათიშად. | არა | გამორთულია | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry სერვისის სახელი. | დიახ | ნაგულისხმები არ არის | Pod-ის სახელი Helm-ში |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry განლაგების გარემო. | დიახ | ნაგულისხმები არ არის | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | Sentry DSN პანიკისა და შეცდომების შესახებ ანგარიშგებისთვის. | არა | გამორთულია | `extraEnv` ან `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | ISO 3166-1 alpha-2 ქვეყანა, სადაც კვანძი მუშაობს, რომელიც ექსპორტირებულ trace-ებზე აღბეჭდილია როგორც `geo.country.iso_code`. | არა | მიღებულია `KURA_REGION`-დან, როდესაც მისი პრეფიქსი ქვეყნის კოდია | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | იმ მონაცემთა ცენტრის ISO 3166-2 ქვედანაყოფი (მაგ., `US-CA`), რომელიც აღბეჭდილია როგორც `geo.region.iso_code`. | არა | დაყენებული არ არის | `extraEnv` |
| `KURA_AUTH_ENABLED` | მოითხოვს, რომ გამომძახებელმა წარმოადგინოს მოქმედი Tuist token. `KURA_AUTH_TUIST_URL`-ის დაყენება საკუთარ თავზე ააქტიურებს ავტორიზაციას და ამის `false`-ზე დაყენება არ თიშავს მას უკან — URL-ის გაუქმება საჭიროა კვანძის ავტორიზაციის გარეშე გასაშვებად. | არა | გამორთულია | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | Tuist სერვერი, რომლის წინაშეც კვანძი ახდენს ავტორიზაციას. საკუთარ თავზე ააქტიურებს ავტორიზაციას. | აუცილებელია, როდესაც ავტორიზაცია ჩართულია | ნაგულისხმები არ არის | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | კავშირის timeout იმ სერვერთან ზარებისთვის. | არა | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | Request timeout იმ სერვერთან ზარებისთვის. | არა | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | გაზიარებული secret token-ებისთვის, რომლებსაც კვანძი საკუთარ თავზე კითხულობს, round trip-ის გამოტოვებით. ის ასევე აფორმებს ხელმოწერას, როგორც ამოწმებს, ამიტომ გამოიყენეთ მხოლოდ იქ, სადაც კვანძი და სერვერი ერთი და იგივე ნდობის საზღვარშია. Self-hosted კვანძები ჩვეულებრივ ამას დაყენებულს ტოვებენ. | არა | გამორთულია | `extraEnv` ან `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | სერვერის მიერ cache token-ების ხელმოწერისთვის გამოყენებული საჯარო გასაღები, ერთი ან რამდენიმე შეერთებული PEM ბლოკის სახით. კითხულობს ამ token-ებს მათი შექმნის შესაძლებლობის გარეშე, რაც ინტერნეტზე ხელმისაწვდომმა კვანძმა უნდა შეინახოს. ურთიერთგამომრიცხავია `KURA_AUTH_JWT_SECRET`-თან. | არა | გამორთულია | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | ალგორითმი იმ გასაღებისთვის: `HS256`, `HS384` ან `HS512` secret-ით, `ES256` საჯარო გასაღებით. | არა | `HS256` secret-ით, `ES256` საჯარო გასაღებით | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | გამომცემელი, რომელიც token-ებმა უნდა შეიცავდეს. | არა | შემოწმებული არ არის | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | მსმენელები (audiences), რომლებიც token-ებმა უნდა შეიცავდეს, გამოყოფილი მძიმით. | არა | შემოწმებული არ არის | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | ტიპური ჩანაწერების მაქსიმალური რაოდენობა, რომელიც ინახება ავთენტიკაციის და ავტორიზაციის თითოეულ cache-ში. | არა | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | კვანძის რეგისტრაცია control plane-ში ყოველ ჩატვირთვაზე, peer სერტიფიკატის მომზადებით და `KURA_TENANT_ID` და `KURA_PEERS`-ის მიწოდებით. | არა | გამორთულია | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | Tuist სერვერი, რომლის წინაშეც კვანძი რეგისტრირდება. | აუცილებელია რეგისტრაციის დროს | ნაგულისხმები არ არის | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | კვანძის credential-ის Client ID, რომელიც გენერირდება dashboard-ში. | აუცილებელია რეგისტრაციის ან enrollment-ის დროს | ნაგულისხმები არ არის | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | Client secret, რომელიც შეწყვილებულია `KURA_CONTROL_PLANE_CLIENT_ID`-თან. | აუცილებელია რეგისტრაციის ან enrollment-ის დროს | ნაგულისხმები არ არის | `extraEnv` |
| `KURA_REGISTRATION_URL` | აბსოლუტური URL, რომელზეც კვანძი აგზავნის რეგისტრაციის heartbeat-ებს, თავისი client-facing endpoint-ის რეკლამირებით. | აუცილებელია რეგისტრაციის დროს | ნაგულისხმები არ არის | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | Cache URL, რომელიც ხელმისაწვდომია კლიენტებისთვის და რომელსაც control plane აწვდის კლიენტებს. უნდა იყოს ხელმისაწვდომი ანგარიშის ყოველი კლიენტისთვის. | აუცილებელია რეგისტრაციის დროს | ნაგულისხმები არ არის | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | რეგისტრაციის heartbeat-ის სიხშირე. ვადა რამდენიმე გამოტოვებულ heartbeat-ს ფარავს, ამიტომ ერთი გამოტოვებული heartbeat არ ცვლის endpoint-ს. | არა | `60000` | `extraEnv` |

თუ შიდა peer mTLS-ს ჩართავთ, ერთად დააყენეთ `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH` და `KURA_INTERNAL_TLS_KEY_PATH`. `KURA_NODE_URL` და `KURA_PEERS`-ის ყოველი მნიშვნელობა შემდეგ უნდა იყენებდეს `https://`-ს შიდა peer პორტთან.
