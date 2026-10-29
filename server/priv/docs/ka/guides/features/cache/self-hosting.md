---
{
  "title": "Self-hosted cache",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "Deploy self-hosted cache nodes and connect them to Tuist."
}
---

# თვითმასპინძელი კეში {#self-hosted-cache}

თვითმასპინძელი კეშის კვანძები საშუალებას გაძლევთ, აგების არტიფაქტები და კეშის მეტამონაცემები შეინახოთ იმ მანქანებთან ახლოს, რომლებიც ქმნიან და მოიხმარენ აგების შედეგებს. გამოიყენეთ ისინი მაშინ, როდესაც კეშის დაყოვნებას აქვს მნიშვნელობა CI-ში, დეველოპერების ოფისებში, დისტანციურ სამუშაო სადგურებზე ან რეგიონულ საგამოთვლო კლასტერებში.

მიზანი არის დაბალი დაყოვნების კეშირება ყველგან, არა მხოლოდ იმ ერთ გარემოში, სადაც ცენტრალური კეში შემთხვევით ახლოსაა. თითოეული კეშის კვანძი ემსახურება წაკითხვებსა და ჩაწერებს ლოკალური დისკიდან, ხოლო mesh-ი ავრცელებს არტიფაქტებსა და მეტამონაცემებს პირებს შორის, რათა სხვა ადგილებმაც დროთა განმავლობაში მიიღონ სარგებელი იმავე კეშიდან.

