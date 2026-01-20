---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# Kendi kendine ana bilgisayar kurulumu {#self-host-installation}

Altyapıları üzerinde daha fazla kontrole ihtiyaç duyan kuruluşlar için Tuist
sunucusunun kendi kendine barındırılan bir sürümünü sunuyoruz. Bu sürüm, Tuist'i
kendi altyapınızda barındırmanıza olanak tanıyarak verilerinizin güvenli ve
gizli kalmasını sağlar.

::: warning LICENSE REQUIRED
<!-- -->
Tuist'in kendi kendine barındırılması yasal olarak geçerli ücretli bir lisans
gerektirir. Tuist'in şirket içi sürümü yalnızca Kurumsal plandaki kuruluşlar
için mevcuttur. Bu sürümle ilgileniyorsanız, lütfen
[contact@tuist.dev](mailto:contact@tuist.dev) adresine ulaşın.
<!-- -->
:::

## Serbest bırakma temposu {#release-cadence}

Tuist'in yeni sürümlerini, yeni yayınlanabilir değişiklikler main'e ulaştıkça
sürekli olarak yayınlıyoruz. Öngörülebilir sürümleme ve uyumluluk sağlamak için
[semantic versioning](https://semver.org/) yöntemini izliyoruz.

Ana bileşen, Tuist sunucusunda şirket içi kullanıcılarla koordinasyon
gerektirecek kırılma değişikliklerini işaretlemek için kullanılır. Bunu
kullanmamızı beklememelisiniz ve ihtiyaç duymamız halinde, geçişi sorunsuz hale
getirmek için sizinle birlikte çalışacağımızdan emin olabilirsiniz.

## Sürekli dağıtım {#continuous-deployment}

Tuist'in en son sürümünü her gün otomatik olarak dağıtan sürekli bir dağıtım
işlem hattı kurmanızı şiddetle tavsiye ederiz. Bu sayede her zaman en son
özelliklere, iyileştirmelere ve güvenlik güncellemelerine erişebilirsiniz.

İşte her gün yeni sürümleri kontrol eden ve dağıtan örnek bir GitHub Actions iş
akışı:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 3 * * *' # Run daily at 3 AM UTC
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

## Çalışma zamanı gereksinimleri {#runtime-requirements}

Bu bölümde, Tuist sunucusunu altyapınızda barındırmak için gerekenler
özetlenmektedir.

### Uyumluluk matrisi {#compatibility-matrix}

Tuist sunucusu test edilmiştir ve aşağıdaki minimum sürümlerle uyumludur:

| Bileşen     | Minimum Sürüm | Notlar                                                   |
| ----------- | ------------- | -------------------------------------------------------- |
| PostgreSQL  | 15            | TimescaleDB uzantısı ile                                 |
| TimescaleDB | 2.16.1        | Gerekli PostgreSQL uzantısı (kullanımdan kaldırılmıştır) |
| ClickHouse  | 25            | Analitik için gerekli                                    |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB şu anda Tuist sunucusu için gerekli bir PostgreSQL uzantısıdır ve
zaman serisi veri depolama ve sorgulama için kullanılmaktadır. Ancak,
**TimescaleDB kullanımdan kaldırılmıştır** ve tüm zaman serisi işlevlerini
ClickHouse'a taşıdığımız için yakın gelecekte gerekli bir bağımlılık olmaktan
çıkarılacaktır. Şimdilik, PostgreSQL örneğinizde TimescaleDB'nin yüklü ve etkin
olduğundan emin olun.
<!-- -->
:::

### Docker sanallaştırılmış görüntüleri çalıştırma {#running-dockervirtualized-images}

Sunucuyu [GitHub's Container
Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
aracılığıyla bir [Docker](https://www.docker.com/) görüntüsü olarak dağıtıyoruz.

Çalıştırmak için altyapınızın Docker görüntülerini çalıştırmayı desteklemesi
gerekir. Çoğu altyapı sağlayıcısının bunu desteklediğini unutmayın çünkü üretim
ortamlarında yazılım dağıtmak ve çalıştırmak için standart kapsayıcı haline
gelmiştir.

### Postgres veritabanı {#postgres-database}

Docker görüntülerini çalıştırmanın yanı sıra, ilişkisel ve zaman serisi
verilerini depolamak için [TimescaleDB uzantısı](https://www.timescale.com/)
olan bir [Postgres veritabanına](https://www.postgresql.org/) ihtiyacınız
olacaktır. Çoğu altyapı sağlayıcısı Postgres veritabanlarını tekliflerine dahil
eder (örneğin, [AWS](https://aws.amazon.com/rds/postgresql/) ve [Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

**TimescaleDB Uzantısı Gerekli:** Tuist, verimli zaman serisi veri depolama ve
sorgulama için TimescaleDB uzantısını gerektirir. Bu uzantı komut olayları,
analizler ve diğer zamana dayalı özellikler için kullanılır. Tuist'i
çalıştırmadan önce PostgreSQL örneğinizde TimescaleDB'nin yüklü ve etkin
olduğundan emin olun.

::: info MIGRATIONS
<!-- -->
Docker görüntüsünün giriş noktası, hizmeti başlatmadan önce bekleyen tüm şema
geçişlerini otomatik olarak çalıştırır. Geçişler eksik bir TimescaleDB uzantısı
nedeniyle başarısız olursa, önce bunu veritabanınıza yüklemeniz gerekir.
<!-- -->
:::

### ClickHouse veritabanı {#clickhouse-database}

Tuist, büyük miktarda analitik veriyi depolamak ve sorgulamak için
[ClickHouse](https://clickhouse.com/) kullanmaktadır. ClickHouse, build insights
gibi özellikler için **gerekli** ve TimescaleDB'yi aşamalı olarak
kaldırdığımızda birincil zaman serisi veritabanı olacak. ClickHouse'u kendiniz
barındırmayı ya da barındırılan hizmeti kullanmayı seçebilirsiniz.

::: info MIGRATIONS
<!-- -->
Docker görüntüsünün giriş noktası, hizmeti başlatmadan önce bekleyen tüm
ClickHouse şema geçişlerini otomatik olarak çalıştırır.
<!-- -->
:::

### Depolama {#storage}

Ayrıca dosyaları (örn. çerçeve ve kütüphane ikili dosyaları) depolamak için de
bir çözüme ihtiyacınız olacaktır. Şu anda S3 uyumlu tüm depolama alanlarını
destekliyoruz.

## Konfigürasyon {#configuration}

Hizmetin yapılandırması çalışma zamanında ortam değişkenleri aracılığıyla
yapılır. Bu değişkenlerin hassas yapısı göz önüne alındığında, şifrelenmelerini
ve güvenli parola yönetimi çözümlerinde saklanmalarını tavsiye ederiz. İçiniz
rahat olsun, Tuist bu değişkenleri son derece dikkatli bir şekilde ele alır ve
asla günlüklerde görüntülenmemelerini sağlar.

::: info LAUNCH CHECKS
<!-- -->
Gerekli değişkenler başlangıçta doğrulanır. Herhangi biri eksikse, başlatma
başarısız olur ve hata mesajı eksik değişkenleri detaylandırır.
<!-- -->
:::

### Lisans yapılandırması {#license-configuration}

Şirket içi bir kullanıcı olarak, bir ortam değişkeni olarak göstermeniz gereken
bir lisans anahtarı alırsınız. Bu anahtar, lisansı doğrulamak ve hizmetin
sözleşme şartları dahilinde çalıştığından emin olmak için kullanılır.

| Ortam değişkeni                    | Açıklama                                                                                                                                                                                                                                           | Gerekli | Varsayılan | Örnekler                                  |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ---------- | ----------------------------------------- |
| `TUIST_LICENSE`                    | Hizmet seviyesi anlaşması imzalandıktan sonra sağlanan lisans                                                                                                                                                                                      | Evet*   |            | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **TUIST_LICENSE` için olağanüstü bir alternatif**. Sunucunun harici hizmetlerle iletişim kuramadığı hava boşluklu ortamlarda çevrimdışı lisans doğrulaması için Base64 kodlu genel sertifika. Yalnızca `TUIST_LICENSE` kullanılamadığında kullanın | Evet*   |            | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* Ya `TUIST_LICENSE` ya da `TUIST_LICENSE_CERTIFICATE_BASE64` sağlanmalıdır,
ancak ikisi birden sağlanmamalıdır. Standart dağıtımlar için `TUIST_LICENSE`
kullanın.

::: warning EXPIRATION DATE
<!-- -->
Lisansların bir son kullanma tarihi vardır. Kullanıcılar, sunucu ile etkileşime
giren Tuist komutlarını kullanırken, lisansın süresinin 30 günden daha kısa bir
süre içinde dolması durumunda bir uyarı alacaklardır. Lisansınızı yenilemekle
ilgileniyorsanız, lütfen [contact@tuist.dev](mailto:contact@tuist.dev) adresine
ulaşın.
<!-- -->
:::

### Temel ortam yapılandırması {#base-environment-configuration}

| Ortam değişkeni                       | Açıklama                                                                                                                                                                                                                              | Gerekli | Varsayılan                         | Örnekler                                                                        |                                                                                                                                    |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ---------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | Örneğe İnternet'ten erişmek için temel URL                                                                                                                                                                                            | Evet    |                                    | https://tuist.dev                                                               |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | Bilgileri şifrelemek için kullanılacak anahtar (örneğin, bir çerezdeki oturumlar)                                                                                                                                                     | Evet    |                                    |                                                                                 | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Hash edilmiş parolalar oluşturmak için Pepper                                                                                                                                                                                         | Hayır   | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | Rastgele belirteçler oluşturmak için gizli anahtar                                                                                                                                                                                    | Hayır   | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | Hassas verilerin AES-GCM şifrelemesi için 32 baytlık anahtar                                                                                                                                                                          | Hayır   | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | `1` olduğunda, uygulamayı IPv6 adreslerini kullanacak şekilde yapılandırır                                                                                                                                                            | Hayır   | `0`                                | `1`                                                                             |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | Uygulama için kullanılacak günlük düzeyi                                                                                                                                                                                              | Hayır   | `bilgi`                            | [Günlük seviyeleri](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | GitHub uygulama adınızın URL sürümü                                                                                                                                                                                                   | Hayır   |                                    | `benim-uygulamam`                                                               |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | Otomatik PR yorumları göndermek gibi ekstra işlevlerin kilidini açmak için GitHub uygulaması için kullanılan base64 kodlu özel anahtar                                                                                                | Hayır   | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                                 |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | Otomatik PR yorumları gönderme gibi ekstra işlevlerin kilidini açmak için GitHub uygulaması için kullanılan özel anahtar. **Özel karakterlerle ilgili sorunları önlemek için bunun yerine base64 kodlu sürümü kullanmanızı öneririz** | Hayır   | `-----BAŞLA RSA...`                |                                                                                 |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | İşlem URL'lerine erişimi olan kullanıcı tanıtıcılarının virgülle ayrılmış listesi                                                                                                                                                     | Hayır   |                                    | `kullanıcı1,kullanıcı2`                                                         |                                                                                                                                    |
| `TUIST_WEB`                           | Web sunucusu uç noktasını etkinleştirin                                                                                                                                                                                               | Hayır   | `1`                                | `1` veya `0`                                                                    |                                                                                                                                    |

### Veritabanı yapılandırması {#database-configuration}

Veritabanı bağlantısını yapılandırmak için aşağıdaki ortam değişkenleri
kullanılır:

| Ortam değişkeni                      | Açıklama                                                                                                                                                                                                                                 | Gerekli | Varsayılan | Örnekler                                                               |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ---------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | Postgres veritabanına erişmek için URL. URL'nin kimlik doğrulama bilgilerini içermesi gerektiğini unutmayın                                                                                                                              | Evet    |            | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | ClickHouse veritabanına erişmek için URL. URL'nin kimlik doğrulama bilgilerini içermesi gerektiğini unutmayın                                                                                                                            | Hayır   |            | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | Doğru olduğunda, veritabanına bağlanmak için [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) kullanır                                                                                                                      | Hayır   | `1`        | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | Bağlantı havuzunda açık tutulacak bağlantı sayısı                                                                                                                                                                                        | Hayır   | `10`       | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | Havuzdan çıkış yapılan tüm bağlantıların kuyruk aralığından daha uzun sürüp sürmediğini kontrol etme aralığı (milisaniye cinsinden) [(Daha fazla bilgi)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)   | Hayır   | `300`      | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | Havuzun yeni bağlantıları bırakmaya başlayıp başlamayacağını belirlemek için kullandığı kuyruktaki eşik süresi (milisaniye cinsinden) [(Daha fazla bilgi)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | Hayır   | `1000`     | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse arabellek yıkamaları arasındaki milisaniye cinsinden zaman aralığı                                                                                                                                                            | Hayır   | `5000`     | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | Yıkamaya zorlamadan önce bayt cinsinden maksimum ClickHouse tampon boyutu                                                                                                                                                                | Hayır   | `1000000`  | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | Çalıştırılacak ClickHouse tampon işlemlerinin sayısı                                                                                                                                                                                     | Hayır   | `5`        | `5`                                                                    |

### Kimlik doğrulama ortamı yapılandırması {#authentication-environment-configuration}

Kimlik doğrulamayı [kimlik sağlayıcıları
(IdP)](https://en.wikipedia.org/wiki/Identity_provider) aracılığıyla
kolaylaştırıyoruz. Bunu kullanmak için, seçilen sağlayıcı için gerekli tüm ortam
değişkenlerinin sunucunun ortamında mevcut olduğundan emin olun. **Eksik
değişkenler** Tuist'in söz konusu sağlayıcıyı atlamasına neden olacaktır.

#### GitHub {#github}

Bir [GitHub
Uygulaması](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)
kullanarak kimlik doğrulaması yapmanızı öneririz, ancak [OAuth
Uygulaması](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)
da kullanabilirsiniz. GitHub tarafından belirtilen tüm temel ortam
değişkenlerini sunucu ortamına eklediğinizden emin olun. Eksik değişkenler
Tuist'in GitHub kimlik doğrulamasını gözden kaçırmasına neden olacaktır. GitHub
uygulamasını düzgün bir şekilde kurmak için:
- GitHub uygulamasının genel ayarlarında:
    - `İstemci Kimliğini` kopyalayın ve `TUIST_GITHUB_APP_CLIENT_ID olarak
      ayarlayın`
    - Yeni bir `istemci sırrı` oluşturup kopyalayın ve
      `TUIST_GITHUB_APP_CLIENT_SECRET olarak ayarlayın`
    - `Geri Arama URL'sini` ` http://YOUR_APP_URL/users/auth/github/callback`
      olarak ayarlayın. `YOUR_APP_URL` sunucunuzun IP adresi de olabilir.
- Aşağıdaki izinler gereklidir:
  - Depolar:
    - Çekme istekleri: Okuma ve yazma
  - Hesaplar:
    - E-posta adresleri: Salt okunur

`İzinler ve etkinlikler`'in `Hesap izinleri` bölümünde, `E-posta adresleri`
iznini `Salt okunur` olarak ayarlayın.

Daha sonra Tuist sunucusunun çalıştığı ortamda aşağıdaki ortam değişkenlerini
göstermeniz gerekecektir:

| Ortam değişkeni                  | Açıklama                             | Gerekli | Varsayılan | Örnekler                                   |
| -------------------------------- | ------------------------------------ | ------- | ---------- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub uygulamasının istemci kimliği | Evet    |            | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | Uygulamanın istemci sırrı            | Evet    |            | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

OAuth 2](https://developers.google.com/identity/protocols/oauth2) kullanarak
Google ile kimlik doğrulama ayarlayabilirsiniz. Bunun için, OAuth istemci
kimliği türünde yeni bir kimlik bilgisi oluşturmanız gerekir. Kimlik bilgilerini
oluştururken, uygulama türü olarak "Web Uygulaması "nı seçin, `Tuist` olarak
adlandırın ve yönlendirme URI'sini `{base_url}/users/auth/google/callback`
olarak ayarlayın; burada `base_url` barındırılan hizmetinizin çalıştığı URL'dir.
Uygulamayı oluşturduktan sonra, istemci kimliğini ve gizliliğini kopyalayın ve
bunları sırasıyla `GOOGLE_CLIENT_ID` ve `GOOGLE_CLIENT_SECRET` ortam
değişkenleri olarak ayarlayın.

::: info CONSENT SCREEN SCOPES
<!-- -->
Bir onay ekranı oluşturmanız gerekebilir. Bunu yaptığınızda, `userinfo.email` ve
`openid` kapsamlarını eklediğinizden ve uygulamayı dahili olarak
işaretlediğinizden emin olun.
<!-- -->
:::

#### Okta {#okta}

Okta ile kimlik doğrulamayı [OAuth 2.0](https://oauth.net/2/) protokolü
aracılığıyla etkinleştirebilirsiniz. Okta'da
<LocalizedLink href="/guides/integrations/sso#okta"> bu talimatları</LocalizedLink> izleyerek [bir uygulama
oluşturmanız](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)
gerekir.

Okta uygulamasının kurulumu sırasında istemci kimliğini ve gizliliğini elde
ettikten sonra aşağıdaki ortam değişkenlerini ayarlamanız gerekecektir:

| Ortam değişkeni              | Açıklama                                                                                   | Gerekli | Varsayılan | Örnekler |
| ---------------------------- | ------------------------------------------------------------------------------------------ | ------- | ---------- | -------- |
| `TUIST_OKTA_1_CLIENT_ID`     | Okta'ya karşı kimlik doğrulaması için istemci kimliği. Numara kuruluş kimliğiniz olmalıdır | Evet    |            |          |
| `TUIST_OKTA_1_CLIENT_SECRET` | Okta'ya karşı kimlik doğrulaması yapmak için istemci sırrı                                 | Evet    |            |          |

`1` numarasının kuruluş kimliğinizle değiştirilmesi gerekir. Bu genellikle 1
olacaktır, ancak veritabanınızı kontrol edin.

### Depolama ortamı yapılandırması {#storage-environment-configuration}

Tuist, API aracılığıyla yüklenen eserleri barındırmak için depolama alanına
ihtiyaç duyar. Tuist'in etkin bir şekilde çalışması için **desteklenen depolama
çözümlerinden birini** yapılandırmak çok önemlidir.

#### S3 uyumlu depolar {#s3compliant-storages}

Artifaktları depolamak için herhangi bir S3 uyumlu depolama sağlayıcısı
kullanabilirsiniz. Depolama sağlayıcısı ile entegrasyonu doğrulamak ve
yapılandırmak için aşağıdaki ortam değişkenleri gereklidir:

| Ortam değişkeni                                           | Açıklama                                                                                                                                                                              | Gerekli | Varsayılan                       | Örnekler                                                      |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | -------------------------------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` veya `AWS_ACCESS_KEY_ID`         | Depolama sağlayıcısına karşı kimlik doğrulaması yapmak için erişim anahtarı kimliği                                                                                                   | Evet    |                                  | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` veya `AWS_SECRET_ACCESS_KEY` | Depolama sağlayıcısına karşı kimlik doğrulaması yapmak için gizli erişim anahtarı                                                                                                     | Evet    |                                  | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` veya `AWS_REGION`                       | Kovanın bulunduğu bölge                                                                                                                                                               | Hayır   | `otomatik`                       | `abd-bati-2`                                                  |
| `TUIST_S3_ENDPOINT` veya `AWS_ENDPOINT`                   | Depolama sağlayıcısının uç noktası                                                                                                                                                    | Evet    |                                  | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                    | Eserlerin depolanacağı kovanın adı                                                                                                                                                    | Evet    |                                  | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                    | S3 HTTPS bağlantılarını doğrulamak için PEM kodlu CA sertifikası. Kendinden imzalı sertifikalara veya dahili Sertifika Yetkililerine sahip hava boşluklu ortamlar için kullanışlıdır. | Hayır   | Sistem CA paketi                 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                                | Depolama sağlayıcısıyla bağlantı kurmak için zaman aşımı (milisaniye cinsinden)                                                                                                       | Hayır   | `3000`                           | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                                | Depolama sağlayıcısından veri almak için zaman aşımı (milisaniye cinsinden)                                                                                                           | Hayır   | `5000`                           | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                                   | Depolama sağlayıcısına bağlantı havuzu için zaman aşımı (milisaniye cinsinden). Zaman aşımı olmaması için `infinity` adresini kullanın                                                | Hayır   | `5000`                           | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                             | Havuzdaki bağlantılar için maksimum boşta kalma süresi (milisaniye cinsinden). Bağlantıları süresiz olarak canlı tutmak için `infinity` adresini kullanın                             | Hayır   | `sonsuzluk`                      | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                      | Havuz başına maksimum bağlantı sayısı                                                                                                                                                 | Hayır   | `500`                            | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                     | Kullanılacak bağlantı havuzu sayısı                                                                                                                                                   | Hayır   | Sistem zamanlayıcılarının sayısı | `4`                                                           |
| `TUIST_S3_PROTOKOLÜ`                                      | Depolama sağlayıcısına bağlanırken kullanılacak protokol (`http1` veya `http2`)                                                                                                       | Hayır   | `http1`                          | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                                   | URL'nin bir alt alan adı (sanal ana bilgisayar) olarak kova adıyla oluşturulup oluşturulmayacağı                                                                                      | Hayır   | `Yanlış`                         | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
Depolama sağlayıcınız AWS ise ve bir web kimlik belirteci kullanarak kimlik
doğrulaması yapmak istiyorsanız, `TUIST_S3_AUTHENTICATION_METHOD` ortam
değişkenini `aws_web_identity_token_from_env_vars` olarak ayarlayabilirsiniz ve
Tuist geleneksel AWS ortam değişkenlerini kullanarak bu yöntemi kullanacaktır.
<!-- -->
:::

#### Google Bulut Depolama {#google-cloud-storage}
Google Cloud Storage için, `AWS_ACCESS_KEY_ID` ve `AWS_SECRET_ACCESS_KEY`
çiftini almak için [bu
dokümanları](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)
izleyin. ` AWS_ENDPOINT`, `https://storage.googleapis.com` olarak
ayarlanmalıdır. Diğer ortam değişkenleri diğer S3 uyumlu depolama alanlarıyla
aynıdır.

### E-posta yapılandırması {#email-configuration}

Tuist, kullanıcı kimlik doğrulaması ve işlem bildirimleri (örn. şifre
sıfırlamaları, hesap bildirimleri) için e-posta işlevselliği gerektirir. Şu
anda, **e-posta sağlayıcısı olarak yalnızca Mailgun** desteklenmektedir.

| Ortam değişkeni                  | Açıklama                                                                                                                                                    | Gerekli | Varsayılan                                                            | Örnekler                  |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | --------------------------------------------------------------------- | ------------------------- |
| `TUIST_MAILGUN_API_KEY`          | Mailgun ile kimlik doğrulama için API anahtarı                                                                                                              | Evet*   |                                                                       | `key-1234567890abcdef`    |
| `TUIST_MAILING_DOMAIN`           | E-postaların gönderileceği alan adı                                                                                                                         | Evet*   |                                                                       | `mg.tuist.io`             |
| `TUIST_MAILING_FROM_ADDRESS`     | "Kimden" alanında görünecek e-posta adresi                                                                                                                  | Evet*   |                                                                       | `noreply@tuist.io`        |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | Kullanıcı yanıtları için isteğe bağlı yanıt adresi                                                                                                          | Hayır   |                                                                       | `support@tuist.dev`       |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | Yeni kullanıcı kayıtları için e-posta onayını atlayın. Etkinleştirildiğinde, kullanıcılar otomatik olarak onaylanır ve kayıttan hemen sonra oturum açabilir | Hayır   | `true` e-posta yapılandırılmamışsa, `false` e-posta yapılandırılmışsa | `true`, `false`, `1`, `0` |

\* E-posta yapılandırma değişkenleri yalnızca e-posta göndermek istiyorsanız
gereklidir. Yapılandırılmazsa, e-posta onayı otomatik olarak atlanır

::: info SMTP SUPPORT
<!-- -->
Genel SMTP desteği şu anda mevcut değildir. Şirket içi dağıtımınız için SMTP
desteğine ihtiyacınız varsa, gereksinimlerinizi görüşmek için lütfen
[contact@tuist.dev](mailto:contact@tuist.dev) adresine ulaşın.
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
İnternet erişimi veya e-posta sağlayıcısı yapılandırması olmayan şirket içi
kurulumlar için e-posta onayı varsayılan olarak otomatik olarak atlanır.
Kullanıcılar kayıttan hemen sonra oturum açabilir. E-posta yapılandırmanız varsa
ancak yine de onayı atlamak istiyorsanız `TUIST_SKIP_EMAIL_CONFIRMATION=true`
ayarını yapın. E-posta yapılandırıldığında e-posta onayı gerektirmek için
`TUIST_SKIP_EMAIL_CONFIRMATION=false` ayarını yapın.
<!-- -->
:::

### Git platform yapılandırması {#git-platform-configuration}

Tuist, <LocalizedLink href="/guides/server/authentication"> Git platformları</LocalizedLink> ile entegre olarak çekme isteklerinize otomatik
olarak yorum gönderme gibi ekstra özellikler sağlayabilir.

#### GitHub {#platform-github}

Bir GitHub uygulaması]
(https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)
oluşturmanız gerekecektir. Bir OAuth GitHub uygulaması oluşturmadığınız sürece,
kimlik doğrulama için oluşturduğunuz uygulamayı yeniden kullanabilirsiniz. `
İzinler ve etkinlikler`'in `Depo izinleri` bölümünde, ek olarak `Çekme
istekleri` iznini `Okuma ve yazma` olarak ayarlamanız gerekecektir.

`TUIST_GITHUB_APP_CLIENT_ID` ve `TUIST_GITHUB_APP_CLIENT_SECRET` adreslerine ek
olarak aşağıdaki ortam değişkenlerine ihtiyacınız olacaktır:

| Ortam değişkeni                | Açıklama                           | Gerekli | Varsayılan | Örnekler                             |
| ------------------------------ | ---------------------------------- | ------- | ---------- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub uygulamasının özel anahtarı | Evet    |            | `-----BEGIN RSA PRIVATE KEY-----...` |

## Yerel Testler {#testing-locally}

Altyapınıza dağıtmadan önce Tuist sunucusunu yerel makinenizde test etmek için
gerekli tüm bağımlılıkları içeren kapsamlı bir Docker Compose yapılandırması
sağlıyoruz:

- TimescaleDB 2.16 uzantılı PostgreSQL 15 (kullanımdan kaldırılmıştır)
- Analizler için ClickHouse 25
- Koordinasyon için ClickHouse Keeper
- S3 uyumlu depolama için MinIO
- Dağıtımlar arasında kalıcı KV depolaması için Redis (isteğe bağlı)
- veritabanı yönetimi için pgweb

::: danger LICENSE REQUIRED
<!-- -->
Yerel geliştirme örnekleri de dahil olmak üzere Tuist sunucusunu çalıştırmak
için geçerli bir `TUIST_LICENSE` ortam değişkeni yasal olarak gereklidir. Bir
lisansa ihtiyacınız varsa, lütfen [contact@tuist.dev](mailto:contact@tuist.dev)
adresine ulaşın.
<!-- -->
:::

**Hızlı Başlangıç:**

1. Yapılandırma dosyalarını indirin:
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. Ortam değişkenlerini yapılandırın:
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE and authentication credentials
   ```

3. Tüm hizmetleri başlatın:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

4. Sunucuya http://localhost:8080 adresinden erişin

**Hizmet Uç Noktaları:**
- Tuist Sunucusu: http://localhost:8080
- MinIO Konsolu: http://localhost:9003 (kimlik bilgileri: `tuist` /
  `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**Ortak Komutlar:**

Servis durumunu kontrol edin:
```bash
docker compose ps
# or: podman compose ps
```

Günlükleri görüntüle:
```bash
docker compose logs -f tuist
```

Hizmetleri durdurun:
```bash
docker compose down
```

Her şeyi sıfırlayın (tüm verileri siler):
```bash
docker compose down -v
```

**Yapılandırma Dosyaları:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - Docker Compose
  yapılandırmasını tamamlayın
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse
  yapılandırması
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - ClickHouse Keeper yapılandırması
- [.env.example](/server/self-host/.env.example) - Örnek ortam değişkenleri
  dosyası

## Dağıtım {#deployment}

Resmi Tuist Docker görüntüsü şu adreste mevcuttur:
```
ghcr.io/tuist/tuist
```

### Docker görüntüsünü çekme {#pulling-the-docker-image}

Aşağıdaki komutu çalıştırarak görüntüyü alabilirsiniz:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

Ya da belirli bir sürümü çekin:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker görüntüsünü dağıtma {#deploying-the-docker-image}

Docker görüntüsü için dağıtım süreci, seçtiğiniz bulut sağlayıcısına ve
kuruluşunuzun sürekli dağıtım yaklaşımına göre farklılık gösterecektir.
Kubernetes](https://kubernetes.io/) gibi çoğu bulut çözümü ve aracı Docker
görüntülerini temel birimler olarak kullandığından, bu bölümdeki örnekler mevcut
kurulumunuzla uyumlu olmalıdır.

::: warning
<!-- -->
Dağıtım işlem hattınızın sunucunun çalışır durumda olduğunu doğrulaması
gerekiyorsa, `/ready` adresine bir `GET` HTTP isteği gönderebilir ve yanıtta bir
`200` durum kodu belirtebilirsiniz.
<!-- -->
:::

#### Uçmak {#fly}

Uygulamayı [Fly](https://fly.io/) üzerinde dağıtmak için bir `fly.toml`
yapılandırma dosyasına ihtiyacınız olacaktır. Bu dosyayı Sürekli Dağıtım (CD)
işlem hattınız içinde dinamik olarak oluşturmayı düşünün. Aşağıda kullanımınız
için bir referans örneği bulunmaktadır:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

Ardından uygulamayı başlatmak için `fly launch --local-only --no-deploy`
komutunu çalıştırabilirsiniz. Sonraki dağıtımlarda `fly launch --local-only`
çalıştırmak yerine `fly deploy --local-only` çalıştırmanız gerekecektir. Fly.io
özel Docker görüntülerini çekmeye izin vermez, bu yüzden `--local-only`
bayrağını kullanmamız gerekir.


## Prometheus ölçümleri {#prometheus-metrics}

Tuist, kendi barındırdığınız örneğinizi izlemenize yardımcı olmak için
Prometheus metriklerini `/metrics` adresinde sunar. Bu metrikler şunları içerir:

### Finch HTTP istemci ölçümleri {#finch-metrics}

Tuist, HTTP istemcisi olarak [Finch](https://github.com/sneako/finch) kullanır
ve HTTP istekleri hakkında ayrıntılı ölçümler sunar:

#### Talep ölçümleri
- `tuist_prom_ex_finch_request_count_total` - Finch isteklerinin toplam sayısı
  (sayaç)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP isteklerinin süresi
  (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - Kovalar: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch istek
  istisnalarının toplam sayısı (sayaç)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`,
    `reason`

#### Bağlantı havuzu kuyruk ölçümleri
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Bağlantı havuzu kuyruğunda
  beklemek için harcanan süre (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Kovalar: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Bağlantının kullanılmadan
  önce boşta geçirdiği süre (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Kovalar: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch kuyruğu
  istisnalarının toplam sayısı (sayaç)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Bağlantı ölçümleri
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Bağlantı kurmak için
  harcanan süre (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `error`
  - Kovalar: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - Toplam bağlantı denemesi sayısı
  (sayaç)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`

#### Ölçümleri gönder
- `tuist_prom_ex_finch_send_duration_milliseconds` - İstek gönderilirken
  harcanan süre (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Kovalar: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Bağlantının göndermeden
  önce boşta geçirdiği süre (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Kovalar: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

Tüm histogram ölçümleri, ayrıntılı analiz için `_bucket`, `_sum` ve `_count`
varyantlarını sağlar.

### Diğer metrikler

Finch metriklerine ek olarak, Tuist aşağıdakiler için metrikler sunar:
- BEAM sanal makine performansı
- Özel iş mantığı ölçümleri (depolama, hesaplar, projeler, vb.)
- Veritabanı performansı (Tuist tarafından barındırılan altyapı kullanıldığında)

## Operasyonlar {#operations}

Tuist, `/ops/` altında örneğinizi yönetmek için kullanabileceğiniz bir dizi
yardımcı program sağlar.

::: warning Authorization
<!-- -->
Yalnızca `TUIST_OPS_USER_HANDLES` ortam değişkeninde tanıtıcıları listelenen
kişiler `/ops/` uç noktalarına erişebilir.
<!-- -->
:::

- **Hatalar (`/ops/errors`):** Uygulamada meydana gelen beklenmedik hataları
  görüntüleyebilirsiniz. Bu, hata ayıklama ve neyin yanlış gittiğini anlamak
  için kullanışlıdır ve sorunlarla karşılaşıyorsanız bu bilgileri bizimle
  paylaşmanızı isteyebiliriz.
- **Gösterge Tablosu (`/ops/dashboard`):** Uygulamanın performansı ve sağlığı
  (örneğin bellek tüketimi, çalışan işlemler, istek sayısı) hakkında bilgi
  sağlayan bir gösterge tablosu görüntüleyebilirsiniz. Bu gösterge tablosu,
  kullandığınız donanımın yükü kaldırmaya yeterli olup olmadığını anlamak için
  oldukça yararlı olabilir.
