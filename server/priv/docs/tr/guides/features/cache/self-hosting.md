---
{
  "title": "Kendi sunucunuzda barındırılan önbellek",
  "titleTemplate": ":title | Önbellek | Kılavuzlar | Tuist",
  "description": "Kendi sunucunuzda barındırılan önbellek düğümlerini dağıtın ve bunları Tuist'e bağlayın."
}
---

# Kendi sunucunuzda barındırılan önbellek {#self-hosted-cache}

Kendi sunucunuzda barındırılan önbellek düğümleri, derleme yapıtlarını ve önbellek meta verilerini bu çıktıları üreten ve tüketen makinelerin yakınında tutmanızı sağlar. CI, geliştirici ofisleri, uzak iş istasyonları veya bölgesel hesaplama kümeleri arasında önbellek gecikmesinin önemli olduğu durumlarda bunları kullanın.

Amaç, yalnızca merkezi bir önbelleğin yakın olduğu tek bir ortamda değil, her yerde düşük gecikmeli önbellekleme sağlamaktır. Her önbellek düğümü yerel diskten okuma ve yazma işlemlerine hizmet ederken, ağ diğer konumların zamanla aynı önbellekten faydalanabilmesi için yapıtları ve meta verileri eşler arasında çoğaltır.

> [!NOTE]
> Tuist'in kendi sunucusunda barındırılan önbellek düğümleri, Tuist'in merkezi olmayan önbellek ağı olan [Kura](https://github.com/tuist/tuist/tree/main/kura) tarafından desteklenmektedir. Kura, önbellek düğümleri için veri düzlemidir: önbellek okuma ve yazma işlemlerine hizmet eder, yerel durumu diskte saklar ve yapıtları ile meta verileri eş düğümlere çoğaltır.

## Kendi sunucunuzda barındırılan önbelleğin Tuist ile entegrasyonu {#how-self-hosted-cache-fits-with-tuist}

Tuist'in yönetilen önbelleği `https://<account>.cache.tuist.dev` adresini kullanır. Kendi sunucunuzda barındırılan bir Tuist sunucusuyla, CLI önbellek URL'sini sunucunun `TUIST_CACHE_ENDPOINTS` ayarından alır. Bunu ana önbellek sunucunuzun veya yük dengeleyicinizin URL'sine ayarlayın. Birden fazla URL içeriyorsa ilk olanı kullanılır.

**Barındırılan Tuist sunucusuna** bağlı özel/özel önbellek düğümleri için, geliştirici kabuklarında ve CI'da açık bir uç nokta ayarlayın:

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

Bu geçersiz kılma, her iki sunucu türünde de önceliklidir ve kendi sunucunuzda barındırılan Tuist sunucuları için isteğe bağlıdır. Xcode önbellek arka plan programı için, LaunchAgent'in güncellenmiş ortamı alması amacıyla ayarı yaptıktan sonra `tuist setup cache` komutunu yeniden çalıştırın.

Kendi sunucunuzda barındırılan bir Tuist sunucusu uç noktaları statik yapılandırmadan alır. Tuist tarafından barındırılan sunucuda, düğümler bir kimlik bilgisiyle kimlik doğrulaması yapar ve kendilerini kaydeder. Aşağıdaki iki bölümden birini kullanarak önce bir düğüm dağıtın, ardından [Tuist'e düğüm bağlama](#connect-nodes-to-tuist) bölümüne bakın.

## Kubernetes üzerinde dağıtım {#deploy-on-kubernetes}

Kura, GitHub Container Registry üzerinden bir Helm grafiği olarak dağıtılır. Kura'yı kalıcı birimlerle bir `StatefulSet` olarak, eş keşfi için headless bir servis ve HTTP ile gRPC trafiği için normal bir servis ile dağıtır.

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

Aynı kümedeki kendi sunucunuzda barındırılan bir Tuist sunucusu için ana önbellek uç noktasını yapılandırın:

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

Bu, sunucu pod'unda `TUIST_CACHE_ENDPOINTS` ayarını yapar. Geliştirici makinelerinin ve CI'nın erişebileceği bir adres kullanın; yukarıdaki küme içi servis adı, küme içinde çalışan istemciler için uygundur.

> [!IMPORTANT]
> Her Kura düğümü kendi `KURA_DATA_DIR` alanına sahip olmalıdır. Kura, veri dizini üzerinde uygulama düzeyinde bir yazar kilidi alır ve buna tam olarak bir sürecin sahip olmasını bekler. Kubernetes'te, pod başına bir kalıcı birim kullanın. Kubernetes dışında, birden fazla süreci aynı monte edilmiş dizine yönlendirmeyin.

## Kubernetes olmadan dağıtım {#deploy-without-kubernetes}

Kura, VM'lerde veya bare-metal sunucularda normal bir konteyner olarak da çalışabilir. Bu modda süreç denetimi, kalıcı depolama, yönlendirme ve eş keşfinden siz sorumlusunuz.

En azından her düğümün kalıcı bir veri dizinine, geçici bir dizine, genel bir önbellek portuna (tek bir dinleyici hem HTTP önbellek API'sine hem de REAPI gRPC'ye hizmet eder), dahili bir eş URL'sine ve ya statik bir eş listesine ya da bir keşif mekanizmasına ihtiyacı vardır:

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

Kendi sunucunuzda barındırılan bir Tuist sunucusunda, geliştirici makinelerinin ve CI'nın erişebileceği ana önbellek URL'sini yapılandırın:

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## Düğümleri bir yük dengeleyicinin arkasına yerleştirme {#load-balancers}

İstemciler her önbellek uç noktası URL'sini hem HTTP hem de gRPC için kullanır: sağlık kontrolleri ve HTTP önbellek API'si için HTTP, modül önbelleği ve Bazel'in uzak önbelleği için gRPC. İstemciler ile Kura arasındaki herhangi bir giriş, yük dengeleyici veya CDN, her ikisini de aynı ana bilgisayar adı ve bağlantı noktasında iletmelidir. Bu, istemcilerin aldığı her uç nokta için geçerlidir çünkü CLI en hızlı yanıt verenini seçer. gRPC Kura'ya ulaşamazsa, CLI uzak modül önbelleklemanın kullanılamadığı konusunda uyarır ve yalnızca yerel modül önbelleğini kullanır.

Bu yol öneklerini Kura'ya HTTP/2 üzerinden gRPC olarak, diğer her şeyi ise HTTP olarak yönlendirin:

| Yol öneki | Kullanan |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | Modül önbelleği, Bazel |
| `/google.bytestream.` | Modül önbelleği, Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel derleme olayları |

Kura, `KURA_PORT` üzerinde düz metin HTTP/2 (h2c) ve `KURA_PUBLIC_TLS_CERT_PATH` ile `KURA_PUBLIC_TLS_KEY_PATH` ayarlandığında `KURA_HTTPS_PORT` üzerinde TLS üzerinden HTTP/2 kabul eder. Proxy'niz ingress-nginx gibi istekler arasında upstream bağlantıları yeniden kullanıyorsa, `KURA_GATEWAY_GRPC_PORT` ayarlayın ve gRPC trafiğini bunun yerine o porta gönderin. Yalnızca gRPC'ye hizmet verir, bu nedenle HTTP/1.1 ve gRPC istekleri asla aynı bağlantıyı paylaşmaz.

gRPC rotalarını şu şekilde yapılandırın:

- İstek gövde boyutu sınırı yok. Bir yükleme, tek bir istekte 2 GiB'a kadar tek bir dosya gönderir.
- İstek ve yanıt arabelleğe alma kapalı.
- Okuma, gönderme ve boşta kalma zaman aşımları en az 300 saniye.

Kura, gRPC sağlık kontrolü hizmetini sunmaz. Düğümleri HTTP üzerinden `/ready` adresinden sağlık kontrolünden geçirin. Yük dengeleyiciniz bir gRPC sağlık kontrolü gerektiriyorsa, `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` çağrısını yapın ve `0` ile `16` gRPC durum kodlarını kabul edin. Yetkilendirme etkin olan bir düğüm, token içermeyen bir isteğe `16` (`UNAUTHENTICATED`) ile yanıt verir.

### ingress-nginx {#load-balancers-ingress-nginx}

Helm grafiği ile HTTP girişini `/` üzerinde tutun ve aynı ana bilgisayar için bir gRPC girişi ekleyin. Yalnızca HTTP girişi TLS bildirir:

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

gRPC hedef grupları bir HTTPS dinleyicisine ihtiyaç duyar. Bu dinleyicide:

1. Varsayılan kuralı, `KURA_PORT` üzerinde `HTTP1` protokol sürümüne sahip bir hedef gruba iletin ve `/ready` üzerinden HTTP ile sağlık kontrolü yapın.
2. `KURA_GATEWAY_GRPC_PORT` (veya `KURA_PORT`) üzerinde `HTTP` protokolünü kullanan veya `KURA_HTTPS_PORT` üzerinde `HTTPS` protokolünü kullanan `gRPC` protokol sürümüne sahip ikinci bir hedef grup oluşturun. Sağlık kontrolünü yukarıda açıklandığı gibi yapılandırın.
3. `/build.bazel.remote.execution.v2.*`, `/google.bytestream.*`, `/build.bazel.remote.asset.v1.*` ve `/google.devtools.build.v1.*` yol desenlerini ikinci hedef gruba ileten bir kural ekleyin.
4. Yük dengeleyicinin boşta kalma zaman aşımını en az 300 saniyeye çıkarın.

### CDN'ler {#load-balancers-cdns}

Bir düğümün önündeki bir CDN, gRPC'yi desteklemeli ve güvenlik duvarı kurallarında gRPC yollarını engellememelidir. İstemciler büyük yapıtları en fazla 2 MiB'lik parçalar halinde yükler ve bunları düğümün birleştirmesini sağlar; bu nedenle hiçbir isteğin büyük bir gövdeye veya uzun bir yükleme süresine ihtiyacı yoktur. Modül önbelleği ve Xcode derleme önbelleği bunu yapar; Bazel de `--experimental_remote_cache_chunking` ile derlendiğinde bunu yapar (Bazel 8.7 ve 9.1 veya sonrası). Bu bayrak olmadan, Bazel her çıktıyı tek bir istekte yükler; bu nedenle CDN'nin ayrıca büyük istek gövdelerine ve en yavaş bağlantınızda en büyük çıktılarınızın ihtiyaç duyduğu kadar süren yüklere izin vermesi gerekir. CDN'niz bu gereksinimleri karşılayamıyorsa, istemcilere onu atlayan bir ana bilgisayar adı verin, örneğin yalnızca DNS kaydı.

#### Cloudflare {#load-balancers-cloudflare}

Modül önbelleğe alma, herhangi bir planda proxylenen bir Cloudflare ana bilgisayar adı üzerinden çalışır. Bölgede:

1. **Ağ** altında, **gRPC**'yi açın.
2. **SSL/TLS** altında şifreleme modunu **Tam** veya **Tam (katı)** olarak ayarlayın. Cloudflare kaynak sunucuya 443 numaralı bağlantı noktasından bağlanır, bu nedenle kaynak sunucu orada TLS hizmeti vermeli ve ALPN üzerinden HTTP/2 sunmalıdır.
3. Yukarıda listelenen gRPC yollarını engelleyen hiçbir WAF özel kuralı veya yönetilen kural olmadığından emin olun.

Cloudflare, kaynak sunucu yaklaşık iki dakika sonra yanıt vermeye başlamadığında bir isteği sonlandırır. `--experimental_remote_cache_chunking` olmadan yapılan bir Bazel yüklemesi, ancak son baytı geldiğinde yanıtlanır; bu nedenle Cloudflare'de bu tür yüklemeler bundan daha uzun sürdüğünde başarısız olur.

## Düğümleri Tuist'e bağlama {#connect-nodes-to-tuist}

İstemci yönlendirmesini yapılandırın ve düğümlerinizi Tuist'e kaydedin, böylece adresleri, hazır olma durumları ve kullanımları panoda görünsün.

**Kendi barındırdığınız Tuist sunucusunda**, uç noktaları yukarıdaki dağıtım bölümlerinde gösterildiği gibi `TUIST_CACHE_ENDPOINTS` ile statik olarak bildirirsiniz. CLI, yapılandırılan ilk URL'yi kullanır. `TUIST_CACHE_ENDPOINT`, tek bir istemci için o URL'yi geçersiz kılar.

**Tuist tarafından barındırılan sunucuda**, önbellek isteklerini düğümlerinize yönlendirmek için geliştirici kabuklarında ve CI'da `TUIST_CACHE_ENDPOINT` ayarlayın. Her düğüm, oluşturduğunuz bir kimlik bilgisiyle kimlik doğrulaması yapar, ardından adresini kaydeder ve hazır olma durumunu panoya bildirir. Bu bölüm düğüm kaydını kapsar.

> [!IMPORTANT]
> **Enterprise planı**
>
> Kendi barındırdığınız önbellek düğümleri Enterprise planında kullanılabilir. Aşağıda açıklanan **Kendi barındırılan sunucular** bölümü yalnızca bu plandaki hesaplar için görünür.

### Bir düğüm kimlik bilgisi oluşturma {#generate-a-node-credential}

Tuist panosunda hesabınızı açın, **Önbellek** bölümüne gidin ve **Kendi sunucularınız** seçeneğini bulun. Bir istemci kimliği ve gizli anahtar oluşturmak için **Kimlik bilgisi oluştur** seçeneğini belirleyin.

Kimlik bilgisi yalnızca onu oluşturan hesap için trafiği yetkilendirir.

Gizli anahtar bir kez gösterilir ve iletişim kutusunu kapattıktan sonra kurtarılamaz; bu nedenle onu doğrudan düğümlerinizin okuduğu gizli anahtar deposuna kopyalayın. Bir kimlik bilgisini iptal etmek, onu kullanan her düğümün kimlik doğrulamasını hemen durdurur; bu nedenle hizmette olan bir kimlik bilgisini iptal etmeden önce yedeğini oluşturun.

### Düğümü başlangıçta kaydetme {#enroll-the-node-on-boot}

Kayıt, bir düğümü ayağa kaldırmanın önerilen yoludur. `KURA_ENROLL_ON_BOOT` ayarlayın ve düğüme kimlik bilgisini ve kendi eş URL'sini verin:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

Düğüm anahtar çiftini yerel olarak oluşturur, bu nedenle özel anahtar asla düğümden ayrılmaz; imzalı bir eş sertifikası, hesap CA'sı, kiracı tanımlayıcısı ve eş listesini alır. Aksi takdirde elle yapılandıracağınız her şey budur: kayıtlı bir düğümün `KURA_TENANT_ID`, `KURA_PEERS` veya eş TLS kurulumuna ihtiyacı yoktur.

`KURA_INTERNAL_TLS_*` ayarlanmamış bırakın: kayıt, sertifika malzemesini `KURA_DATA_DIR` altındaki bir `tls` dizinine yazar. Bu yolları yalnızca kaydettirmek yerine sertifikaları kendiniz sağladığınızda, [Önbellek ağı oluşturma](#build-a-cache-mesh) bölümünde açıklandığı gibi ayarlayın.

Bir hesabın ağına ilk kez katılan bir düğüm, halkanın hizmet veren bir üyesi haline gelmeden önce hesabın mevcut önbelleğini çeker. Veri birimini tüm önbellek için boyutlandırın ve ilk katılımın geniş alan bağlantısında biraz zaman almasını bekleyin. Düğüm, yetişene kadar `joining` durumunu bildirir, ardından `serving`.

### Uç noktayı duyurma {#advertise-the-endpoint}

Kayıt, ağa katılmayı sağlar. Kayıt, düğümün istemciye yönelik adresini ve hazır olma durumunu Tuist'e bildirir. Kayıt değişkenlerini ayarlayın:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

Düğüm, 180 saniyelik bir kira süresine karşı her 60 saniyede bir kalp atışı gönderir. Tuist, kira süresi dolduğunda kaydını kullanılamaz olarak kabul eder. Tuist düğümü asla aramaz, bu nedenle düğümün yalnızca istemcileriniz tarafından erişilebilir olması gerekir, internetten değil.

### Düğümün hizmet verdiğini doğrulama {#verify-the-node-is-serving}

Panodaki **Önbellek** bölümüne geri döndüğünüzde, düğüm uç noktası, bölgesi, durumu ve son kalp atışıyla birlikte **Kayıtlı düğümler** altında görünür. Hiçbir zaman görünmeyen bir düğüm, kayıt uç noktasına ulaşamıyor veya yetkilendirmede başarısız oluyor demektir. Görünüp sonra kaybolan bir düğüm, kalp atışı göndermeyi veya hazır olduğunu bildirmeyi durdurmuş demektir.

### Hesabın kalıcı kiracı tanımlayıcısını kullanma {#match-the-tenant-identifier}

`KURA_TENANT_ID`, hesabın kalıcı önbellek kimliğidir. Hiçbir zaman yeniden adlandırılmamış bir hesap için, hesap tanıtıcısına eşittir. Yeniden adlandırmadan sonra, değiştirme düğümleri dahil olmak üzere her düğümde orijinal değeri koruyun: bunu değiştirmek farklı bir depolama ad alanı seçer ve hesabı yeniden adlandırmak depolanan yapıtları taşımaz. Kiracıyı, hesabın mevcut URL'sinden çıkarmak yerine mevcut bir düğümden veya kayıt tarafından döndürülen `tenant_id` değerinden yeniden kullanın.

Kontrol düzlemi, kalp atışındaki kiracıyı kimlik bilgisinden çözümlenen hesapla karşılaştırır ve uyuşmazlığı `409 tenant_mismatch` ile reddeder; bu nedenle yanlış değere sahip bir düğüm başarıyla kimlik doğrulaması yapar ve yine de asla kayıt olmaz.

> [!IMPORTANT]
> Hem Helm grafiği hem de bu kılavuzun önceki bölümlerindeki kapsayıcı örneği bunu varsayılan olarak `default` olarak ayarlar. Düğümü kaydetmeden önce bunu hesabın kiracı tanımlayıcısıyla değiştirin. Düğümü kaydetmek sorunu tamamen ortadan kaldırır, çünkü kontrol düzlemi değeri sağlar.

Ayarlanmamış bir `KURA_TENANT_ID`, kontrolü atlamaz. Kaydı tamamen devre dışı bırakır: düğüm önbellek trafiğine hizmet vermeye devam eder, panoda hiçbir şey görünmez ve hata raporlanmaz. Bir düğüm sağlıklıysa ancak **Kayıtlı düğümler** listesinde eksikse, önce bu değişkeni kontrol edin.

### İstemcilerinizin ulaşabileceği bir duyurulan URL seçme {#choose-an-advertised-url}

`KURA_ADVERTISED_HTTP_URL` ve Tuist sunucusunda veya CLI'da yapılandırılan önbellek URL'si için istemcilerin ulaşabileceği bir adres kullanın.

Yalnızca dahili kullanım için olan bir ana makine adı, onu kullanacak şekilde yapılandırılmış her istemci bu adı çözümlayıp ulaşabildiğinde uygundur. Farklı ağlardaki istemciler için paylaşılan ve erişilebilir bir adres kullanın veya her ortam için erişilebilir bir önbellek düğümü yapılandırın.

## Önbellek ağı oluşturma {#build-a-cache-mesh}

Önbellek ağı, önbellek kapasitesini buna ihtiyaç duyan hesaplama kaynaklarının yanına yerleştirmenizi sağlar. Bir şirket, ana CI çalıştırıcılarının yakınında bir düğüm, Avrupa'daki geliştiricilere yakın başka bir düğüm ve ABD ofisi veya bölgesel derleme kümesine yakın üçüncü bir düğüm çalıştırabilir. Her konum en yakın düğüme okuma ve yazma yaparken, Kura arka planda yapıtları ve meta verileri çoğaltır; böylece diğer konumlardaki sonraki derlemeler aynı çıktıları yeniden kullanabilir.

Ağ yalnızca düğümler Kura'nın dahili eş portu üzerinden birbirine ulaşabildiğinde çalışır. Bu eş düzlemi, Tuist istemcilerinin kullandığı genel önbellek uç noktalarından ayrıdır. Kura bunu üyelikleri kontrol etmek, yeni katılan düğümleri geri doldurmak ve yerel yazmalar kabul edildikten sonra yapıtları çoğaltmak için kullanır.

Düğümler bölgeler, bulutlar, VPC'ler, ofisler veya önbellek dağıtımına tamamen özel olmayan herhangi bir ağ arasında iletişim kurduğunda eş düzlemini [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication) ile güvence altına almanızı şiddetle öneririz. mTLS etkinleştirildiğinde, Kura yalnızca yapılandırılmış CA tarafından imzalanmış bir sertifika sunan eşlere dahili çoğaltma uç noktaları sunar. Eş sertifikaları, düğümlerin birbirini aramak için kullandığı DNS adlarını kapsamalı ve eş URL'leri dahili portta `https://` kullanmalıdır.

> [!NOTE]
> Tuist tarafından barındırılan bir kontrol düzlemine kayıt olan düğümler, kayıt sırasında eş sertifikalarını ve hesap CA'sını alır; bu nedenle aşağıdaki manuel adımlar kayıt olmayan ağlar için geçerlidir.

Örneğin, bu işlem özel bir CA ve küçük bir ağdaki her düğüm tarafından monte edilebilecek tek bir eş sertifikası oluşturur. DNS adlarını, düğümlerinizin `KURA_NODE_URL` ve `KURA_PEERS` içinde kullandığı dahili adlarla değiştirin.

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

### Düğümler arasında yakalama {#catch-up-between-nodes}

Bir ağa katılan veya yeniden katılan bir düğüm **geri doldurma** yapar: her eşin girdilerini en yeniden eskiye doğru tarar ve eksik olanları çeker; canlı çoğaltma ise eş görünürken yapılan yazmaları kapsar. Bir geri doldurma turu, eşin en yeni girdisinden başlayarak düğümün segment halkası ufku ile son tamamlanan turun daha eski olanına kadar uzanır; bu sayede düğümün yakın tarihli verilere sahip olması garanti edilir, ancak mutlaka tüm verilere sahip olması gerekmez. `KURA_BACKFILL_MARGIN_PERCENT`, ufkun ne kadar geriye uzandığını belirler.

Bir ağ çalıştırmadan önce bilinmesi gereken iki sonuç vardır:

- Bir düğüm, segment halkası `KURA_BACKFILL_READY_RING_PERCENT` doluluğa ulaştığında **veya** ilk geri doldurma döngüsü kararlı hale geldiğinde `/ready` bildirir ve hazır durumu süreç ömrünün geri kalanında korunur. Daha sonraki bir eş dalgalanması, hizmet veren bir düğümü rotasyondan çıkarmaz.
- Bir eş yeterince uzun süre erişilemez olduğunda da bir döngü kararlı hale gelir. Tek eşi kapalı olan bir düğüm bu nedenle az veya hiç veri tutarken Hazır durumuna geçer. Hatalar yerine isabet dışı durumları (miss) sunar. Farklılığa dayalı bir yayını engellemek istiyorsanız `/status/rollout`, `backfill_initial_cycle` (`pending`, `complete` veya `degraded`) raporlar.

**Geri doldurma değişikliği sırasında bir ağın yükseltilmesi.** Geri doldurma öncesi Kura sürümleri, artık kaldırılmış farklı bir eş protokolü üzerinden yakalama yapar. Yalnızca geri doldurma konuşan bir sürüme geçmeden **önce** her düğümü geri doldurma çalışan bir sürüme taşıyın. İki protokoldeki düğümler birbirinden yakalama yapamaz: sıcak bir düğüm biriminden hizmet vermeye devam eder ancak açığını kapatmayı durdurur ve bu pencerede boş bir birimle başlayan bir düğüm asla Hazır durumuna geçmez. Grafik sizin için `KURA_BACKFILL_ENABLED=true` ayarladığından, önce grafiği yükseltmek bunu kapsar. Grafiği ve imajı birlikte taşıyan tek bir `helm upgrade` bunu yapmaz.

mTLS'ye ek olarak ağ düzeyinde kısıtlamalar kullanın. Kubernetes'te Kura'yı pod başına bir kalıcı birim ve eş keşfi için headless bir hizmet ile bir `StatefulSet` olarak çalıştırın, ardından dahili eş portuna yalnızca aynı önbellek dağıtımına ait podlar arasında izin verin; örneğin bir `NetworkPolicy` ile. Kubernetes dışında, her düğüme kararlı bir DNS adı veya IP adresi atayın, ağı diğer düğümlerin dahili URL'leriyle tohumlayın ve yalnızca önbellek düğümlerinin eş portuna ulaşabilmesi için güvenlik duvarı kuralları veya güvenlik grupları kullanın. Genel önbellek trafiği, dahili eş düzlemi üzerinden değil, genel HTTP veya gRPC uç noktaları üzerinden girmelidir.

## Yapılandırma {#configuration}

Helm grafiği, ortak çalışma zamanı ayarlarını `values.yaml` dosyasından oluşturur. Kura'yı Kubernetes olmadan çalıştırıyorsanız, aynı değişkenleri doğrudan süreçte ayarlayın. Grafiğin doğrudan eşlemediği değişkenler `extraEnv` veya `extraEnvFrom` aracılığıyla enjekte edilebilir.

| Ortam değişkeni | Açıklama | Gerekli | Varsayılan | Helm değeri |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | Genel önbellek portu. Tek bir dinleyici HTTP önbellek API'sine, sağlık uç noktalarına ve Bazel/Buck2 REAPI gRPC'ye (h2c) hizmet verir. | Evet | Varsayılan yok | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Kura eşleri tarafından kullanılan dahili HTTP veya mTLS portu. | Evet | Varsayılan yok | `peerTls.internalPort` |
| `KURA_TENANT_ID` | Düğüm için varsayılan kiracı tanımlayıcısı. | Evet | Varsayılan yok | `config.tenantId` |
| `KURA_REGION` | Metriklerde ve çoğaltma durumunda kullanılan bölge etiketi. | Evet | Varsayılan yok | `config.region` |
| `KURA_TMP_DIR` | Hazırlanmış istek gövdeleri ve çok parçalı birleştirme için geçici dizin. | Evet | Varsayılan yok | `/var/cache/kura/tmp` olarak sabitlenmiştir |
| `KURA_TMP_DIR_MAX_BYTES` | İstekler geri baskı almadan önce `KURA_TMP_DIR` içine kabul edilen maksimum hazırlanmış bayt sayısı. | Hayır | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | Meta veri durumu ve segment dosyaları için kalıcı dizin. | Evet | Varsayılan yok | `/var/cache/kura` olarak sabitlenmiştir |
| `KURA_NODE_URL` | Diğer eşlerin bu düğüme ulaşmak için kullandığı kanonik dahili URL. | Evet | Varsayılan yok | Pod DNS adından ve `peerTls.internalPort` değerinden türetilir |
| `KURA_PEERS` | Keşif yakınsamadan önce kullanılan tohum eş listesi. | Hayır | `KURA_NODE_URL` | StatefulSet kopyalarından türetilir |
| `KURA_DISCOVERY_DNS_NAME` | Otomatik eş keşfi için kullanılan DNS adı. | Hayır | Devre dışı | `config.discovery.enabled` tarafından etkinleştirilir |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | Eş mTLS'yi doğrulamak için kullanılan CA sertifikası. | Hayır | Devre dışı veya düğüm kaydolduğunda `KURA_DATA_DIR` altında türetilir | `peerTls.enabled` ve `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | Dahili eş mTLS dinleyicisi tarafından kullanılan sertifika. | Hayır | Devre dışı veya düğüm kaydolduğunda `KURA_DATA_DIR` altında türetilir | `peerTls.enabled` ve `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | Dahili eş mTLS dinleyicisi tarafından kullanılan özel anahtar. | Hayır | Devre dışı veya düğüm kaydolduğunda `KURA_DATA_DIR` altında türetilir | `peerTls.enabled` ve `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | Birlikte barındırılan HTTPS dinleyicisinde (`KURA_HTTPS_PORT`) TLS sonlandırmak için kullanılan sertifika. | Hayır | Devre dışı | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | `KURA_PUBLIC_TLS_CERT_PATH` ile eşleştirilmiş özel anahtar. | Hayır | Devre dışı | `extraEnv` |
| `KURA_HTTPS_PORT` | Aynı birlikte barındırılan HTTP + gRPC yüzeyine (ALPN müzakereli) hizmet veren TLS portu. Yalnızca genel TLS yolları ayarlandığında bağlanır. | Hayır | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | Yalnızca gRPC API'lerine hizmet veren, yukarı akış bağlantılarını yeniden kullanan proxy'ler için düz metin HTTP/2 portu. Bkz. [Düğümleri bir yük dengeleyici arkasına yerleştirme](#load-balancers). | Hayır | Devre dışı | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | İstek ve arka plan G/Ç için dosya tanımlayıcı bütçesi. | Hayır | Otomatik türetilir | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | Bir isteğin, FD geri baskısı nedeniyle kontrolü başarısız olmadan önce ne kadar beklediği. | Hayır | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | Sabitlemiş segment okuma işleyicilerinin maksimum sayısı. | Hayır | Otomatik türetilir | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | Kapatma sırasında devam eden HTTP ve gRPC işleri için hoşgörü penceresi. | Hayır | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Kura'nın isteğe bağlı bellek kullanımını azaltmaya başladığı yumuşak bellek eşiği. | Hayır | Otomatik türetilir | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Kura'nın çoğaltmayı duraklattığı ve sıcak önbellekleri kırpıldığı sert bellek eşiği. | Hayır | Otomatik türetilir | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | Bellek içi manifest önbelleğinin maksimum boyutu. | Hayır | Otomatik türetilir | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | İstek başına maksimum keyvalue yük boyutu. | Hayır | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | Meta veri deposu için ayrılan dosya tanımlayıcı bütçesi. | Hayır | Otomatik türetilir | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | Meta veri deposu için arka plan yazma ve birleştirme eşzamanlılığı. | Hayır | Otomatik türetilir | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | Meta veri deposu okuma önbelleğinin kapasitesi. | Hayır | Otomatik türetilir | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | Meta veri yazma arabelleği için ayrılan toplam bellek bütçesi. | Hayır | Otomatik türetilir | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | Yazmadan önce her bir meta veri yazma arabelleğinin boyutu. | Hayır | Otomatik türetilir | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | Bellekte tutulan maksimum meta veri yazma arabelleği sayısı. | Hayır | Otomatik türetilir | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | Devam eden çok parçalı bir yüklemenin süresi dolmadan önce ne kadar bekleyebileceği. | Hayır | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Kura'nın eski çok parçalı yüklemeleri ne sıklıkta taradığı. | Hayır | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | En yeniden sayılan, yaşa göre sıralanmış segment halkasının, bir geri doldurma geçişinin ne kadar geriye ulaşacağını sınırlayan payı. | Hayır | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | İlk geri doldurma döngüsü hâlâ çalışan bir düğümün kendini hazır olarak bildirdiği segment halkası doluluk oranı. | Hayır | `KURA_BACKFILL_MARGIN_PERCENT` yarısı | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | Bir geri doldurma gövde yığınının oluşturulduğu byte eşiği ve bir girdinin tek başına getirileceği boyut. | Hayır | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio iş parçacığı sayısı. | Hayır | Otomatik türetilir | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP izleme uç noktası. İzlemeyi devre dışı bırakmak için boş bırakın. | Hayır | Devre dışı | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry hizmet adı. | Evet | Varsayılan yok | Helm'deki Pod adı |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry dağıtım ortamı. | Evet | Varsayılan yok | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | Panic ve hata raporlaması için Sentry DSN. | Hayır | Devre dışı | `extraEnv` veya `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | Düğümün çalıştığı veri merkezinin ISO 3166-1 alpha-2 ülke kodu; dışa aktarılan izlere `geo.country.iso_code` olarak eklenir. | Hayır | Öneki bir ülke kodu olduğunda `KURA_REGION` değerinden türetilir | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | Bu veri merkezinin ISO 3166-2 alt bölümü (ör. `US-CA`); `geo.region.iso_code` olarak eklenir. | Hayır | Ayarlanmamış | `extraEnv` |
| `KURA_AUTH_ENABLED` | Arayanların geçerli bir Tuist jetonu sunmasını gerektirir. `KURA_AUTH_TUIST_URL` ayarlamak yetkilendirmeyi tek başına etkinleştirir ve bunu `false` olarak ayarlamak onu kapatmaz — yetkilendirme olmadan bir düğüm çalıştırmak için URL'yi kaldırın. | Hayır | Devre dışı | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | Düğümün yetkilendirme yaptığı Tuist sunucusu. Yetkilendirmeyi tek başına etkinleştirir. | Yetkilendirme etkin olduğunda gerekli | Varsayılan yok | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | Bu sunucuya yapılan çağrılar için bağlantı zaman aşımı. | Hayır | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | Bu sunucuya yapılan çağrılar için istek zaman aşımı. | Hayır | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | Düğümün tek başına okuyabileceği ve gidiş-dönüşü atlayabileceği jetonlar için paylaşılan gizli anahtar. Hem imzalar hem de doğrular, bu nedenle yalnızca düğüm ve sunucunun aynı güven sınırı içinde olduğu durumlarda kullanın. Kendi kendine barındırılan düğümler bunu genellikle ayarlanmamış bırakır. | Hayır | Devre dışı | `extraEnv` veya `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | Sunucunun önbellek jetonlarını imzaladığı anahtar çiftinin genel kısmı; bir veya daha fazla bitişik PEM bloğu olarak. Bu jetonları okur ancak yeni bir jeton basamaz; bu, internetten erişilebilen bir düğümün sahip olması gereken özelliktir. `KURA_AUTH_JWT_SECRET` ile karşılıklı olarak özel değildir. | Hayır | Devre dışı | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | Bu anahtar için algoritma: Gizli anahtarla `HS256`, `HS384` veya `HS512`; genel anahtarla `ES256`. | Hayır | Gizli anahtarla `HS256`, genel anahtarla `ES256` | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | Jetonların taşıması gereken yayıncı. | Hayır | Kontrol edilmiyor | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | Jetonların taşıması gereken, virgülle ayrılmış kitleler. | Hayır | Kontrol edilmiyor | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | Kimlik doğrulama ve yetkilendirme önbelleklerinin her birinde tutulan maksimum girdi sayısı. | Hayır | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | Her önyüklemede düğümü kontrol düzlemine kaydeder, eş sertifika sağlar ve `KURA_TENANT_ID` ile `KURA_PEERS` değerlerini sunar. | Hayır | Devre dışı | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | Düğümün kayıt yaptığı Tuist sunucusu. | Kayıt sırasında gerekli | Varsayılan yok | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | Panoda oluşturulan düğüm kimlik bilgilerinin İstemci Kimliği. | Kayıt veya tescil sırasında gerekli | Varsayılan yok | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | `KURA_CONTROL_PLANE_CLIENT_ID` ile eşleştirilmiş istemci gizli anahtarı. | Kayıt veya tescil sırasında gerekli | Varsayılan yok | `extraEnv` |
| `KURA_REGISTRATION_URL` | Düğümün istemciye yönelik uç noktasını duyurarak kayıt kalp atışlarını gönderdiği mutlak URL. | Tescil sırasında gerekli | Varsayılan yok | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | Kontrol düzleminin istemcilere sunduğu, istemciye yönelik önbellek URL'si. Hesaptaki her istemci tarafından erişilebilir olmalıdır. | Tescil sırasında gerekli | Varsayılan yok | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | Kayıt kalp atışı sıklığı. Kiralama birkaç kaçırılan kalp atışı genişliğindedir, bu nedenle tek bir kayıp kalp atışı uç noktayı düşürmez. | Hayır | `60000` | `extraEnv` |

Dahili eş mTLS'yi etkinleştirirseniz, `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH` ve `KURA_INTERNAL_TLS_KEY_PATH` değerlerini birlikte ayarlayın. `KURA_NODE_URL` ve `KURA_PEERS` içindeki her değer daha sonra dahili eş bağlantı noktasıyla `https://` kullanmalıdır.