> [!NOTE]
> Tuist-ის თვითმასპინძელ კეშის კვანძებს ამუშავებს [Kura](https://github.com/tuist/tuist/tree/main/kura), Tuist-ის დეცენტრალიზებული კეშის mesh-ი. Kura არის კეშის კვანძების მონაცემთა ფენა: ის ემსახურება კეშის წაკითხვებსა და ჩაწერებს, ინახავს ლოკალურ მდგომარეობას დისკზე და ავრცელებს არტიფაქტებსა და მეტამონაცემებს პირ კვანძებზე.

## როგორ ერწყმის თვითმასპინძელი კეში Tuist-ს {#how-self-hosted-cache-fits-with-tuist}

Tuist-ის მართული კეში იყენებს `https://<account>.cache.tuist.dev`. თვითმასპინძელი Tuist სერვერით, CLI იღებს კეშის URL-ს სერვერის `TUIST_CACHE_ENDPOINTS` პარამეტრიდან. დააყენეთ ის თქვენი ძირითადი კეშის სერვერის ან დატვირთვის ბალანსერის URL-ზე. თუ ის შეიცავს რამდენიმე URL-ს, გამოიყენება პირველი.

პირადი/მორგებული კეშის კვანძებისთვის, რომლებიც დაკავშირებულია **hosted Tuist server**-თან, დააყენეთ ცალსახა endpoint დეველოპერების shell-ებში და CI-ში:

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

ეს გადაფარვა უპირატესობას იღებს ორივე ტიპის სერვერზე და არის სავალდებულო თვითმასპინძელი Tuist სერვერებისთვის. Xcode კეშის დემონისთვის, ხელახლა გაუშვით `tuist setup cache` მისი დაყენების შემდეგ, რათა LaunchAgent-მა მიიღოს განახლებული გარემო.

თვითმასპინძელი Tuist სერვერი იღებს endpoint-ებს სტატიკური კონფიგურაციიდან. Tuist-ის მიერ მასპინძლობულ სერვერზე, კვანძები ავტორიზაციას გადიან კრედენციალით და რეგისტრირდებიან. ჯერ განათავსეთ კვანძი ქვემოთ მოცემული ორი სექციიდან ერთ-ერთის გამოყენებით, შემდეგ იხილეთ [Connect nodes to Tuist](#connect-nodes-to-tuist).

## განთავსება Kubernetes-ზე {#deploy-on-kubernetes}

Kura ვრცელდება Helm chart-ის სახით GitHub Container Registry-ის მეშვეობით. ის ათავსებს Kura-ს როგორც `StatefulSet` მუდმივი ტომებით, headless სერვისით პირების აღმოჩენისთვის და ჩვეულებრივი სერვისით HTTP და gRPC ტრაფიკისთვის.

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

ეს აყენებს `TUIST_CACHE_ENDPOINTS` სერვერის pod-ში. გამოიყენეთ მისამართი, რომელზეც წვდომა აქვთ დეველოპერების მანქანებს და CI-ს; ზემოთ მოცემული კლასტერის შიდა სერვისის სახელი შესაფერისია კლასტერის შიგნით მომუშავე კლიენტებისთვის.

> [!IMPORTANT]
> ყველა Kura კვანძს უნდა ჰქონდეს საკუთარი `KURA_DATA_DIR`. Kura იღებს აპლიკაციის დონის ჩამწერი ბლოკირებას მონაცემთა დირექტორიაზე და ელის, რომ ზუსტად ერთი პროცესი ფლობდეს მას. Kubernetes-ში, გამოიყენეთ ერთი მუდმივი ტომი თითოეული pod-ისთვის. Kubernetes-ის გარეთ, არ მიმართოთ რამდენიმე პროცესი ერთსა და იმავე მონტირებულ დირექტორიაზე.

## განთავსება Kubernetes-ის გარეშე {#deploy-without-kubernetes}

Kura ასევე შეიძლება გაეშვას როგორც ჩვეულებრივი კონტეინერი VM-ებზე ან bare-metal ჰოსტებზე. ამ რეჟიმში, თქვენ ხართ პასუხისმგებელი პროცესების ზედამხედველობაზე, მუდმივ შენახვაზე, მარშრუტიზაციაზე და პირების აღმოჩენაზე.

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

თვითმასპინძელ Tuist სერვერზე, დააკონფიგურირეთ ძირითადი კეშის URL, რომელზეც წვდომა აქვთ დეველოპერების მანქანებს და CI-ს:

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## კვანძების განთავსება დატვირთვის ბალანსერის უკან {#load-balancers}

კლიენტები იყენებენ თითოეულ კეშის endpoint URL-ს როგორც HTTP-ის, ასევე gRPC-ისთვის: HTTP ჯანმრთელობის შემოწმებებისა და HTTP კეშის API-სთვის, ხოლო gRPC მოდულის კეშისა და Bazel-ის დისტანციური კეშისთვის. ნებისმიერ ingress-ს, დატვირთვის ბალანსერს ან CDN-ს კლიენტებსა და Kura-ს შორის უნდა გადაჰქონდეს ორივე ერთსა და იმავე ჰოსტის სახელსა და პორტზე. ეს ვრცელდება ყველა endpoint-ზე, რომელსაც კლიენტები იღებენ, რადგან CLI ირჩევს იმას, რომელიც ყველაზე სწრაფად პასუხობს. თუ gRPC ვერ აღწევს Kura-მდე, CLI აფრთხილებს, რომ დისტანციური მოდულის კეშირება მიუწვდომელია და იყენებს მხოლოდ ლოკალურ მოდულის კეშს.

გადაამისამართეთ ეს გზის პრეფიქსები Kura-ზე როგორც gRPC HTTP/2-ზე, ხოლო ყველაფერი დანარჩენი როგორც HTTP:

| გზის პრეფიქსი | გამოიყენება |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | მოდულის კეში, Bazel |
| `/google.bytestream.` | მოდულის კეში, Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel აგების მოვლენები |

Kura იღებს plaintext HTTP/2-ს (h2c) `KURA_PORT`-ზე და HTTP/2-ს TLS-ზე `KURA_HTTPS_PORT`-ზე, როდესაც დაყენებულია `KURA_PUBLIC_TLS_CERT_PATH` და `KURA_PUBLIC_TLS_KEY_PATH`. თუ თქვენი proxy ხელახლა იყენებს upstream კავშირებს მოთხოვნებს შორის, როგორც ingress-nginx აკეთებს, დააყენეთ `KURA_GATEWAY_GRPC_PORT` და გაუგზავნეთ gRPC ტრაფიკი ამ პორტზე. ის ემსახურება მხოლოდ gRPC-ს, ამიტომ HTTP/1.1 და gRPC მოთხოვნები არასდროს იზიარებენ კავშირს.

დააკონფიგურირეთ gRPC მარშრუტები:

- მოთხოვნის სხეულის ზომის ლიმიტის გარეშე. ატვირთვა აგზავნის ერთ ფაილს ერთ მოთხოვნაში, 2 GiB-მდე.
- მოთხოვნისა და პასუხის ბუფერიზაცია გამორთულია.
- წაკითხვის, გაგზავნის და უმოქმედობის таймаუთები მინიმუმ 300 წამი.

Kura არ ემსახურება gRPC ჯანმრთელობის შემოწმების სერვისს. შეამოწმეთ კვანძების ჯანმრთელობა HTTP-ით `/ready`-ზე. თუ თქვენს დატვირთვის ბალანსერს სჭირდება gRPC ჯანმრთელობის შემოწმება, გამოიძახეთ `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` და მიიღეთ gRPC სტატუსის კოდები `0` და `16`. კვანძი, რომელსაც ჩართული აქვს ავტორიზაცია, პასუხობს მოთხოვნას ტოკენის გარეშე `16`-ით (`UNAUTHENTICATED`).

### ingress-nginx {#load-balancers-ingress-nginx}

Helm chart-ით, შეინარჩუნეთ HTTP ingress `/`-ზე და დაამატეთ gRPC ingress იმავე ჰოსტისთვის. მხოლოდ HTTP ingress აცხადებს TLS-ს:

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

gRPC სამიზნე ჯგუფებს სჭირდებათ HTTPS listener. ამ listener-ზე:

1. გადაამისამართეთ ნაგულისხმევი წესი სამიზნე ჯგუფზე პროტოკოლის ვერსიით `HTTP1` `KURA_PORT`-ზე, ჯანმრთელობის შემოწმებით HTTP-ით `/ready`-ზე.
2. შექმენით მეორე სამიზნე ჯგუფი პროტოკოლის ვერსიით `gRPC`, პროტოკოლის გამოყენებით `HTTP` `KURA_GATEWAY_GRPC_PORT`-ზე (ან `KURA_PORT`), ან პროტოკოლი `HTTPS` `KURA_HTTPS_PORT`-ზე. დააკონფიგურირეთ მისი ჯანმრთელობის შემოწმება ზემოთ აღწერილი გზით.
3. დაამატეთ წესი, რომელიც გადაამისამართებს გზის ნიმუშებს `/build.bazel.remote.execution.v2.*`, `/google.bytestream.*`, `/build.bazel.remote.asset.v1.*` და `/google.devtools.build.v1.*` მეორე სამიზნე ჯგუფზე.
4. გაზარდეთ დატვირთვის ბალანსერის უმოქმედობის таймаუთი მინიმუმ 300 წამამდე.

### CDN-ები {#load-balancers-cdns}

კვანძის წინ მდებარე CDN-მა უნდა მხარი დაუჭიროს gRPC-ს და არ უნდა დაბლოკოს gRPC გზები თავისი firewall წესებით. კლიენტები ტვირავენ დიდ არტეფაქტებს მაქსიმუმ 2 MiB ზომის ნაწილებად და აწყობენ მათ კვანძზე, ამიტომ არცერთ მოთხოვნას არ სჭირდება დიდი სხეული ან ხანგრძლივი ატვირთვა. მოდულის ქეში და Xcode კომპილაციის ქეში ასე იქცევიან, ისევე როგორც Bazel, თუ აგებულია `--experimental_remote_cache_chunking` ფლაგით (Bazel 8.7 და 9.1 ან უახლესი). ამ ფლაგის გარეშე, Bazel ტვირავენ თითოეულ გამომავალ ფაილს ერთ მოთხოვნაში, ამიტომ CDN-მა ასევე უნდა დაუშვას დიდი მოთხოვნის სხეულები და ატვირთვები, რომლებიც იმდენ ხანს გრძელდება, რამდენსაც თქვენი უდიდესი გამომავალი ფაილები საჭიროებენ თქვენს ყველაზე ნელა არხზე. თუ თქვენი CDN ვერ აკმაყოფილებს ამ მოთხოვნებს, მიეცით კლიენტებს ჰოსტნეიმი, რომელიც აუვლის მას გვერდს, მაგალითად, მხოლოდ DNS ჩანაწერი.

#### Cloudflare {#load-balancers-cloudflare}

მოდულის ქეშირება მუშაობს პროქსირებული Cloudflare ჰოსტნეიმის მეშვეობით ნებისმიერ პაკეტზე. ზონაში:

1. **Network**-ის ქვეშ, ჩართეთ **gRPC**.
2. **SSL/TLS**-ის ქვეშ, დააყენეთ დაშიფვრის რეჟიმი **Full** ან **Full (strict)**. Cloudflare უკავშირდება origin-ს 443 პორტზე, ამიტომ origin-მა უნდა მოემსახუროს TLS-ს იქ და შესთავაზოს HTTP/2 ALPN-ის მეშვეობით.
3. დარწმუნდით, რომ არცერთი WAF მორგებული წესი ან მართული წესი არ ბლოკავს ზემოთ ჩამოთვლილ gRPC გზებს.

Cloudflare ასრულებს მოთხოვნას, თუ origin-მა დაახლოებით ორი წუთის შემდეგაც არ დაიწყო პასუხის გაგზავნა. Bazel ატვირთვა `--experimental_remote_cache_chunking`-ის გარეშე მიიღებს პასუხს მხოლოდ მას შემდეგ, რაც მისი ბოლო ბაიტი მივა, ამიტომ Cloudflare-ზე ასეთი ატვირთვები ვერ ხერხდება, თუ ისინი ამ დროზე მეტს გრძელდება.

## კვანძების Tuist-თან დაკავშირება {#connect-nodes-to-tuist}

დააკონფიგურირეთ კლიენტის მარშრუტიზაცია და დაარეგისტრირეთ თქვენი კვანძები Tuist-ში, რათა მათი მისამართები, მზადყოფნა და გამოყენება გამოჩნდეს დაფაზე.

**self-hosted Tuist server**-ზე, თქვენ აცხადებთ endpoint-ებს სტატიკურად `TUIST_CACHE_ENDPOINTS`-ის მეშვეობით, როგორც ეს ნაჩვენებია ზემოთ განლაგების სექციებში. CLI იყენებს პირველ კონფიგურირებულ URL-ს. `TUIST_CACHE_ENDPOINT` გადაფარავს ამ URL-ს ინდივიდუალური კლიენტისთვის.

**Tuist-hosted server**-ზე, დააყენეთ `TUIST_CACHE_ENDPOINT` დეველოპერის shell-ებში და CI-ში, რათა ქეშის მოთხოვნები მიმართოთ თქვენს კვანძებზე. თითოეული კვანძი ავტორიზდება თქვენს მიერ შექმნილი credential-ით, შემდეგ რეგისტრირებს თავის მისამართს და აცნობებს თავის მზადყოფნას დაფას. ეს სექცია ეხება კვანძის რეგისტრაციას.

> [!IMPORTANT]
> **Enterprise plan**
>
> Self-hosted cache კვანძები ხელმისაწვდომია Enterprise პაკეტზე. ქვემოთ აღწერილი **Self-hosted servers** სექცია ჩნდება მხოლოდ იმ ანგარიშებისთვის, რომლებიც ამ პაკეტზე არიან.

### კვანძის credential-ის გენერირება {#generate-a-node-credential}

Tuist დაფაზე, გახსენით თქვენი ანგარიში, გადადით **Cache**-ზე და იპოვეთ **Self-hosted servers**. აირჩიეთ **Generate credential** კლიენტის ID-ისა და საიდუმლოს შესაქმნელად.

credential ავტორიზებს მხოლოდ იმ ანგარიშის ტრაფიკს, რომელმაც ის შექმნა.

საიდუმლო გამოისახება ერთხელ და არ არის აღდგენადი დიალოგის დახურვის შემდეგ, ამიტომ პირდაპირ დააკოპირეთ ის საიდუმლოების საცავში, საიდანაც თქვენი კვანძები კითხულობენ. credential-ის გაუქმება მაშინვე აჩერებს ყველა კვანძს, რომელიც მას იყენებს, ავტორიზაციისგან, ამიტომ შექმენით ჩამნაცვლებელი სანამ გააუქმებთ მოქმედ credential-ს.

### კვანძის ჩარიცხვა ჩატვირთვისას {#enroll-the-node-on-boot}

ჩარიცხვა არის კვანძის ამუშავების რეკომენდებული გზა. დააყენეთ `KURA_ENROLL_ON_BOOT` და მიეცით კვანძს მისი credential და საკუთარი peer URL:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

კვანძი ადგილობრივად ქმნის თავის გასაღებების წყვილს, ამიტომ პირადი გასაღები არასდროს ტოვებს მას, და იღებს ხელმოწერილ peer სერტიფიკატს, ანგარიშის CA-ს, მის tenant იდენტიფიკატორს და peer-ების სიას. ეს არის ყველაფერი, რასაც წინააღმდეგ შემთხვევაში ხელით დააკონფიგურირებდით: ჩარიცხულ კვანძს არ სჭირდება `KURA_TENANT_ID`, არ `KURA_PEERS` და არ peer TLS კონფიგურაცია.

დატოვეთ `KURA_INTERNAL_TLS_*` დაუყენებელი: ჩარიცხვა წერს სერტიფიკატის მასალას `tls` დირექტორიაში `KURA_DATA_DIR`-ის ქვეშ. დააყენეთ ეს გზები თავად მხოლოდ მაშინ, როცა თქვენ აწვდით სერტიფიკატებს ჩარიცხვის ნაცვლად, როგორც აღწერილია [Build a cache mesh](#build-a-cache-mesh)-ში.

კვანძი, რომელიც პირველად უერთდება ანგარიშის mesh-ს, იღებს ანგარიშის არსებულ ქეშს სანამ გახდება რგოლის მომსახურე წევრი. გაზომეთ მონაცემთა მოცულობა მთელი ქეშისთვის და მოელით, რომ პირველი შეერთება გარკვეულ დროს წაიღებს ფართო არხზე. კვანძი აცნობებს `joining`-ს სანამ არ დაეწევა, შემდეგ `serving`-ს.

### endpoint-ის რეკლამირება {#advertise-the-endpoint}

ჩარიცხვა აერთებს mesh-ში. რეგისტრაცია აცნობებს კვანძის კლიენტისთვის ხილულ მისამართს და მზადყოფნას Tuist-ს. დააყენეთ რეგისტრაციის ცვლადები:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

კვანძი აგზავნის heartbeat-ს ყოველ 60 წამში 180-წამიანი იჯარის წინააღმდეგ. Tuist მიიჩნევს მის რეგისტრაციას ხელმიუწვდომლად, როცა იჯარა ამოიწურება. Tuist არასდროს უკავშირდება კვანძს, ამიტომ ის მხოლოდ თქვენი კლიენტებისთვის უნდა იყოს ხელმისაწვდომი, არა ინტერნეტიდან.

### დაადასტურეთ, რომ კვანძი ემსახურება {#verify-the-node-is-serving}

დაფაზე **Cache**-ში დაბრუნებისას, კვანძი ჩნდება **Registered nodes**-ის ქვეშ თავისი endpoint-ით, რეგიონით, სტატუსით და ბოლო heartbeat-ით. კვანძი, რომელიც არასდროს ჩნდება, ვერ აღწევს რეგისტრაციის endpoint-ს ან ვერ ახერხებს ავტორიზაციას. კვანძი, რომელიც ჩნდება და შემდეგ ქრება, შეწყვიტა heartbeat-ის გაგზავნა ან შეწყვიტა თავისი მზადყოფნის შესახებ ანგარიშგება.

### tenant იდენტიფიკატორის თქვენი ანგარიშის handle-თან შედარება {#match-the-tenant-identifier}

`KURA_TENANT_ID` უნდა ემთხვეოდეს თქვენს Tuist ანგარიშის handle-ს. საკონტროლო სიბრტყე ადარებს heartbeat-ის tenant-ს credential-დან ამოხსნილ ანგარიშს და უარყოფს შეუსაბამობას `409 tenant_mismatch`-ით, ამიტომ კვანძი არასწორი მნიშვნელობით წარმატებით ავტორიზდება, მაგრამ მაინც ვერასდროს რეგისტრირდება.

> [!IMPORTANT]
> როგორც Helm chart, ასევე ამ სახელმძღვანელოში ადრე მოყვანილი კონტეინერის მაგალითი ნაგულისხმევად აყენებს ამას `default`-ზე. ეს მნიშვნელობა სწორია self-hosted Tuist server-ისთვის, სადაც tenant არის ადგილობრივი ლეიბლი, და არასწორია Tuist-hosted server-ზე ანგარიშისთვის, სადაც მან უნდა დაასახელოს ანგარიში. კვანძის ჩარიცხვა სრულად აცილებს ამ საკითხს, რადგან საკონტროლო სიბრტყე აწვდის მნიშვნელობას.

დაუყენებელი `KURA_TENANT_ID` არ ტოვებს შემოწმებას. ის სრულად თიშავს რეგისტრაციას: კვანძი აგრძელებს ქეშის ტრაფიკის მომსახურებას, დაფაზე არაფერი ჩნდება და არანაირი შეცდომა არ ანგარიშდება. თუ კვანძი ჯანმრთელია, მაგრამ აკლია **Registered nodes**-ს, პირველ რიგში შეამოწმეთ ეს ცვლადი.

### აირჩიეთ რეკლამირებული URL, რომელსაც თქვენი კლიენტები მიაღწევენ {#choose-an-advertised-url}

გამოიყენეთ კლიენტისთვის ხელმისაწვდომი მისამართი `KURA_ADVERTISED_HTTP_URL`-ისთვის და ქეშის URL-ისთვის, რომელიც კონფიგურირებულია Tuist server-ზე ან CLI-ში.

მხოლოდ შიდა ჰოსტნეიმი შესაფერისია, როცა ყველა კლიენტი, რომელიც კონფიგურირებულია მის გამოყენებაზე, შეუძლია ამ სახელის გარჩევა და მიღწევა. სხვადასხვა ქსელში მყოფი კლიენტებისთვის, გამოიყენეთ საერთო ხელმისაწვდომი მისამართი ან დააკონფიგურირეთ ხელმისაწვდომი ქეშის კვანძი თითოეული გარემოსთვის.

## ქეშის mesh-ის აგება {#build-a-cache-mesh}

ქეშის mesh საშუალებას გაძლევთ განათავსოთ ქეშის სიმძლავრე იმ გამოთვლითი რესურსების გვერდით, რომლებსაც ის სჭირდება. კომპანიამ შეიძლება გაუშვას ერთი კვანძი მთავარი CI გამშვებების (runners) ახლოს, მეორე ევროპაში მყოფ დეველოპერებთან ახლოს, ხოლო მესამე აშშ-ის ოფისთან ან რეგიონულ ბილდ კლასტერთან ახლოს. თითოეული ადგილმდებარეობა კითხულობს და წერს უახლოეს კვანძთან, ხოლო Kura ფონურად ახდენს არტიფაქტებისა და მეტამონაცემების რეპლიკაციას, რათა მოგვიანებით სხვა ადგილმდებარეობებში შესრულებულმა ბილდებმა შეძლონ იგივე შედეგების ხელახლა გამოყენება.

mesh მუშაობს მხოლოდ მაშინ, თუ კვანძებს შეუძლიათ ერთმანეთთან დაკავშირება Kura-ს შიდა peer პორტზე. ეს peer სიბრტყე გამოყოფილია იმ საჯარო ქეშის endpoint-ებისგან, რომლებსაც Tuist კლიენტები იყენებენ. Kura იყენებს მას წევრობის შესამოწმებლად, ახლად შეერთებული კვანძების მონაცემებით შესავსებად (backfill) და არტიფაქტების რეპლიკაციისთვის ადგილობრივი ჩაწერების მიღების შემდეგ.

ჩვენ მკაცრად გირჩევთ peer სიბრტყის დაცვას [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication)-ით, როდესაც კვანძები ერთმანეთთან უკავშირდებიან რეგიონებს, ღრუბლებს, VPC-ებს, ოფისებს ან ნებისმიერ ქსელს შორის, რომელიც არ არის სრულად იზოლირებული ქეშის განლაგებისთვის. mTLS-ის ჩართვისას, Kura შიდა რეპლიკაციის endpoint-ებს მხოლოდ იმ peer-ებს უწევს, რომლებიც წარმოადგენენ კონფიგურირებული CA-ს მიერ ხელმოწერილ სერტიფიკატს. peer სერტიფიკატებმა უნდა მოიცვან DNS სახელები, რომლებსაც კვანძები იყენებენ ერთმანეთთან დასაკავშირებლად, და peer URL-ებმა უნდა გამოიყენონ `https://` შიდა პორტზე.

> [!NOTE]
> კვანძები, რომლებიც რეგისტრირდებიან Tuist-hosted საკონტროლო სიბრტყეზე, რეგისტრაციის დროს იღებენ თავიანთ peer სერტიფიკატს და ანგარიშის CA-ს, ამიტომ ქვემოთ მოყვანილი ხელით შესრულებული ნაბიჯები ეხება იმ mesh-ებს, რომლებიც არ რეგისტრირდებიან.

მაგალითად, ეს ქმნის პირად CA-ს და ერთ peer სერტიფიკატს, რომლის დამაგრებაც (mounting) შეუძლია მცირე mesh-ის ყოველ კვანძს. შეცვალეთ DNS სახელები იმ შიდა სახელებით, რომლებსაც თქვენი კვანძები იყენებენ `KURA_NODE_URL`-ში და `KURA_PEERS`-ში.

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

კვანძი, რომელიც უერთდება ან ხელახლა უერთდება mesh-ს, **ავსებს გამოტოვებულ მონაცემებს (backfills)**: ის გადახედავს თითოეული peer-ის ჩანაწერებს უახლესიდან ძველისკენ და ჩამოიტანს იმას, რაც აკლია, ხოლო ცოცხალი რეპლიკაცია ფარავს ჩაწერებს, რომლებიც შესრულდა peer-ის ხილვადობის პერიოდში. backfill-ის ერთი ციკლი მიჰყვება peer-ის უახლეს ჩანაწერს უკან, კვანძის segment-ring-ის ჰორიზონტამდე ან მის ბოლო დასრულებულ ციკლამდე (რაც უფრო ძველია), ამიტომ კვანძი გარანტირებულად შეიცავს ბოლო დროის მონაცემებს, თუმცა არა აუცილებლად ყველაფერს. `KURA_BACKFILL_MARGIN_PERCENT` განსაზღვრავს, თუ რამდენად შორს მიდის ეს ჰორიზონტი.

ორი შედეგის ცოდნა ღირს mesh-ის გაშვებამდე:

- კვანძი ანგარიშობს `/ready`-ს, როდესაც მისი segment ring არის `KURA_BACKFILL_READY_RING_PERCENT`-ით სავსე **ან** მისი პირველი backfill ციკლი დასრულდება, და მზადყოფნა (readiness) ნარჩუნდება პროცესის სიცოცხლის დარჩენილ ნაწილში. მოგვიანებით peer-ის გათიშვა არასდროს აცილებს მომსახურე კვანძს როტაციიდან.
- ციკლი ასევე სრულდება, როდესაც peer გარკვეული დროის განმავლობაში მიუწვდომელია. კვანძი, რომლის ერთადერთი peer გამორთულია, ამიტომ ხდება Ready, თუნდაც ცოტა ან საერთოდ არ ჰქონდეს მონაცემები. ის უპასუხებს გამოტოვებებს (misses) და არა შეცდომებს. `/status/rollout` ანგარიშობს `backfill_initial_cycle`-ს (`pending`, `complete` ან `degraded`), თუ გსურთ განლაგების (rollout) შეჩერება ამ განსხვავების საფუძველზე.

**mesh-ის განახლება backfill-ის ცვლილების გადაკვეთისას.** Kura-ს იმ ვერსიებში, რომლებიც backfill-ს უსწრებენ, სინქრონიზაცია ხდებოდა სხვა, ახლა უკვე წაშლილი peer პროტოკოლის საშუალებით. გადაიყვანეთ ყოველი კვანძი ისეთ ვერსიაზე, რომელიც ასრულებს backfill-ს **მანამ**, სანამ აიღებთ ვერსიას, რომელიც მხოლოდ backfill-ზე საუბრობს. ორ პროტოკოლზე მყოფ კვანძებს ერთმანეთთან სინქრონიზაცია არ შეუძლიათ: "თბილი" კვანძი აგრძელებს მომსახურებას თავისი დისკიდან, მაგრამ წყვეტს სხვაობის აღმოფხვრას, ხოლო კვანძი, რომელიც ამ ფანჯარაში ცარიელი დისკით იწყებს მუშაობას, არასდროს ხდება Ready. chart აყენებს `KURA_BACKFILL_ENABLED=true`-ს თქვენთვის, ამიტომ chart-ის პირველადი განახლება ფარავს ამას. ერთი `helm upgrade`, რომელიც ერთდროულად ანახლებს chart-სა და image-ს, არ ფარავს.

გამოიყენეთ ქსელის დონის შეზღუდვები mTLS-ის დამატებით. Kubernetes-ში, გაუშვით Kura როგორც `StatefulSet`, თითოეულ pod-ზე ერთი persistent volume-ით და headless სერვისით peer-ების აღმოსაჩენად, შემდეგ კი დაუშვით შიდა peer პორტი მხოლოდ იმ pod-ებს შორის, რომლებიც ეკუთვნიან იმავე ქეშის განლაგებას, მაგალითად, `NetworkPolicy`-ის გამოყენებით. Kubernetes-ის გარეთ, მიანიჭეთ თითოეულ კვანძს სტაბილური DNS სახელი ან IP მისამართი, შეავსეთ mesh სხვა კვანძების შიდა URL-ებით და გამოიყენეთ firewall-ის წესები ან security groups, რათა მხოლოდ ქეშის კვანძებმა შეძლონ peer პორტთან მიღწევა. საჯარო ქეშის ტრაფიკი უნდა შედიოდეს საჯარო HTTP ან gRPC endpoint-ების საშუალებით და არა შიდა peer სიბრტყის მეშვეობით.

## კონფიგურაცია {#configuration}

Helm chart აგენერირებს ზოგად runtime პარამეტრებს `values.yaml`-დან. თუ Kura-ს Kubernetes-ის გარეშე აშვებთ, დააყენეთ იგივე ცვლადები პირდაპირ პროცესზე. ცვლადები, რომლებსაც chart პირდაპირ არ ასახავს, შეიძლება ჩაინექტოს `extraEnv` ან `extraEnvFrom`-ის საშუალებით.

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმევი | Helm მნიშვნელობა |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | საჯარო ქეშის პორტი. ერთი listener ემსახურება HTTP ქეშის API-ს, ჯანმრთელობის endpoint-ებს და Bazel/Buck2 REAPI gRPC-ს (h2c). | კი | ნაგულისხმევი არ არის | `service.httpPort` |
| `KURA_INTERNAL_PORT` | შიდა HTTP ან mTLS პორტი, რომელსაც Kura peer-ები იყენებენ. | კი | ნაგულისხმევი არ არის | `peerTls.internalPort` |
| `KURA_TENANT_ID` | კვანძის ნაგულისხმევი tenant იდენტიფიკატორი. | კი | ნაგულისხმევი არ არის | `config.tenantId` |
| `KURA_REGION` | რეგიონის ლეიბლი, რომელიც გამოიყენება მეტრიკებსა და რეპლიკაციის მდგომარეობაში. | კი | ნაგულისხმევი არ არის | `config.region` |
| `KURA_TMP_DIR` | დროებითი დირექტორია request body-ების staging-ისა და multipart აწყობისთვის. | კი | ნაგულისხმევი არ არის | ფიქსირებულია `/var/cache/kura/tmp`-ზე |
| `KURA_TMP_DIR_MAX_BYTES` | მაქსიმალური staged byte-ები, რომლებიც დაიშვება `KURA_TMP_DIR`-ში, სანამ requests მიიღებენ backpressure-ს. | არა | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | მუდმივი დირექტორია მეტამონაცემების მდგომარეობისა და segment ფაილებისთვის. | კი | ნაგულისხმევი არ არის | ფიქსირებულია `/var/cache/kura`-ზე |
| `KURA_NODE_URL` | კანონიკური შიდა URL, რომელსაც სხვა peer-ები იყენებენ ამ კვანძთან დასაკავშირებლად. | კი | ნაგულისხმევი არ არის | მიღებულია pod-ის DNS სახელიდან და `peerTls.internalPort`-დან |
| `KURA_PEERS` | Seed peer-ების სია, რომელიც გამოიყენება აღმოჩენის კონვერგენციამდე. | არა | `KURA_NODE_URL` | მიღებულია StatefulSet რეპლიკებიდან |
| `KURA_DISCOVERY_DNS_NAME` | DNS სახელი, რომელიც გამოიყენება ავტომატური peer აღმოჩენისთვის. | არა | გამორთულია | ჩართულია `config.discovery.enabled`-ით |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | CA სერთიფიკატი, რომელიც გამოიყენება peer mTLS-ის ვერიფიკაციისთვის. | არა | გამორთულია, ან მიღებულია `KURA_DATA_DIR`-ის ქვეშ, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | სერთიფიკატი, რომელიც გამოიყენება შიდა peer mTLS listener-ის მიერ. | არა | გამორთულია, ან მიღებულია `KURA_DATA_DIR`-ის ქვეშ, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | პირადი გასაღები, რომელიც გამოიყენება შიდა peer mTLS listener-ის მიერ. | არა | გამორთულია, ან მიღებულია `KURA_DATA_DIR`-ის ქვეშ, როდესაც კვანძი რეგისტრირდება | `peerTls.enabled` და `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | სერთიფიკატი, რომელიც გამოიყენება TLS-ის დასასრულებლად თანამფლობელ HTTPS listener-ზე (`KURA_HTTPS_PORT`). | არა | გამორთულია | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | პირადი გასაღები, რომელიც შეესაბამება `KURA_PUBLIC_TLS_CERT_PATH`-ს. | არა | გამორთულია | `extraEnv` |
| `KURA_HTTPS_PORT` | TLS პორტი, რომელიც ემსახურება იმავე თანამფლობელ HTTP + gRPC ზედაპირს (ALPN-ით შეთანხმებული). იბმება მხოლოდ მაშინ, როდესაც საჯარო TLS გზები დაყენებულია. | არა | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | Plaintext HTTP/2 პორტი, რომელიც ემსახურება მხოლოდ gRPC API-ებს, პროქსებისთვის, რომლებიც ხელახლა იყენებენ upstream კავშირებს. იხილეთ [კვანძების განთავსება load balancer-ის უკან](#load-balancers). | არა | გამორთულია | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | ფაილის დესკრიპტორების ბიუჯეტი request და ფონური I/O-სთვის. | არა | ავტომატურად მიღებული | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | რამდენ ხანს ელოდება request, სანამ FD backpressure ჩააგდებს checkout-ს. | არა | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | პინირებული სეგმენტის წაკითხვის handle-ების მაქსიმალური რაოდენობა. | არა | ავტომატურად მიღებული | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | შეწყვეტის დროს ფრენაში მყოფი HTTP და gRPC სამუშაოებისთვის განკუთვნილი გრეის პერიოდი. | არა | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | მეხსიერების რბილი ზღვარი, სადაც Kura იწყებს არასავალდებულო მეხსიერების გამოყენების შემცირებას. | არა | ავტომატურად მიღებული | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | მეხსიერების მკაცრი ზღვარი, სადაც Kura აჩერებს რეპლიკაციას და ასუფთავებს ცხელ caches-ს. | არა | ავტომატურად მიღებული | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | მეხსიერებაში მყოფი manifest cache-ის მაქსიმალური ზომა. | არა | ავტომატურად მიღებული | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | მაქსიმალური keyvalue payload-ის ზომა თითო request-ზე. | არა | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | ფაილის დესკრიპტორების ბიუჯეტი, რომელიც შენახულია metadata store-ისთვის. | არა | ავტომატურად მიღებული | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | ფონური flush-ისა და compaction-ის კონკურენტულობა metadata store-ისთვის. | არა | ავტომატურად მიღებული | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | metadata-store read cache-ის ტევადობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | მთლიანი მეხსიერების ბიუჯეტი, რომელიც შენახულია metadata ჩაწერის ბუფერიზაციისთვის. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | თითოეული metadata ჩაწერის ბუფერის ზომა flush-ამდე. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | მეხსიერებაში შენახული metadata ჩაწერის ბუფერების მაქსიმალური რაოდენობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | რამდენ ხანს შეიძლება დარჩეს მიმდინარე multipart upload ვადის გასვლამდე. | არა | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | რამდენად ხშირად ამოწმებს Kura მოძველებულ multipart uploads-ს. | არა | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | ასაკის მიხედვით დალაგებული სეგმენტების რგოლის წილი, რომელიც ითვლება უახლესიდან და განსაზღვრავს, თუ რამდენად შორს აღწევს backfill pass. | არა | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | სეგმენტების რგოლის სისავსე, რომლის დროსაც კვანძი, რომელიც ჯერ კიდევ ასრულებს თავის პირველ backfill ციკლს, იუწყება მზაობას. | არა | `KURA_BACKFILL_MARGIN_PERCENT`-ის ნახევარი | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | ბაიტების ზღვარი, რომლის მიხედვითაც იქმნება ერთი backfill bodies batch, და ზომა, რომლის ზემოთაც ჩანაწერი ცალ-ცალკე იტვირთება. | არა | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio worker threads-ის რაოდენობა. | არა | ავტომატურად მიღებული | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP traces endpoint. დატოვეთ ცარიელი ტრეისინგის გასათიშად. | არა | გამორთულია | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry სერვისის სახელი. | კი | ნაგულისხმები არ აქვს | Pod-ის სახელი Helm-ში |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry განლაგების გარემო. | კი | ნაგულისხმები არ აქვს | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | Sentry DSN პანიკისა და შეცდომების შესახებ ანგარიშგებისთვის. | არა | გამორთულია | `extraEnv` ან `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | ISO 3166-1 alpha-2 ქვეყანა, სადაც მდებარეობს datacenter, რომელშიც კვანძი მუშაობს, ექსპორტირებულ traces-ზე აღბეჭდილი როგორც `geo.country.iso_code`. | არა | მიღებულია `KURA_REGION`-დან, როცა მისი პრეფიქსი წარმოადგენს ქვეყნის კოდს | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | იმ datacenter-ის ISO 3166-2 ქვედანაყოფი (მაგ., `US-CA`), აღბეჭდილი როგორც `geo.region.iso_code`. | არა | დაყენებული არ არის | `extraEnv` |
| `KURA_AUTH_ENABLED` | მოითხოვს, რომ გამომძახებლებმა წარმოადგინონ მოქმედი Tuist token. `KURA_AUTH_TUIST_URL`-ის დაყენება თვითონვე რთავს ავტორიზაციას, ხოლო ამის `false`-ზე დაყენება არ თიშავს მას უკან — URL-ის გაუქმება საჭიროა კვანძის ავტორიზაციის გარეშე გასაშვებად. | არა | გამორთულია | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | Tuist სერვერი, რომლის წინააღმდეგაც კვანძი ახდენს ავტორიზაციას. თვითონვე რთავს ავტორიზაციას. | საჭიროა, როცა ავტორიზაცია ჩართულია | ნაგულისხმები არ აქვს | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | Connect timeout იმ სერვერზე ზარებისთვის. | არა | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | Request timeout იმ სერვერზე ზარებისთვის. | არა | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | გაზიარებული secret token-ებისთვის, რომლებსაც კვანძს შეუძლია თვითონ წაიკითხოს, round trip-ის გამოტოვებით. ის ასევე აწერს ხელს, როგორც ამოწმებს, ამიტომ გამოიყენეთ მხოლოდ იქ, სადაც კვანძი და სერვერი ერთი და იგივე ნდობის საზღვარშია. Self-hosted კვანძები ჩვეულებრივ ტოვებენ ამას დაუყენებლად. | არა | გამორთულია | `extraEnv` ან `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | სერვერის მიერ cache token-ების ხელმოწერისთვის გამოყენებული keypair-ის საჯარო ნაწილი, ერთი ან რამდენიმე შეერთებული PEM ბლოკის სახით. კითხულობს ამ token-ებს მათი შექმნის შესაძლებლობის გარეშე, რაც ინტერნეტიდან ხელმისაწვდომი კვანძისთვის უნდა იყოს. ურთიერთგამომრიცხავია `KURA_AUTH_JWT_SECRET`-თან. | არა | გამორთულია | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | ალგორითმი ამ გასაღებისთვის: `HS256`, `HS384` ან `HS512` secret-ით, `ES256` საჯარო გასაღებით. | არა | `HS256` secret-ით, `ES256` საჯარო გასაღებით | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | გამომცემელი, რომელიც token-ებმა უნდა შეიცავდეს. | არა | შემოწმებული არ არის | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | მძლეობით გამოყოფილი audiences, რომლებიც token-ებმა უნდა შეიცავდეს. | არა | შემოწმებული არ არის | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | მაქსიმალური ჩანაწერები, რომლებიც ინახება ავთენტიკაციისა და ავტორიზაციის თითოეულ cache-ში. | არა | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | არეგისტრირებს კვანძს control plane-თან ყოველ ჩატვირთვაზე, ამზადებს მის peer certificate-ს და აწვდის `KURA_TENANT_ID`-ს და `KURA_PEERS`-ს. | არა | გამორთულია | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | Tuist სერვერი, რომლის წინააღმდეგაც კვანძი რეგისტრირდება. | საჭიროა რეგისტრაციისას | ნაგულისხმები არ აქვს | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | კვანძის credential-ის Client ID, რომელიც გენერირდება dashboard-ში. | საჭიროა რეგისტრაციის ან დარეგისტრირებისას | ნაგულისხმები არ აქვს | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | Client secret, რომელიც შეწყვილებულია `KURA_CONTROL_PLANE_CLIENT_ID`-თან. | საჭიროა რეგისტრაციის ან დარეგისტრირებისას | ნაგულისხმები არ აქვს | `extraEnv` |
| `KURA_REGISTRATION_URL` | აბსოლუტური URL, რომელზეც კვანძი აგზავნის რეგისტრაციის heartbeats-ს, რითაც აცხადებს თავის client-facing endpoint-ს. | საჭიროა დარეგისტრირებისას | ნაგულისხმები არ აქვს | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | Client-facing cache URL, რომელსაც control plane აწვდის კლიენტებს. უნდა იყოს ხელმისაწვდომი ანგარიშის ყველა კლიენტისთვის. | საჭიროა დარეგისტრირებისას | ნაგულისხმები არ აქვს | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | რეგისტრაციის heartbeat cadence. Lease მოიცავს რამდენიმე გამოტოვებულ heartbeat-ს, ამიტომ ერთი გამოტოვებული heartbeat არ აშორებს endpoint-ს. | არა | `60000` | `extraEnv` |

თუ შიდა peer mTLS-ს ჩართავთ, ერთად დააყენეთ `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH` და `KURA_INTERNAL_TLS_KEY_PATH`. `KURA_NODE_URL` და `KURA_PEERS`-ში ყველა მნიშვნელობამ შემდეგ უნდა გამოიყენოს `https://` შიდა peer port-თან.
