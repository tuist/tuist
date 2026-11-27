---
{
  "title": "თვითმასპინძელი ქეში",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "განათავსეთ თვითმასპინძელი ქეშის კვანძები და დააკავშირეთ ისინი Tuist-თან."
}
---

# თვითმასპინძელი კეში {#self-hosted-cache}

თვითმასპინძელი კეშის კვანძები საშუალებას გაძლევთ, ბილდის არტეფაქტები და კეშის მეტამონაცემები შეინახოთ იმ მანქანებთან ახლოს, რომლებიც ქმნიან და მოიხმარენ ბილდის შედეგებს. გამოიყენეთ ისინი მაშინ, როდესაც კეშის დაყოვნებას აქვს მნიშვნელობა CI-ში, დეველოპერების ოფისებში, დაშორებულ სამუშაო სადგურებზე ან რეგიონულ საკომპიუტრო კლასტერებში.

მიზანია ყველგან დაბალი დაყოვნებით კეშირება, არა მხოლოდ იმ ერთ გარემოში, სადაც ცენტრალური კეში შემთხვევით ახლოსაა. თითოეული კეშის კვანძი ემსახურება წაკითხვებსა და ჩაწერებს ლოკალური დისკიდან, ხოლო mesh-ი არტეფაქტებსა და მეტამონაცემებს რეპლიცირებს პირებს შორის, რათა სხვა ადგილებმაც დროთა განმავლობაში მიიღონ იმავე კეშის სარგებელი.

> [!NOTE]
> Tuist-ის თვითმასპინძელ კეშის კვანძებს ამუშავებს [Kura](https://github.com/tuist/tuist/tree/main/kura), Tuist-ის დეცენტრალიზებული კეშის mesh-ი. Kura არის კეშის კვანძების მონაცემთა ფენა: ის ემსახურება კეშის წაკითხვებსა და ჩაწერებს, ინახავს ლოკალურ მდგომარეობას დისკზე და არტეფაქტებსა და მეტამონაცემებს რეპლიცირებს მეზობელ კვანძებზე.

## როგორ ერწყმის თვითმასპინძელი კეში Tuist-ს {#how-self-hosted-cache-fits-with-tuist}

Tuist-ის მართული კეში იყენებს `https://<account>.cache.tuist.dev`. თვითმასპინძელი Tuist სერვერის შემთხვევაში, CLI იღებს კეშის URL-ს სერვერის `TUIST_CACHE_ENDPOINTS` პარამეტრიდან. მიუთითეთ თქვენი ძირითადი კეშის სერვერის ან სატვირთო გამანაწილებლის URL. თუ ის შეიცავს რამდენიმე URL-ს, გამოიყენება პირველი.

პირადი/მორგებული კეშის კვანძებისთვის, რომლებიც დაკავშირებულია **hosted Tuist server**-თან, დეველოპერების გარსებში და CI-ში მიუთითეთ ცალსახა endpoint:

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

ეს გადაფარვა უპირატესობას იღებს ორივე ტიპის სერვერზე და არის არასავალდებულო თვითმასპინძელი Tuist სერვერებისთვის. Xcode კეშის დემონისთვის, მისი დაყენების შემდეგ ხელახლა გაუშვით `tuist setup cache`, რათა LaunchAgent-მა მიიღოს განახლებული გარემო.

თვითმასპინძელი Tuist სერვერი endpoints-ს იღებს სტატიკური კონფიგურაციიდან. Tuist-ის მიერ მასპინძელ სერვერზე, კვანძები ავტორიზაციას გადიან კრედენციალით და რეგისტრირდებიან. ჯერ განათავსეთ კვანძი ქვემოთ მოცემული ორი სექციიდან ერთ-ერთის გამოყენებით, შემდეგ იხილეთ [Connect nodes to Tuist](#connect-nodes-to-tuist).

## განთავსება Kubernetes-ზე {#deploy-on-kubernetes}

Kura ვრცელდება Helm chart-ის სახით GitHub Container Registry-ის მეშვეობით. ის ათავსებს Kura-ს როგორც `StatefulSet` persistent volumes-ით, headless სერვისით პირების აღმოსაჩენად და ჩვეულებრივი სერვისით HTTP და gRPC ტრაფიკისთვის.

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

იმავე კლასტერში მყოფი თვითმასპინძელი Tuist სერვერისთვის, დააკონფიგურირეთ მისი ძირითადი კეშის endpoint:

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

ეს აყენებს `TUIST_CACHE_ENDPOINTS` სერვერის pod-ში. გამოიყენეთ ისეთი მისამართი, რომელზეც დეველოპერების მანქანებსა და CI-ს აქვთ წვდომა; ზემოთ მოცემული კლასტერის შიდა სერვისის სახელი შესაფერისია კლასტერის შიგნით მომუშავე კლიენტებისთვის.

> [!IMPORTANT]
> თითოეულ Kura კვანძს უნდა ჰქონდეს თავისი საკუთარი `KURA_DATA_DIR`. Kura იღებს აპლიკაციის დონის writer lock-ს მონაცემთა დირექტორიაზე და ელის, რომ ზუსტად ერთი პროცესი ფლობდეს მას. Kubernetes-ში გამოიყენეთ ერთი persistent volume თითო pod-ზე. Kubernetes-ის გარეთ, არ მიუთითოთ რამდენიმე პროცესი იმავე mounted დირექტორიაზე.

## განთავსება Kubernetes-ის გარეშე {#deploy-without-kubernetes}

Kura ასევე შეიძლება გაეშვას როგორც ჩვეულებრივი კონტეინერი VM-ებზე ან bare-metal ჰოსტებზე. ამ რეჟიმში, თქვენ ხართ პასუხისმგებელი პროცესების მონიტორინგზე, მუდმივ შენახვაზე, მარშრუტიზაციაზე და პირების აღმოჩენაზე.

მინიმუმ, თითოეულ კვანძს სჭირდება მუდმივი მონაცემთა დირექტორია, დროებითი დირექტორია, საჯარო კეშის პორტი (ერთი listener ემსახურება როგორც HTTP cache API-ს, ასევე REAPI gRPC-ს), შიდა პირის URL და ან სტატიკური პირების სია, ან აღმოჩენის მექანიზმი:

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

თვითმასპინძელ Tuist სერვერზე, დააკონფიგურირეთ ძირითადი კეშის URL, რომელზეც დეველოპერების მანქანებსა და CI-ს აქვთ წვდომა:

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## კვანძების სატვირთო გამანაწილებლის უკან განთავსება {#load-balancers}

კლიენტები იყენებენ თითოეულ კეშის endpoint URL-ს როგორც HTTP-ის, ასევე gRPC-ისთვის: HTTP ჯანმრთელობის შემოწმებებისა და HTTP cache API-სთვის, ხოლო gRPC მოდულის კეშისა და Bazel-ის remote cache-ისთვის. ნებისმიერ ingress-ს, სატვირთო გამანაწილებელს ან CDN-ს კლიენტებსა და Kura-ს შორის უნდა გადაამისამართოს ორივე იმავე hostname-ზე და პორტზე. ეს ეხება ყველა endpoint-ს, რომელსაც კლიენტები იღებენ, რადგან CLI ირჩევს იმას, რომელიც ყველაზე სწრაფად პასუხობს. თუ gRPC ვერ აღწევს Kura-მდე, CLI აფრთხილებს, რომ remote module caching ხელმიუწვდომელია და იყენებს მხოლოდ ლოკალურ მოდულის კეშს.

გადაამისამართეთ ეს path prefix-ები Kura-ზე როგორც gRPC over HTTP/2, ხოლო ყველაფერი დანარჩენი როგორც HTTP:

| Path prefix | გამოიყენება |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | მოდულის კეში, Bazel |
| `/google.bytestream.` | მოდულის კეში, Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel build events |

Kura იღებს plaintext HTTP/2-ს (h2c) `KURA_PORT`-ზე, და HTTP/2-ს TLS-ით `KURA_HTTPS_PORT`-ზე, როდესაც დაყენებულია `KURA_PUBLIC_TLS_CERT_PATH` და `KURA_PUBLIC_TLS_KEY_PATH`. თუ თქვენი proxy ხელახლა იყენებს upstream კავშირებს მოთხოვნებს შორის, როგორც ამას ingress-nginx აკეთებს, დააყენეთ `KURA_GATEWAY_GRPC_PORT` და gRPC ტრაფიკი გაუგზავნეთ იმ პორტს. ის ემსახურება მხოლოდ gRPC-ს, ამიტომ HTTP/1.1 და gRPC მოთხოვნები არასდროს იზიარებენ კავშირს.

დააკონფიგურირეთ gRPC მარშრუტები:

- მოთხოვნის სხეულის ზომის ლიმიტი არ არის. ატვირთვა აგზავნის ერთ ფაილს ერთ მოთხოვნაში, 2 GiB-მდე.
- მოთხოვნისა და პასუხის ბუფერიზაცია გამორთულია.
- წაკითხვის, გაგზავნისა და უმოქმედობის таймаუთები მინიმუმ 300 წამი.

Kura არ ემსახურება gRPC ჯანმრთელობის შემოწმების სერვისს. კვანძების ჯანმრთელობის შემოწმება ხდება HTTP-ით `/ready`-ზე. თუ თქვენს სატვირთო გამანაწილებელს სჭირდება gRPC ჯანმრთელობის შემოწმება, გამოიძახეთ `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` და დაუშვით gRPC სტატუსის კოდები `0` და `16`. ავტორიზაციის ჩართული კვანძი პასუხობს მოთხოვნას ტოკენის გარეშე `16` (`UNAUTHENTICATED`).

### ingress-nginx {#load-balancers-ingress-nginx}

Helm chart-ით, HTTP ingress დატოვეთ `/`-ზე და დაამატეთ gRPC ingress იმავე ჰოსტისთვის. მხოლოდ HTTP ingress აცხადებს TLS-ს:

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

1. გადაამისამართეთ ნაგულისხმევი წესი target group-ზე პროტოკოლის ვერსიით `HTTP1` `KURA_PORT`-ზე, ჯანმრთელობის შემოწმებით HTTP-ით `/ready`-ზე.
2. შექმენით მეორე target group პროტოკოლის ვერსიით `gRPC`, პროტოკოლის გამოყენებით `HTTP` `KURA_GATEWAY_GRPC_PORT`-ზე (ან `KURA_PORT`), ან პროტოკოლი `HTTPS` `KURA_HTTPS_PORT`-ზე. დააკონფიგურირეთ მისი ჯანმრთელობის შემოწმება ზემოთ აღწერილი გზით.
3. დაამატეთ წესი, რომელიც გადაამისამართებს path patterns-ს `/build.bazel.remote.execution.v2.*`, `/google.bytestream.*`, `/build.bazel.remote.asset.v1.*` და `/google.devtools.build.v1.*` მეორე target group-ზე.
4. გაზარდეთ სატვირთო გამანაწილებლის უმოქმედობის таймаუთი მინიმუმ 300 წამამდე.

### CDN-ები {#load-balancers-cdns}

კვანძის წინ მდებარე CDN-მა უნდა მხარი დაუჭიროს gRPC-ს და არ უნდა ბლოკავდეს gRPC მარშრუტებს თავისი firewall-ის წესებში. კლიენტები ტვირავენ დიდ არტიფაქტებს მაქსიმუმ 2 MiB ზომის ნაწილებად და აწყობენ მათ კვანძზე, ამიტომ არცერთ მოთხოვნას არ სჭირდება დიდი სხეული ან ხანგრძლივი ატვირთვა. მოდულის ქეში და Xcode კომპილაციის ქეში ასე იქცევიან, ისევე როგორც Bazel, თუ აგებულია `--experimental_remote_cache_chunking` ფლაგით (Bazel 8.7 და 9.1 ან უახლესი). ამ ფლაგის გარეშე, Bazel ტვირავენ თითოეულ შედეგს ერთ მოთხოვნაში, ამიტომ CDN-მა ასევე უნდა დაუშვას დიდი მოთხოვნის სხეულები და ატვირთვები, რომლებიც იმდენ ხანს გრძელდება, რამდენსაც თქვენი უდიდესი შედეგები მოითხოვენ თქვენს ყველაზე ნელ ბმულზე. თუ თქვენი CDN ვერ აკმაყოფილებს ამ მოთხოვნებს, მიეცით კლიენტებს ჰოსტნეიმი, რომელიც გამოტოვებს მას, მაგალითად, მხოლოდ DNS ჩანაწერი.

#### Cloudflare {#load-balancers-cloudflare}

მოდულის ქეშირება მუშაობს ნებისმიერ პაკეტზე Cloudflare-ის პროქსირებული ჰოსტნეიმის მეშვეობით. ზონაში:

1. **Network**-ის ქვეშ, ჩართეთ **gRPC**.
2. **SSL/TLS**-ის ქვეშ, დააყენეთ დაშიფვრის რეჟიმი **Full** ან **Full (strict)**. Cloudflare უკავშირდება origin-ს 443 პორტზე, ამიტომ origin-მა უნდა მიწოდოს TLS იქ და შესთავაზოს HTTP/2 ALPN-ის მეშვეობით.
3. დარწმუნდით, რომ არცერთი WAF მორგებული წესი ან მართული წესი არ ბლოკავს ზემოთ ჩამოთვლილ gRPC მარშრუტებს.

Cloudflare ასრულებს მოთხოვნას, თუ origin-მა დაახლოებით ორი წუთის შემდეგაც კი არ დაიწყო პასუხის გაცემა. Bazel ატვირთვა `--experimental_remote_cache_chunking` ფლაგის გარეშე იღებს პასუხს მხოლოდ მას შემდეგ, რაც მისი ბოლო ბაიტი მივა, ამიტომ Cloudflare-ზე ასეთი ატვირთვები ვერ ხერხდება, თუ ისინი იმაზე მეტ ხანს გრძელდება.

## კვანძების დაკავშირება Tuist-თან {#connect-nodes-to-tuist}

დააკონფიგურირეთ კლიენტის მარშრუტიზაცია და დაარეგისტრირეთ თქვენი კვანძები Tuist-ში, რათა მათი მისამართები, მზადყოფნა და გამოყენება გამოჩნდეს დაფაზე.

**self-hosted Tuist server**-ზე, თქვენ აცხადებთ endpoint-ებს სტატიკურად `TUIST_CACHE_ENDPOINTS`-ის მეშვეობით, როგორც ნაჩვენებია ზემოთ განთავსების სექციებში. CLI იყენებს პირველ კონფიგურირებულ URL-ს. `TUIST_CACHE_ENDPOINT` გადაფარავს ამ URL-ს ინდივიდუალური კლიენტისთვის.

**Tuist-hosted server**-ზე, დააყენეთ `TUIST_CACHE_ENDPOINT` დეველოპერის გარსებში და CI-ში, რათა ქეშის მოთხოვნები მიმართოთ თქვენს კვანძებზე. თითოეული კვანძი ავთენტიფიცირდება თქვენს მიერ გენერირებული კრედენციალით, შემდეგ რეგისტრირებს თავის მისამართს და აცნობებს თავის მზადყოფნას დაფას. ეს სექცია ეხება კვანძის რეგისტრაციას.

> [!IMPORTANT]
> **Enterprise plan**
>
> Self-hosted ქეშის კვანძები ხელმისაწვდომია Enterprise პაკეტზე. ქვემოთ აღწერილი სექცია **Self-hosted servers** ჩანს მხოლოდ იმ ანგარიშებისთვის, რომლებიც ამ პაკეტზე არიან.

### კვანძის კრედენციალის გენერირება {#generate-a-node-credential}

Tuist დაფაზე, გახსენით თქვენი ანგარიში, გადადით **Cache**-ზე და იპოვეთ **Self-hosted servers**. აირჩიეთ **Generate credential** კლიენტის ID-ის და საიდუმლოს შესაქმნელად.

კრედენციალი ავტორიზაციას ანიჭებს მხოლოდ იმ ანგარიშის ტრაფიკს, რომელმაც ის შექმნა.

საიდუმლო ჩანს ერთხელ და არ აღდგება დიალოგის დახურვის შემდეგ, ამიტომ პირდაპირ დააკოპირეთ ის საიდუმლოების საცავში, საიდანაც თქვენი კვანძები კითხულობენ. კრედენციალის გაუქმება მაშინვე აჩერებს ყველა კვანძს, რომელიც მას იყენებს, ავთენტიფიკაციისგან, ამიტომ შექმენით ჩამნაცვლებელი, სანამ გააუქმებთ მოქმედ კრედენციალს.

### კვანძის რეგისტრაცია ჩატვირთვისას {#enroll-the-node-on-boot}

რეგისტრაცია არის კვანძის ამუშავების რეკომენდებული გზა. დააყენეთ `KURA_ENROLL_ON_BOOT` და მიეცით კვანძს მისი კრედენციალი და საკუთარი peer URL:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

კვანძი ადგილობრივად გენერირებს თავის გასაღებების წყვილს, ამიტომ კერძო გასაღები არასდროს ტოვებს მას, და იღებს ხელმოწერილ peer სერტიფიკატს, ანგარიშის CA-ს, მის tenant იდენტიფიკატორს და peer-ების სიას. ეს არის ყველაფერი, რასაც წინააღმდეგ შემთხვევაში ხელით დააკონფიგურირებდით: რეგისტრირებულ კვანძს არ სჭირდება `KURA_TENANT_ID`, არ `KURA_PEERS` და არ peer TLS კონფიგურაცია.

დატოვეთ `KURA_INTERNAL_TLS_*` დაუყენებელი: რეგისტრაცია წერს სერტიფიკატის მასალას `tls` დირექტორიაში `KURA_DATA_DIR`-ის ქვეშ. დააყენეთ ეს გზები თავად მხოლოდ მაშინ, როცა თქვენ აწვდით სერტიფიკატებს რეგისტრაციის ნაცვლად, როგორც აღწერილია [Build a cache mesh](#build-a-cache-mesh)-ში.

კვანძი, რომელიც პირველად უერთდება ანგარიშის mesh-ს, იღებს ანგარიშის არსებულ ქეშს, სანამ გახდება რგოლის მომსახურე წევრი. გამოყავით მონაცემთა ტომი მთელი ქეშისთვის და მოელით, რომ პირველი შეერთება გარკვეული დრო დასჭირდება ფართო არეალის ბმულზე. კვანძი აცნობებს `joining`-ს, სანამ არ დაეწევა, შემდეგ `serving`-ს.

### endpoint-ის რეკლამირება {#advertise-the-endpoint}

რეგისტრაცია აერთებს mesh-ს. რეგისტრაცია აცნობებს კვანძის კლიენტისთვის ხილულ მისამართს და მზადყოფნას Tuist-ს. დააყენეთ რეგისტრაციის ცვლადები:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

კვანძი აგზავნის heartbeats ყოველ 60 წამში 180-წამიანი lease-ის წინააღმდეგ. Tuist მიიჩნევს მის რეგისტრაციას მიუწვდომლად, როცა lease იწურება. Tuist არასდროს ურეკავს კვანძს, ამიტომ ის მხოლოდ თქვენი კლიენტებისთვის უნდა იყოს მიწვდომადი, არა ინტერნეტიდან.

### დაადასტურეთ, რომ კვანძი ემსახურება {#verify-the-node-is-serving}

დაფაზე **Cache**-ში დაბრუნებისას, კვანძი ჩანს **Registered nodes**-ის ქვეშ თავისი endpoint-ით, რეგიონით, სტატუსით და ბოლო heartbeat-ით. კვანძი, რომელიც არასდროს ჩანს, ვერ აღწევს რეგისტრაციის endpoint-ს ან ვერ გადის ავტორიზაციას. კვანძი, რომელიც ჩანს და შემდეგ ქრება, შეწყვიტა heartbeats-ის გაგზავნა ან შეწყვიტა თავისი მზადყოფნის შესახებ მოხსენება.

### ანგარიშის მუდმივი tenant იდენტიფიკატორის გამოყენება {#match-the-tenant-identifier}

`KURA_TENANT_ID` არის ანგარიშის მუდმივი ქეშის იდენტობა. ანგარიშისთვის, რომელიც არასდროს გადარქმეულა, ის უდრის ანგარიშის handle-ს. გადარქმევის შემდეგ, შეინარჩუნეთ საწყისი მნიშვნელობა ყველა კვანძზე, ჩანაცვლებითი კვანძების ჩათვლით: მისი შეცვლა ირჩევს სხვა storage namespace-ს, ხოლო ანგარიშის გადარქმევა არ გადააქვს შენახულ არტიფაქტებს. გამოიყენეთ tenant არსებული კვანძიდან ან `tenant_id` რეგისტრაციის მიერ დაბრუნებული, ნაცვლად მისი გამოყვანისა ანგარიშის მიმდინარე URL-დან.

Control plane ადარებს heartbeat-ის tenant-ს კრედენციალიდან ამოხსნილ ანგარიშს და უარყოფს შეუსაბამობას `409 tenant_mismatch`-ით, ამიტომ კვანძი არასწორი მნიშვნელობით წარმატებით ავთენტიფიცირდება, მაგრამ მაინც არასდროს რეგისტრირდება.

> [!IMPORTANT]
> როგორც Helm chart, ისე ამ სახელმძღვანელოში ადრე მოყვანილი container მაგალითი ნაგულისხმევად აყენებს ამას `default`-ზე. შეცვალეთ ის ანგარიშის tenant იდენტიფიკატორით, სანამ დაარეგისტრირებთ კვანძს. კვანძის რეგისტრაცია სრულად აცილებს ამ საკითხს, რადგან control plane აწვდის მნიშვნელობას.

დაუყენებელი `KURA_TENANT_ID` არ გამოტოვებს შემოწმებას. ის სრულად თიშავს რეგისტრაციას: კვანძი აგრძელებს ქეშის ტრაფიკის მომსახურებას, დაფაზე არაფერი ჩანს და არცერთი შეცდომა არ იგზავნება. თუ კვანძი ჯანმრთელია, მაგრამ არ ჩანს **Registered nodes**-ში, პირველ რიგში შეამოწმეთ ეს ცვლადი.

### აირჩიეთ რეკლამირებული URL, რომელსაც თქვენი კლიენტები მიაღწევენ {#choose-an-advertised-url}

გამოიყენეთ კლიენტისთვის მიწვდომადი მისამართი `KURA_ADVERTISED_HTTP_URL`-ისთვის და Tuist სერვერზე ან CLI-ზე კონფიგურირებული ქეშის URL-ისთვის.

მხოლოდ შიდა ქსელისთვის განკუთვნილი ჰოსტნეიმი შესაფერისია, როდესაც მის გამოყენებაზე კონფიგურირებული ყოველი კლიენტი ახერხებს ამ სახელის გარჩევას და მიღწევას. სხვადასხვა ქსელში მყოფი კლიენტებისთვის გამოიყენეთ საერთო მიწვდომადი მისამართი ან თითოეული გარემოსთვის კონფიგურირეთ მიწვდომადი ქეშის კვანძი.

## ააწყვეთ ქეშის mesh {#build-a-cache-mesh}

ქეშის mesh საშუალებას გაძლევთ ქეშის სიმძლავრე განათავსოთ იმ გამოთვლითი რესურსების გვერდით, რომლებსაც ის სჭირდება. კომპანიამ შეიძლება ერთი კვანძი გაუშვას ძირითად CI runner-ებთან ახლოს, მეორე ევროპაში მყოფ დეველოპერებთან ახლოს, ხოლო მესამე აშშ-ის ოფისთან ან რეგიონულ ბილდ კლასტერთან ახლოს. თითოეული ადგილმდებარეობა კითხვასა და ჩაწერას ასრულებს უახლოეს კვანძთან, ხოლო Kura ფონურ რეჟიმში ახდენს არტიფაქტებისა და მეტამონაცემების რეპლიკაციას, რათა მოგვიანებით სხვა ადგილმდებარეობებში განხორციელებულმა ბილდებმა შეძლონ იგივე გამომავალი მონაცემების ხელახლა გამოყენება.

mesh მუშაობს მხოლოდ მაშინ, თუ კვანძებს შეუძლიათ ერთმანეთთან დაკავშირება Kura-ს შიდა peer პორტზე. ეს peer სიბრტყე გამოყოფილია იმ საჯარო ქეშის endpoint-ებისგან, რომლებსაც Tuist კლიენტები იყენებენ. Kura იყენებს მას წევრობის შესამოწმებლად, ახლად შეერთებული კვანძების მონაცემებით შესავსებად (backfill) და არტიფაქტების რეპლიკაციისთვის, მას შემდეგ, რაც ადგილობრივი ჩაწერები მიღებული იქნება.

ჩვენ მკაცრად გირჩევთ peer სიბრტყის დაცვას [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication)-ით, როდესაც კვანძები ერთმანეთთან კომუნიკაციას ახდენენ რეგიონებს, ღრუბლებს, VPC-ებს, ოფისებს ან ნებისმიერ სხვა ქსელს შორის, რომელიც არ არის სრულად იზოლირებული ქეშის განლაგებისთვის. mTLS-ის ჩართვისას, Kura შიდა რეპლიკაციის endpoint-ებს მხოლოდ იმ peer-ებს უწევს, რომლებიც წარმოადგენენ კონფიგურირებული CA-ს მიერ ხელმოწერილ სერტიფიკატს. Peer სერტიფიკატებმა უნდა მოიცვას DNS სახელები, რომლებსაც კვანძები ერთმანეთთან დასაკავშირებლად იყენებენ, ხოლო peer URL-ებმა შიდა პორტზე უნდა გამოიყენონ `https://`.

> [!NOTE]
> კვანძები, რომლებიც რეგისტრირდებიან Tuist-ის მიერ მართულ control plane-ზე, რეგისტრაციის დროს იღებენ თავიანთ peer სერტიფიკატს და ანგარიშის CA-ს, ამიტომ ქვემოთ მოყვანილი ხელით შესრულებული ნაბიჯები ეხება იმ mesh-ებს, რომლებიც არ გადიან რეგისტრაციას.

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

კვანძი, რომელიც უერთდება ან ხელახლა უერთდება mesh-ს, ასრულებს **backfill**-ს: ის გადახედავს თითოეული peer-ის ჩანაწერებს უახლესიდან დაწყებული და ჩამოტვირთავს იმას, რაც აკლია, ხოლო ცოცხალი რეპლიკაცია ფარავს იმ ჩაწერებს, რომლებიც შესრულდა peer-ის ხილვადობის პერიოდში. Backfill-ის ერთი ციკლი ვრცელდება peer-ის უახლესი ჩანაწერიდან კვანძის segment-ring-ის ჰორიზონტამდე ან ბოლო დასრულებულ ციკლამდე (აირჩევა უფრო ადრინდელი), რაც უზრუნველყოფს, რომ კვანძს ექნება ბოლოდროინდელი მონაცემები, თუმცა არა აუცილებლად ყველა მონაცემი. `KURA_BACKFILL_MARGIN_PERCENT` განსაზღვრავს, თუ რამდენად შორს ვრცელდება ეს ჰორიზონტი.

ორი შედეგი ღირს ცოდნამდე, სანამ mesh-ს გაუშვებთ:

- კვანძი აცხადებს `/ready`-ს, როდესაც მისი segment ring ივსება `KURA_BACKFILL_READY_RING_PERCENT`-ით **ან** როდესაც მისი პირველი backfill ციკლი სტაბილიზდება, და მზადყოფნა ნარჩუნდება პროცესის სიცოცხლის დარჩენილ ნაწილში. peer-ის მოგვიანებითი რყევა არასდროს აცილებს მომსახურე კვანძს როტაციიდან.
- ციკლი ასევე სტაბილიზდება, როდესაც peer გარკვეული დროის განმავლობაში მიუწვდომელია. შესაბამისად, კვანძი, რომლის ერთადერთი peer გათიშულია, ხდება Ready, თუნდაც ცოტა ან საერთოდ არ ჰქონდეს მონაცემები. ის ამუშავებს გამოტოვებებს (misses) და არა შეცდომებს. `/status/rollout` აბრუნებს `backfill_initial_cycle`-ს (`pending`, `complete` ან `degraded`), თუ განსხვავებაზე დაყრდნობით გსურთ rollout-ის შეჩერება.

**Mesh-ის განახლება backfill-ის ცვლილების გადაკვეთით.** Kura-ს იმ ვერსიებში, რომლებიც backfill-ამდეა, სინქრონიზაცია ხდებოდა სხვა, ახლა უკვე წაშლილი peer პროტოკოლის მეშვეობით. გადაიყვანეთ ყოველი კვანძი ისეთ ვერსიაზე, რომელიც ასრულებს backfill-ს, **სანამ** გადახვალთ ვერსიაზე, რომელიც მხოლოდ backfill-ს იყენებს. ორ სხვადასხვა პროტოკოლზე მყოფ კვანძებს ერთმანეთთან სინქრონიზაცია არ შეუძლიათ: „თბილი“ კვანძი აგრძელებს მომსახურებას თავისი დისკიდან, მაგრამ წყვეტს ნაკლის აღმოფხვრას, ხოლო კვანძი, რომელიც ამ პერიოდში ცარიელი დისკით იწყებს მუშაობას, არასდროს ხდება Ready. Helm chart ავტომატურად აყენებს `KURA_BACKFILL_ENABLED=true`-ს, ამიტომ chart-ის პირველადი განახლება ფარავს ამ საკითხს. ერთიანი `helm upgrade`, რომელიც ერთდროულად ცვლის chart-სა და image-ს, ამას არ აკეთებს.

გამოიყენეთ ქსელის დონის შეზღუდვები mTLS-ის დამატებით. Kubernetes-ში გაუშვით Kura როგორც `StatefulSet`, თითოეული pod-ისთვის ერთი persistent volume-ით და headless სერვისით peer-ების აღმოსაჩენად, შემდეგ კი ნება დართეთ შიდა peer პორტზე მხოლოდ იმ pod-ებს შორის, რომლებიც ერთსა და იმავე ქეშის განლაგებას ეკუთვნის, მაგალითად, `NetworkPolicy`-ის გამოყენებით. Kubernetes-ის გარეთ, მიანიჭეთ თითოეულ კვანძს სტაბილური DNS სახელი ან IP მისამართი, შეავსეთ mesh სხვა კვანძების შიდა URL-ებით და გამოიყენეთ firewall-ის წესები ან security groups, რათა მხოლოდ ქეშის კვანძებს შეეძლოთ peer პორტზე მიწვდომა. საჯარო ქეშის ტრაფიკი უნდა შედიოდეს საჯარო HTTP ან gRPC endpoint-ების მეშვეობით და არა შიდა peer სიბრტყის გავლით.

## კონფიგურაცია {#configuration}

Helm chart აგენერირებს ზოგად runtime პარამეტრებს `values.yaml`-დან. თუ Kura-ს Kubernetes-ის გარეშე აწარმოებთ, დააყენეთ იგივე ცვლადები პირდაპირ პროცესზე. ცვლადები, რომლებსაც chart პირდაპირ არ ასახავს, შეიძლება ჩაინექციოს `extraEnv`-ის ან `extraEnvFrom`-ის მეშვეობით.

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმევი | Helm მნიშვნელობა |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | საჯარო ქეშის პორტი. ერთი listener ემსახურება HTTP ქეშის API-ს, ჯანმრთელობის endpoint-ებს და Bazel/Buck2 REAPI gRPC-ს (h2c). | დიახ | ნაგულისხმევი არ არის | `service.httpPort` |
| `KURA_INTERNAL_PORT` | შიდა HTTP ან mTLS პორტი, რომელსაც Kura peer-ები იყენებენ. | დიახ | ნაგულისხმევი არ არის | `peerTls.internalPort` |
| `KURA_TENANT_ID` | კვანძის ნაგულისხმევი tenant იდენტიფიკატორი. | დიახ | ნაგულისხმევი არ არის | `config.tenantId` |
| `KURA_REGION` | რეგიონის ლეიბლი, რომელიც გამოიყენება მეტრიკებსა და რეპლიკაციის მდგომარეობაში. | დიახ | ნაგულისხმევი არ არის | `config.region` |
| `KURA_TMP_DIR` | დროებითი დირექტორია staged request body-ებისა და multipart აწყობისთვის. | დიახ | ნაგულისხმევი არ არის | ფიქსირებულია `/var/cache/kura/tmp`-ზე |
| `KURA_TMP_DIR_MAX_BYTES` | მაქსიმალური staged ბაიტები, რომლებიც დაშვებულია `KURA_TMP_DIR`-ში, სანამ მოთხოვნები backpressure-ს მიიღებენ. | არა | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | მუდმივი დირექტორია მეტამონაცემების მდგომარეობისა და სეგმენტური ფაილებისთვის. | დიახ | ნაგულისხმევი არ არის | ფიქსირებულია `/var/cache/kura`-ზე |
| `KURA_NODE_URL` | კანონიკური შიდა URL, რომელსაც სხვა peer-ები იყენებენ ამ კვანძთან მისასვლელად. | დიახ | ნაგულისხმევი არ არის | მიღებულია pod-ის DNS სახელიდან და `peerTls.internalPort`-დან |
| `KURA_PEERS` | Seed peer-ების სია, რომელიც გამოიყენება აღმოჩენის კონვერგენციამდე. | არა | `KURA_NODE_URL` | მიღებულია StatefulSet რეპლიკებიდან |
| `KURA_DISCOVERY_DNS_NAME` | DNS სახელი, რომელიც გამოიყენება ავტომატური peer აღმოჩენისთვის. | არა | გათიშულია | ჩართულია `config.discovery.enabled`-ით |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | CA სერტიფიკატი, რომელიც გამოიყენება peer mTLS-ის ვერიფიკაციისთვის. | არა | გათიშულია, ან მიღებულია `KURA_DATA_DIR`-ში, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | სერტიფიკატი, რომელსაც იყენებს შიდა peer mTLS listener. | არა | გათიშულია, ან მიღებულია `KURA_DATA_DIR`-ში, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | პირადი გასაღები, რომელსაც იყენებს შიდა peer mTLS listener. | არა | გათიშულია, ან მიღებულია `KURA_DATA_DIR`-ში, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | სერტიფიკატი, რომელიც გამოიყენება TLS-ის დასასრულებლად თანამასპინძელ HTTPS listener-ზე (`KURA_HTTPS_PORT`). | არა | გათიშულია | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | პირადი გასაღები, შეწყვილებული `KURA_PUBLIC_TLS_CERT_PATH`-თან. | არა | გათიშულია | `extraEnv` |
| `KURA_HTTPS_PORT` | TLS პორტი, რომელიც ემსახურება იგივე თანამასპინძელ HTTP + gRPC ზედაპირს (ALPN-ით შეთანხმებული). იბმება მხოლოდ მაშინ, როდესაც საჯარო TLS გზები დაყენებულია. | არა | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | Plaintext HTTP/2 პორტი, რომელიც ემსახურება მხოლოდ gRPC API-ებს, პროქსებისთვის, რომლებიც ხელახლა იყენებენ upstream კავშირებს. იხილეთ [კვანძების load balancer-ის უკან განთავსება](#load-balancers). | არა | გათიშულია | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | File descriptor-ების ბიუჯეტი მოთხოვნებისა და ფონური I/O-სთვის. | არა | ავტომატურად მიღებული | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | რამდენ ხანს ელოდება მოთხოვნა, სანამ FD backpressure ჩაშლის checkout-ს. | არა | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | მიმაგრებული სეგმენტის წაკითხვის handle-ების მაქსიმალური რაოდენობა. | არა | ავტომატურად მიღებული | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | Grace პერიოდი გაფრენილი HTTP და gRPC სამუშაოებისთვის გამორთვის დროს. | არა | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | მეხსიერების რბილი ზღვარი, სადაც Kura იწყებს არასავალდებულო მეხსიერების გამოყენების შემცირებას. | არა | ავტომატურად მიღებული | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | მეხსიერების მკაცრი ზღვარი, სადაც Kura აჩერებს რეპლიკაციას და ამცირებს ცხელ caches-ს. | არა | ავტომატურად მიღებული | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | მეხსიერებაში მყოფი manifest cache-ის მაქსიმალური ზომა. | არა | ავტომატურად მიღებული | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | მოთხოვნის ერთეულზე keyvalue payload-ის მაქსიმალური ზომა. | არა | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | File descriptor-ების ბიუჯეტი, რომელიც გამოყოფილია metadata store-ისთვის. | არა | ავტომატურად მიღებული | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | ფონური flush-ისა და compaction-ის კონკურენტულობა metadata store-ისთვის. | არა | ავტომატურად მიღებული | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | metadata-store read cache-ის ტევადობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | მეხსიერების საერთო ბიუჯეტი, რომელიც გამოყოფილია metadata write buffering-ისთვის. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | თითოეული metadata write buffer-ის ზომა flush-მდე. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | მეხსიერებაში შენახული metadata write buffer-ების მაქსიმალური რაოდენობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | რამდენ ხანს შეიძლება დარჩეს მიმდინარე multipart upload ვადის გასვლამდე. | არა | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | რამდენად ხშირად აკეთებს Kura სკანირებას ძველი multipart uploads-ისთვის. | არა | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | ასაკის მიხედვით დალაგებული სეგმენტური რგოლის წილი, ათვლილი უახლესიდან, რომელიც განსაზღვრავს, თუ რამდენად შორს ვრცელდება backfill-ის ერთი ციკლი. | არა | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | სეგმენტური რგოლის შევსების დონე, რომლის დროსაც კვანძი, რომელიც ჯერ კიდევ ასრულებს თავის პირველ backfill ციკლს, საკუთარ თავს მზადყოფნად აცხადებს. | არა | `KURA_BACKFILL_MARGIN_PERCENT`-ის ნახევარი | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | ბაიტების ზღვარი, რომლის მიხედვითაც იქმნება ერთი backfill bodies batch, და ზომა, რომლის ზემოთაც ჩანაწერი ინდივიდუალურად იტვირთება. | არა | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio worker thread-ების რაოდენობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP traces endpoint. დატოვეთ ცარიელი ტრეისინგის გამოსართავად. | არა | გამორთულია | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry სერვისის სახელი. | კი | ნაგულისხმები მნიშვნელობა არ არსებობს | Pod-ის სახელი Helm-ში |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry განლაგების გარემო. | კი | ნაგულისხმები მნიშვნელობა არ არსებობს | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | Sentry DSN panic-ისა და შეცდომების შესახებ მოხსენებისთვის. | არა | გამორთულია | `extraEnv` ან `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | ISO 3166-1 alpha-2 ქვეყანა იმ მონაცემთა ცენტრისთვის, სადაც კვანძი მუშაობს, ექსპორტირებულ traces-ზე ბეჭდავს როგორც `geo.country.iso_code`. | არა | მიღებულია `KURA_REGION`-დან, როცა მისი პრეფიქსი ქვეყნის კოდია | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | იმ მონაცემთა ცენტრის ISO 3166-2 ქვედანაყოფი (მაგ., `US-CA`), ბეჭდავს როგორც `geo.region.iso_code`. | არა | არ არის დაყენებული | `extraEnv` |
| `KURA_AUTH_ENABLED` | მოითხოვს, რომ გამომძახებლებმა წარმოადგინონ მოქმედი Tuist token. `KURA_AUTH_TUIST_URL`-ის დაყენება საკუთარ თავზე რთავს ავტორიზაციას, ხოლო ამის `false`-ზე დაყენება არ თიშავს მას — URL-ის გასუფთავება საჭიროა კვანძის ავტორიზაციის გარეშე გასაშვებად. | არა | გამორთულია | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | Tuist სერვერი, რომლის მიმართაც კვანძი ახდენს ავტორიზაციას. საკუთარ თავზე რთავს ავტორიზაციას. | აუცილებელია, როცა ავტორიზაცია ჩართულია | ნაგულისხმები მნიშვნელობა არ არსებობს | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | Connect timeout იმ სერვერთან ზარებისთვის. | არა | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | Request timeout იმ სერვერთან ზარებისთვის. | არა | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | საერთო საიდუმლო იმ token-ებისთვის, რომელთა წაკითხვაც კვანძს შეუძლია თვითონ, რათა თავიდან აიცილოს დამატებითი ზარი. ის ასევე ხელმოწერასაც აკეთებს და ვერიფიკაციასაც, ამიტომ გამოიყენეთ მხოლოდ იქ, სადაც კვანძი და სერვერი ერთსა და იმავე ნდობის საზღვარშია. თვითმასპინძელი კვანძები ჩვეულებრივ ამ პარამეტრს ტოვებენ დაუყენებლად. | არა | გამორთულია | `extraEnv` ან `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | გასაღები წყვილის საჯარო ნაწილი, რომლითაც სერვერი ხელს აწერს cache token-ებს, ერთი ან რამდენიმე შეერთებული PEM ბლოკის სახით. კითხულობს ამ token-ებს მათი შექმნის შესაძლებლობის გარეშე, რაც ინტერნეტიდან ხელმისაწვდომ კვანძს უნდა ჰქონდეს. ურთიერთგამომრიცხავია `KURA_AUTH_JWT_SECRET`-თან. | არა | გამორთულია | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | ალგორითმი ამ გასაღებისთვის: `HS256`, `HS384` ან `HS512` საიდუმლოსთან ერთად, `ES256` საჯარო გასაღებთან ერთად. | არა | `HS256` საიდუმლოსთან ერთად, `ES256` საჯარო გასაღებთან ერთად | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | გამომცემელი, რომელიც token-ებმა უნდა შეიცავდნენ. | არა | შემოწმების გარეშე | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | მძლეებით გამოყოფილი აუდიტორიები, რომლებიც token-ებმა უნდა შეიცავდნენ. | არა | შემოწმების გარეშე | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | მაქსიმალური ჩანაწერები, რომლებიც ინახება ავთენტიკაციისა და ავტორიზაციის თითოეულ cache-ში. | არა | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | არეგისტრირებს კვანძს სამართავ სიბრტყესთან ყოველ ჩართვაზე, ამზადებს მის peer certificate-ს და აწვდის `KURA_TENANT_ID` და `KURA_PEERS`. | არა | გამორთულია | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | Tuist სერვერი, რომლის მიმართაც კვანძი ახდენს რეგისტრაციას. | აუცილებელია რეგისტრაციის დროს | ნაგულისხმები მნიშვნელობა არ არსებობს | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | კვანძის credential-ის Client ID, რომელიც გენერირდება dashboard-ში. | აუცილებელია რეგისტრაციის ან enrolment-ის დროს | ნაგულისხმები მნიშვნელობა არ არსებობს | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | Client secret, რომელიც შეწყვილებულია `KURA_CONTROL_PLANE_CLIENT_ID`-თან. | აუცილებელია რეგისტრაციის ან enrolment-ის დროს | ნაგულისხმები მნიშვნელობა არ არსებობს | `extraEnv` |
| `KURA_REGISTRATION_URL` | აბსოლუტური URL, სადაც კვანძი აგზავნის რეგისტრაციის heartbeat-ებს, რათა განაცხადოს მისი კლიენტისთვის ხელმისაწვდომი endpoint. | აუცილებელია რეგისტრაციის დროს | ნაგულისხმები მნიშვნელობა არ არსებობს | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | კლიენტისთვის ხელმისაწვდომი cache URL, რომელსაც სამართავი სიბრტყე აწვდის კლიენტებს. უნდა იყოს ხელმისაწვდომი ანგარიშის ყოველი კლიენტისთვის. | აუცილებელია რეგისტრაციის დროს | ნაგულისხმები მნიშვნელობა არ არსებობს | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | რეგისტრაციის heartbeat-ის სიხშირე. lease მოიცავს რამდენიმე გამოტოვებულ heartbeat-ს, ამიტომ ერთი გამოტოვებული heartbeat არ ცვლის endpoint-ს. | არა | `60000` | `extraEnv` |

თუ ჩართავთ შიდა peer mTLS-ს, ერთდროულად დააყენეთ `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH` და `KURA_INTERNAL_TLS_KEY_PATH`. `KURA_NODE_URL` და `KURA_PEERS`-ში ყოველი მნიშვნელობა შემდეგ უნდა იყენებდეს `https://` შიდა peer port-თან ერთად.
