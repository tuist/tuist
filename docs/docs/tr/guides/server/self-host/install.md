---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# Kendi sunucunuzda kurulum {#self-host-installation}

Altyapıları üzerinde daha fazla kontrol sahibi olmak isteyen kuruluşlar için
Tuist sunucusunun kendi sunucunuzda barındırılan bir sürümünü sunuyoruz. Bu
sürüm, Tuist'i kendi altyapınızda barındırmanıza olanak tanıyarak verilerinizin
güvenli ve gizli kalmasını sağlar.

::: warning LICENSE REQUIRED
<!-- -->
Tuist'i kendi sunucunuzda barındırmak için yasal olarak geçerli bir ücretli
lisans gerekir. Tuist'in şirket içi sürümü yalnızca Enterprise planına sahip
kuruluşlar için mevcuttur. Bu sürümle ilgileniyorsanız, lütfen
[contact@tuist.dev](mailto:contact@tuist.dev) adresine başvurun.
<!-- -->
:::

## Yayınlama sıklığı {#release-cadence}

Yeni sürümler yayınlanabilir hale geldikçe Tuist'in yeni sürümlerini sürekli
olarak yayınlıyoruz. Öngörülebilir sürümleme ve uyumluluk sağlamak için
[semantik sürümleme](https://semver.org/) yöntemini takip ediyoruz.

Ana bileşen, Tuist sunucusunda yerinde kullanıcılarla koordinasyon gerektiren
önemli değişiklikleri işaretlemek için kullanılır. Bizim bunu kullanmamızı
beklememelisiniz ve ihtiyacımız olursa, geçişin sorunsuz olması için sizinle
birlikte çalışacağımızdan emin olabilirsiniz.

## Sürekli dağıtım {#continuous-deployment}

Tuist'in en son sürümünü her gün otomatik olarak dağıtan sürekli bir dağıtım
boru hattı kurmanızı şiddetle tavsiye ederiz. Bu, en son özelliklere,
iyileştirmelere ve güvenlik güncellemelerine her zaman erişiminizi sağlar.

İşte her gün yeni sürümleri kontrol eden ve dağıtan bir GitHub Actions iş akışı
örneği:

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

Bu bölüm, altyapınızda Tuist sunucusunu barındırmak için gerekli şartları
özetlemektedir.

### Uyumluluk matrisi {#compatibility-matrix}

Tuist sunucusu test edilmiştir ve aşağıdaki minimum sürümlerle uyumludur:

| Bileşen     | Minimum Sürüm | Notlar                                               |
| ----------- | ------------- | ---------------------------------------------------- |
| PostgreSQL  | 15            | TimescaleDB uzantısı ile                             |
| TimescaleDB | 2.16.1        | Gerekli PostgreSQL uzantısı (kullanımdan kaldırıldı) |
| ClickHouse  | 25            | Analitik için gereklidir                             |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB şu anda Tuist sunucusu için gerekli bir PostgreSQL uzantısıdır ve
zaman serisi veri depolama ve sorgulama için kullanılır. Ancak, **TimescaleDB
kullanımdan kaldırılmıştır** ve tüm zaman serisi işlevlerini ClickHouse'a
taşıdığımız için yakın gelecekte gerekli bir bağımlılık olarak kaldırılacaktır.
Şu anda, PostgreSQL örneğinizde TimescaleDB'nin kurulu ve etkin olduğundan emin
olun.
<!-- -->
:::

### Docker ile sanallaştırılmış görüntüleri çalıştırma {#running-dockervirtualized-images}

Sunucuyu [GitHub’un Container
Kayıtı](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
aracılığıyla [Docker](https://www.docker.com/) görüntüsü olarak dağıtıyoruz.

Bunu çalıştırmak için altyapınızın Docker görüntülerini çalıştırmayı
desteklemesi gerekir. Üretim ortamlarında yazılım dağıtımı ve çalıştırma için
standart konteyner haline geldiği için çoğu altyapı sağlayıcısının bunu
desteklediğini unutmayın.

### Postgres veritabanı {#postgres-database}

Docker görüntülerini çalıştırmanın yanı sıra, ilişkisel ve zaman serisi
verilerini depolamak için [TimescaleDB uzantısı](https://www.timescale.com/) ile
bir [Postgres veritabanı](https://www.postgresql.org/) gerekir. Çoğu altyapı
sağlayıcısı, hizmetlerine Postgres veritabanlarını dahil eder (ör.
[AWS](https://aws.amazon.com/rds/postgresql/) ve [Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

**TimescaleDB Uzantısı Gerekli:** Tuist, verimli zaman serisi veri depolama ve
sorgulama için TimescaleDB uzantısını gerektirir. Bu uzantı, komut olayları,
analitik ve diğer zamana dayalı özellikler için kullanılır. Tuist'i
çalıştırmadan önce PostgreSQL örneğinizde TimescaleDB'nin kurulu ve
etkinleştirilmiş olduğundan emin olun.

::: info MIGRATIONS
<!-- -->
Docker görüntüsünün giriş noktası, hizmeti başlatmadan önce bekleyen tüm şema
geçişleri otomatik olarak çalıştırır. TimescaleDB uzantısının eksik olması
nedeniyle geçişler başarısız olursa, önce veritabanınıza bu uzantıyı yüklemeniz
gerekir.
<!-- -->
:::

### ClickHouse veritabanı {#clickhouse-database}

Tuist, büyük miktarda analiz verisini depolamak ve sorgulamak için
[ClickHouse](https://clickhouse.com/) kullanır. ClickHouse, yapı bilgileri gibi
özellikler iç **'ın gerektirdiği** olup, TimescaleDB'yi aşamalı olarak
kaldırdıkça birincil zaman serisi veritabanı olacaktır. ClickHouse'u kendi
sunucunuzda barındırmayı veya barındırma hizmetini kullanmayı seçebilirsiniz.

::: info MIGRATIONS
<!-- -->
Docker görüntüsünün giriş noktası, hizmeti başlatmadan önce bekleyen tüm
ClickHouse şema geçişleri otomatik olarak çalıştırır.
<!-- -->
:::

### Depolama {#storage}

Ayrıca dosyaları (ör. çerçeve ve kütüphane ikili dosyaları) depolamak için bir
çözüme ihtiyacınız olacaktır. Şu anda S3 uyumlu tüm depolama alanlarını
destekliyoruz.

::: tip OPTIMIZED CACHING
<!-- -->
Amacınız öncelikle ikili dosyaları depolamak için kendi deponuzu oluşturmak ve
önbellek gecikmesini azaltmaksa, tüm sunucuyu kendi sunucunuzda barındırmanız
gerekmeyebilir. Önbellek düğümlerini kendi sunucunuzda barındırabilir ve bunları
barındırılan Tuist sunucusuna veya kendi sunucunuza bağlayabilirsiniz.

<LocalizedLink href="/guides/cache/self-host">önbellek kendi kendine barındırma
kılavuzuna</LocalizedLink>bakın.
<!-- -->
:::

## Konfigürasyon {#configuration}

Hizmetin yapılandırması, çalışma zamanında ortam değişkenleri aracılığıyla
yapılır. Bu değişkenlerin hassas doğası göz önüne alındığında, bunları
şifreleyip güvenli şifre yönetimi çözümlerinde saklamanızı öneririz. Tuist, bu
değişkenleri azami özenle ele alır ve günlüklerde asla görüntülenmemelerini
sağlar.

::: info LAUNCH CHECKS
<!-- -->
Gerekli değişkenler başlangıçta doğrulanır. Herhangi biri eksikse, başlatma
başarısız olur ve hata mesajında eksik değişkenler ayrıntılı olarak belirtilir.
<!-- -->
:::

### Lisans yapılandırması {#license-configuration}

Yerel kullanıcı olarak, ortam değişkeni olarak göstermeniz gereken bir lisans
anahtarı alacaksınız. Bu anahtar, lisansı doğrulamak ve hizmetin sözleşme
koşulları dahilinde çalıştığından emin olmak için kullanılır.

| Ortam değişkeni                    | Açıklama                                                                                                                                                                                                                                       | Gerekli | Varsayılan | Örnekler                                  |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ---------- | ----------------------------------------- |
| `TUIST_LICENSE`                    | Hizmet seviyesi sözleşmesini imzaladıktan sonra sağlanan lisans                                                                                                                                                                                | Evet*   |            | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **`TUIST_LICENSE`** için istisnai alternatif. Sunucunun harici hizmetlerle iletişim kuramadığı hava boşluklu ortamlarda çevrimdışı lisans doğrulaması için Base64 kodlu genel sertifika. Yalnızca `TUIST_LICENSE` kullanılamadığında kullanın. | Evet*   |            | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* `TUIST_LICENSE` veya `TUIST_LICENSE_CERTIFICATE_BASE64` adreslerinden biri
sağlanmalıdır, ancak ikisi birden sağlanmamalıdır. Standart dağıtımlar için
`TUIST_LICENSE` adresini kullanın.

::: warning EXPIRATION DATE
<!-- -->
Lisansların son kullanma tarihi vardır. Lisansın son kullanma tarihi 30 günden
az kaldıysa, kullanıcılar sunucuyla etkileşime giren Tuist komutlarını
kullanırken bir uyarı alırlar. Lisansınızı yenilemek istiyorsanız, lütfen
[contact@tuist.dev](mailto:contact@tuist.dev) adresine başvurun.
<!-- -->
:::

### Temel ortam yapılandırması {#base-environment-configuration}

| Ortam değişkeni                       | Açıklama                                                                                                                                                                                                                | Gerekli | Varsayılan                         | Örnekler                                                                       |                                                                                                                                    |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ---------------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | İnternetten örneğe erişmek için temel URL                                                                                                                                                                               | Evet    |                                    | https://tuist.dev                                                              |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | Bilgileri şifrelemek için kullanılacak anahtar (ör. çerezdeki oturumlar)                                                                                                                                                | Evet    |                                    |                                                                                | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pepper ile şifrelenmiş şifreler oluşturun                                                                                                                                                                               | Hayır   | `$TUIST_SECRET_KEY_BASE`           |                                                                                |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | Rastgele token oluşturmak için gizli anahtar                                                                                                                                                                            | Hayır   | `$TUIST_SECRET_KEY_BASE`           |                                                                                |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | Hassas verilerin AES-GCM şifrelemesi için 32 baytlık anahtar                                                                                                                                                            | Hayır   | `$TUIST_SECRET_KEY_BASE`           |                                                                                |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | `1` yazdığınızda, uygulama IPv6 adreslerini kullanacak şekilde yapılandırılır.                                                                                                                                          | Hayır   | `0`                                | `1`                                                                            |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | Uygulama için kullanılacak günlük seviyesi                                                                                                                                                                              | Hayır   | `bilgi`                            | [Günlük düzeyleri](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | GitHub uygulamanızın adının URL versiyonu                                                                                                                                                                               | Hayır   |                                    | `my-app`                                                                       |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub uygulamasının otomatik PR yorumları gönderme gibi ekstra işlevleri etkinleştirmek için kullandığı base64 kodlu özel anahtar                                                                                      | Hayır   | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                                |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | GitHub uygulamasının otomatik PR yorumları yayınlama gibi ekstra işlevleri etkinleştirmek için kullanılan özel anahtar. **Özel karakterlerle ilgili sorunları önlemek için base64 kodlu sürümü kullanmanızı öneririz.** | Hayır   | `-----BEGIN RSA...`                |                                                                                |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | İşlem URL'lerine erişimi olan kullanıcı adlarının virgülle ayrılmış listesi                                                                                                                                             | Hayır   |                                    | `user1,user2`                                                                  |                                                                                                                                    |
| `TUIST_WEB`                           | Web sunucusu uç noktasını etkinleştirin                                                                                                                                                                                 | Hayır   | `1`                                | `1` veya `0`                                                                   |                                                                                                                                    |

### Veritabanı yapılandırması {#database-configuration}

Veritabanı bağlantısını yapılandırmak için aşağıdaki ortam değişkenleri
kullanılır:

| Ortam değişkeni                      | Açıklama                                                                                                                                                                                                                                     | Gerekli | Varsayılan | Örnekler                                                               |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ---------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | Postgres veritabanına erişmek için kullanılan URL. URL'nin kimlik doğrulama bilgilerini içermesi gerektiğini unutmayın.                                                                                                                      | Evet    |            | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | ClickHouse veritabanına erişmek için kullanılan URL. URL'nin kimlik doğrulama bilgilerini içermesi gerektiğini unutmayın.                                                                                                                    | Hayır   |            | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | Doğru olduğunda, veritabanına bağlanmak için [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) kullanır.                                                                                                                         | Hayır   | `1`        | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | Bağlantı havuzunda açık tutulacak bağlantı sayısı                                                                                                                                                                                            | Hayır   | `10`       | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | Havuzdan kontrol edilen tüm bağlantıların kuyruk aralığından daha uzun sürüp sürmediğini kontrol etmek için aralık (milisaniye cinsinden) [(Daha fazla bilgi)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | Hayır   | `300`      | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | Havuzun yeni bağlantıları kesmeye başlaması gerekip gerekmediğini belirlemek için kuyrukta kullandığı eşik süre (milisaniye cinsinden) [(Daha fazla bilgi)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)    | Hayır   | `1000`     | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse tampon boşaltmaları arasındaki milisaniye cinsinden zaman aralığı                                                                                                                                                                 | Hayır   | `5000`     | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | Zorla boşaltma öncesinde ClickHouse tamponunun maksimum boyutu (bayt cinsinden)                                                                                                                                                              | Hayır   | `1000000`  | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | Çalıştırılacak ClickHouse tampon işlemlerinin sayısı                                                                                                                                                                                         | Hayır   | `5`        | `5`                                                                    |

### Kimlik doğrulama ortamı yapılandırması {#authentication-environment-configuration}

[kimlik sağlayıcılar (IdP)](https://en.wikipedia.org/wiki/Identity_provider)
aracılığıyla kimlik doğrulamayı kolaylaştırıyoruz. Bunu kullanmak için, seçilen
sağlayıcı için gerekli tüm ortam değişkenlerinin sunucunun ortamında mevcut
olduğundan emin olun. **Eksik değişkenler** Tuist'in o sağlayıcıyı atlamasına
neden olur.

#### GitHub {#github}

[GitHub
Uygulaması](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)
kullanarak kimlik doğrulaması yapmanızı öneririz, ancak [OAuth
Uygulaması](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)
da kullanabilirsiniz. GitHub tarafından belirtilen tüm gerekli ortam
değişkenlerini sunucu ortamına eklediğinizden emin olun. Eksik değişkenler,
Tuist'in GitHub kimlik doğrulamasını gözden kaçırmasına neden olur. GitHub
uygulamasını doğru şekilde kurmak için:
- GitHub uygulamasının genel ayarlarında:
    - `İstemci Kimliğini` kopyalayın ve `TUIST_GITHUB_APP_CLIENT_ID olarak
      ayarlayın.`
    - Yeni bir `istemci gizli anahtarı oluşturun ve kopyalayın` ve bunu
      `TUIST_GITHUB_APP_CLIENT_SECRET olarak ayarlayın.`
    - `'ın Geri Arama URL'sini` olarak
      `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` olarak
      ayarlayın. , sunucunuzun IP adresi de olabilir.
- Aşağıdaki izinler gereklidir:
  - Depolar:
    - Çekme istekleri: Okuma ve yazma
  - Hesaplar:
    - E-posta adresleri: Salt okunur

`İzinler ve olaylar`'s `Hesap izinleri` bölümünde, `E-posta adresleri` iznini
`Salt okunur` olarak ayarlayın.

Ardından, Tuist sunucusunun çalıştığı ortamda aşağıdaki ortam değişkenlerini
açığa çıkarmanız gerekir:

| Ortam değişkeni                  | Açıklama                             | Gerekli | Varsayılan | Örnekler                                   |
| -------------------------------- | ------------------------------------ | ------- | ---------- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub uygulamasının müşteri kimliği | Evet    |            | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | Uygulamanın müşteri gizli anahtarı   | Evet    |            | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

[OAuth 2](https://developers.google.com/identity/protocols/oauth2) kullanarak
Google ile kimlik doğrulama ayarlayabilirsiniz. Bunun için OAuth istemci kimliği
türünde yeni bir kimlik bilgisi oluşturmanız gerekir. Kimlik bilgilerini
oluştururken, uygulama türü olarak "Web Uygulaması"nı seçin, `Tuist` adını verin
ve yeniden yönlendirme URI'sini `{base_url}/users/auth/google/callback` olarak
ayarlayın. Burada `base_url`, barındırılan hizmetinizin çalıştığı URL'dir.
Uygulamayı oluşturduktan sonra, istemci kimliğini ve gizli anahtarı kopyalayın
ve bunları sırasıyla `GOOGLE_CLIENT_ID` ve `GOOGLE_CLIENT_SECRET` ortam
değişkenleri olarak ayarlayın.

::: info CONSENT SCREEN SCOPES
<!-- -->
Bir onay ekranı oluşturmanız gerekebilir. Bunu yaparken, `userinfo.email` ve
`openid` kapsamlarını eklediğinizden ve uygulamayı dahili olarak
işaretlediğinizden emin olun.
<!-- -->
:::

#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/) protokolü aracılığıyla Okta ile kimlik
doğrulamayı etkinleştirebilirsiniz.
<LocalizedLink href="/guides/integrations/sso#okta">bu
talimatları</LocalizedLink> izleyerek Okta'da [bir uygulama
oluşturmanız](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)
gerekir.

Okta uygulamasının kurulumunda istemci kimliğini ve gizli anahtarı aldıktan
sonra aşağıdaki ortam değişkenlerini ayarlamanız gerekecektir:

| Ortam değişkeni              | Açıklama                                                                                                        | Gerekli | Varsayılan | Örnekler |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------- | ------- | ---------- | -------- |
| `TUIST_OKTA_1_CLIENT_ID`     | Okta'da kimlik doğrulaması için kullanılan müşteri kimliği. Bu numara, kuruluşunuzun kimlik numarası olmalıdır. | Evet    |            |          |
| `TUIST_OKTA_1_CLIENT_SECRET` | Okta'da kimlik doğrulama için kullanılan müşteri gizli anahtarı                                                 | Evet    |            |          |

`1` numarası, kuruluşunuzun kimlik numarasıyla değiştirilmelidir. Bu numara
genellikle 1'dir, ancak veritabanınızı kontrol edin.

### Depolama ortamı yapılandırması {#storage-environment-configuration}

Tuist, API aracılığıyla yüklenen eserleri depolamak için depolama alanına
ihtiyaç duyar. Tuist'in etkili bir şekilde çalışması iç **'da desteklenen
depolama çözümlerinden birini yapılandırmak çok önemlidir.**

#### S3 uyumlu depolama alanları {#s3compliant-storages}

Artefaktları depolamak için S3 uyumlu herhangi bir depolama sağlayıcısını
kullanabilirsiniz. Depolama sağlayıcısıyla entegrasyonu doğrulamak ve
yapılandırmak için aşağıdaki ortam değişkenleri gereklidir:

| Ortam değişkeni                                           | Açıklama                                                                                                                                                                             | Gerekli | Varsayılan                       | Örnekler                                                        |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------- | -------------------------------- | --------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` veya `AWS_ACCESS_KEY_ID`         | Depolama sağlayıcısına karşı kimlik doğrulaması yapmak için erişim anahtarı kimliği                                                                                                  | Evet    |                                  | `AKIAIOSFOD`                                                    |
| `TUIST_S3_SECRET_ACCESS_KEY` veya `AWS_SECRET_ACCESS_KEY` | Depolama sağlayıcısına karşı kimlik doğrulama için gizli erişim anahtarı                                                                                                             | Evet    |                                  | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                      |
| `TUIST_S3_REGION` veya `AWS_REGION`                       | Kovanın bulunduğu bölge                                                                                                                                                              | Hayır   | `otomatik`                       | `us-west-2`                                                     |
| `TUIST_S3_ENDPOINT` veya `AWS_ENDPOINT`                   | Depolama sağlayıcısının uç noktası                                                                                                                                                   | Evet    |                                  | `https://s3.us-west-2.amazonaws.com`                            |
| `TUIST_S3_BUCKET_NAME`                                    | Artefaktların depolanacağı kovanın adı                                                                                                                                               | Evet    |                                  | `tuist-artifacts`                                               |
| `TUIST_S3_CA_CERT_PEM`                                    | S3 HTTPS bağlantılarını doğrulamak için PEM kodlu CA sertifikası. Kendinden imzalı sertifikalar veya dahili Sertifika Yetkilileri bulunan hava boşluklu ortamlar için kullanışlıdır. | Hayır   | Sistem CA paketi                 | `-----SERTİFİKA BAŞLANGICI-----\n...\n-----SERTİFİKA SONU-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                                | Depolama sağlayıcısına bağlantı kurmak için zaman aşımı (milisaniye cinsinden)                                                                                                       | Hayır   | `3000`                           | `3000`                                                          |
| `TUIST_S3_RECEIVE_TIMEOUT`                                | Depolama sağlayıcısından veri almak için zaman aşımı (milisaniye cinsinden)                                                                                                          | Hayır   | `5000`                           | `5000`                                                          |
| `TUIST_S3_POOL_TIMEOUT`                                   | Depolama sağlayıcısına bağlantı havuzunun zaman aşımı süresi (milisaniye cinsinden). Zaman aşımı süresi olmaması için `infinity` kullanın.                                           | Hayır   | `5000`                           | `5000`                                                          |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                             | Havuzdaki bağlantılar için maksimum bekleme süresi (milisaniye cinsinden). Bağlantıları süresiz olarak canlı tutmak için `infinity` kullanın.                                        | Hayır   | `sonsuzluk`                      | `60000`                                                         |
| `TUIST_S3_POOL_SIZE`                                      | Havuz başına maksimum bağlantı sayısı                                                                                                                                                | Hayır   | `500`                            | `500`                                                           |
| `TUIST_S3_POOL_COUNT`                                     | Kullanılacak bağlantı havuzlarının sayısı                                                                                                                                            | Hayır   | Sistem zamanlayıcılarının sayısı | `4`                                                             |
| `TUIST_S3_PROTOCOL`                                       | Depolama sağlayıcısına bağlanırken kullanılacak protokol (`http1` veya `http2`)                                                                                                      | Hayır   | `http1`                          | `http1`                                                         |
| `TUIST_S3_VIRTUAL_HOST`                                   | URL'nin alt etki alanı (sanal ana bilgisayar) olarak kova adıyla oluşturulması gerekip gerekmediği                                                                                   | Hayır   | `false`                          | `1`                                                             |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
Depolama sağlayıcınız AWS ise ve web kimlik jetonu kullanarak kimlik doğrulaması
yapmak istiyorsanız, `TUIST_S3_AUTHENTICATION_METHOD` `
aws_web_identity_token_from_env_vars` ortam değişkenini ayarlayabilirsiniz.
Tuist, geleneksel AWS ortam değişkenlerini kullanarak bu yöntemi kullanacaktır.
<!-- -->
:::

#### Google Cloud Storage {#google-cloud-storage}
Google Cloud Storage için, [bu
belgeleri](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)
izleyerek `AWS_ACCESS_KEY_ID` ve `AWS_SECRET_ACCESS_KEY` çiftini alın.
`AWS_ENDPOINT` ` https://storage.googleapis.com` olarak ayarlanmalıdır. Diğer
ortam değişkenleri, diğer S3 uyumlu depolama alanlarıyla aynıdır.

### E-posta yapılandırması {#email-configuration}

Tuist, kullanıcı kimlik doğrulama ve işlem bildirimleri (ör. şifre sıfırlama,
hesap bildirimleri) için e-posta işlevselliğine ihtiyaç duyar. Şu anda,
**yalnızca Mailgun** e-posta sağlayıcısı olarak desteklenmektedir.

| Ortam değişkeni                  | Açıklama                                                                                                                                                              | Gerekli | Varsayılan                                                             | Örnekler                  |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ---------------------------------------------------------------------- | ------------------------- |
| `TUIST_MAILGUN_API_KEY`          | Mailgun ile kimlik doğrulama için API anahtarı                                                                                                                        | Evet*   |                                                                        | `key-1234567890abcdef`    |
| `TUIST_MAILING_DOMAIN`           | E-postaların gönderileceği alan adı                                                                                                                                   | Evet*   |                                                                        | `mg.tuist.io`             |
| `TUIST_MAILING_FROM_ADDRESS`     | "Kimden" alanında görünecek e-posta adresi                                                                                                                            | Evet*   |                                                                        | `noreply@tuist.io`        |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | Kullanıcı yanıtları için isteğe bağlı yanıt adresi                                                                                                                    | Hayır   |                                                                        | `support@tuist.dev`       |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | Yeni kullanıcı kayıtları için e-posta onayını atlayın. Etkinleştirildiğinde, kullanıcılar otomatik olarak onaylanır ve kayıt olduktan hemen sonra oturum açabilirler. | Hayır   | ` `e-posta yapılandırılmamışsa true`, e-posta yapılandırılmışsa false` | `true`, `false`, `1`, `0` |

\* E-posta yapılandırma değişkenleri yalnızca e-posta göndermek istediğinizde
gereklidir. Yapılandırılmamışsa, e-posta onayı otomatik olarak atlanır.

::: info SMTP SUPPORT
<!-- -->
Genel SMTP desteği şu anda mevcut değildir. Yerel dağıtımınız için SMTP
desteğine ihtiyacınız varsa, gereksinimlerinizi görüşmek üzere
[contact@tuist.dev](mailto:contact@tuist.dev) adresine başvurun.
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
İnternet erişimi veya e-posta sağlayıcı yapılandırması olmayan şirket içi
kurulumlarda, e-posta onayı varsayılan olarak otomatik olarak atlanır.
Kullanıcılar kayıt olduktan hemen sonra oturum açabilirler. E-posta
yapılandırılmış olmasına rağmen onayı atlamak istiyorsanız,
`TUIST_SKIP_EMAIL_CONFIRMATION=true` ayarını yapın. E-posta yapılandırıldığında
e-posta onayı gerektirmesini istiyorsanız, `TUIST_SKIP_EMAIL_CONFIRMATION=false`
ayarını yapın.
<!-- -->
:::

### Git platformu yapılandırması {#git-platform-configuration}

Tuist, <LocalizedLink href="/guides/server/authentication">Git platformlarıyla
entegre olabilir</LocalizedLink> ve pull isteklerinize otomatik olarak yorum
gönderme gibi ek özellikler sunabilir.

#### GitHub {#platform-github}

Bir GitHub uygulaması oluşturmanız gerekecektir. OAuth GitHub uygulaması
oluşturmadıysanız, kimlik doğrulama için oluşturduğunuz uygulamayı yeniden
kullanabilirsiniz. `İzinler ve olaylar`'s `Depo izinleri` bölümünde, `Çekme
istekleri` iznini `Okuma ve yazma` olarak ayarlamanız gerekecektir.

`TUIST_GITHUB_APP_CLIENT_ID` ve `TUIST_GITHUB_APP_CLIENT_SECRET` adreslerinin
yanı sıra, aşağıdaki ortam değişkenlerine de ihtiyacınız olacaktır:

| Ortam değişkeni                | Açıklama                           | Gerekli | Varsayılan | Örnekler                             |
| ------------------------------ | ---------------------------------- | ------- | ---------- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub uygulamasının özel anahtarı | Evet    |            | `-----BEGIN RSA PRIVATE KEY-----...` |

## Yerel Olarak Test Etme {#testing-locally}

Altyapınıza dağıtmadan önce yerel makinenizde Tuist sunucusunu test etmek için
gerekli tüm bağımlılıkları içeren kapsamlı bir Docker Compose yapılandırması
sağlıyoruz:

- TimescaleDB 2.16 uzantılı PostgreSQL 15 (kullanımdan kaldırıldı)
- Analitik için ClickHouse 25
- Koordinasyon için ClickHouse Keeper
- S3 uyumlu depolama için MinIO
- Dağıtımlar arasında kalıcı KV depolama için Redis (isteğe bağlı)
- Veritabanı yönetimi için pgweb

::: danger LICENSE REQUIRED
<!-- -->
`TUIST_LICENSE` geçerli bir ortam değişkeni, yerel geliştirme örnekleri de dahil
olmak üzere Tuist sunucusunu çalıştırmak için yasal olarak gereklidir. Lisansa
ihtiyacınız varsa, lütfen [contact@tuist.dev](mailto:contact@tuist.dev) ile
iletişime geçin.
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

4. http://localhost:8080 adresinden sunucuya erişin.

**Hizmet Uç Noktaları:**
- Tuist Sunucusu: http://localhost:8080
- MinIO Konsolu: http://localhost:9003 (kimlik bilgileri: `tuist` /
  `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrikleri: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**Yaygın Komutlar:**

Hizmet durumunu kontrol edin:
```bash
docker compose ps
# or: podman compose ps
```

Günlükleri görüntüleyin:
```bash
docker compose logs -f tuist
```

Hizmetleri durdurun:
```bash
docker compose down
```

Her şeyi sıfırla (tüm verileri siler):
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

Veya belirli bir sürümü çekin:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker görüntüsünü dağıtma {#deploying-the-docker-image}

Docker görüntüsünün dağıtım süreci, seçtiğiniz bulut sağlayıcısı ve
kuruluşunuzun sürekli dağıtım yaklaşımına göre farklılık gösterecektir.
[Kubernetes](https://kubernetes.io/) gibi çoğu bulut çözümü ve aracı, temel
birimler olarak Docker görüntülerini kullandığından, bu bölümdeki örnekler
mevcut kurulumunuzla uyumlu olacaktır.

::: warning
<!-- -->
Dağıtım ardışık düzeninizin sunucunun çalışır durumda olduğunu doğrulaması
gerekiyorsa, `GET` HTTP isteğini `/ready` adresine gönderebilir ve yanıtta `200`
durum kodunu onaylayabilirsiniz.
<!-- -->
:::

#### Fly {#fly}

Uygulamayı [Fly](https://fly.io/) üzerinde dağıtmak için, `fly.toml`
yapılandırma dosyasına ihtiyacınız olacaktır. Bu dosyayı Sürekli Dağıtım (CD)
ardışık düzeninde dinamik olarak oluşturmayı düşünün. Aşağıda,
kullanabileceğiniz bir referans örneği bulunmaktadır:

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

Ardından, uygulamayı başlatmak için `fly launch --local-only --no-deploy`
komutunu çalıştırabilirsiniz. Sonraki dağıtımlarda, `fly launch --local-only`
komutunu çalıştırmak yerine, `fly deploy --local-only` komutunu çalıştırmanız
gerekir. Fly.io, özel Docker görüntülerini çekmeye izin vermez, bu nedenle
`--local-only` bayrağını kullanmamız gerekir.


## Prometheus metrikleri {#prometheus-metrics}

Tuist, kendi barındırdığınız örneği izlemenize yardımcı olmak için `/metrics`
adresinde Prometheus metriklerini gösterir. Bu metrikler şunları içerir:

### Finch HTTP istemci metrikleri {#finch-metrics}

Tuist, HTTP istemcisi olarak [Finch](https://github.com/sneako/finch) kullanır
ve HTTP istekleri hakkında ayrıntılı ölçümler sunar:

#### Metrikleri isteyin
- `tuist_prom_ex_finch_request_count_total` - Toplam Finch isteği sayısı (sayaç)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP isteklerinin süresi
  (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - Kovalar: 10 ms, 50 ms, 100 ms, 250 ms, 500 ms, 1 saniye, 2,5 saniye, 5
    saniye, 10 saniye
- `tuist_prom_ex_finch_request_exception_count_total` - Toplam Finch istek
  istisnası sayısı (sayaç)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`,
    `reason`

#### Bağlantı havuzu kuyruğu ölçümleri
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Bağlantı havuzu kuyruğunda
  bekleme süresi (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Kovalar: 1 ms, 5 ms, 10 ms, 25 ms, 50 ms, 100 ms, 250 ms, 500 ms, 1 saniye
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Kullanılmadan önce
  bağlantının boşta kaldığı süre (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Kovalar: 10 ms, 50 ms, 100 ms, 250 ms, 500 ms, 1 saniye, 5 saniye, 10 saniye
- `tuist_prom_ex_finch_queue_exception_count_total` - Toplam Finch kuyruk
  istisnası sayısı (sayaç)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Bağlantı metrikleri
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Bağlantı kurulması için
  harcanan süre (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `error`
  - Kovalar: 10 ms, 50 ms, 100 ms, 250 ms, 500 ms, 1 saniye, 2,5 saniye, 5
    saniye
- `tuist_prom_ex_finch_connect_count_total` - Toplam bağlantı deneme sayısı
  (sayaç)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`

#### Metrikleri gönder
- `tuist_prom_ex_finch_send_duration_milliseconds` - İsteğin gönderilmesi için
  harcanan süre (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Kovalar: 1 ms, 5 ms, 10 ms, 25 ms, 50 ms, 100 ms, 250 ms, 500 ms, 1 saniye
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Göndermeden önce
  bağlantının boşta kaldığı süreyi ölçün (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Kovalar: 1 ms, 5 ms, 10 ms, 25 ms, 50 ms, 100 ms, 250 ms, 500 ms

Tüm histogram metrikleri, ayrıntılı analiz iç `_bucket`, `_sum` ve `_count`
varyantları sunar.

### Diğer ölçütler

Finch metriklerine ek olarak, Tuist aşağıdakiler için metrikler sunar:
- BEAM sanal makine performansı
- Özel iş mantığı ölçütleri (depolama, hesaplar, projeler vb.)
- Veritabanı performansı (Tuist tarafından barındırılan altyapı kullanıldığında)

## İşlemler {#operations}

Tuist, `/ops/` adresinde, örneğinizin yönetiminde kullanabileceğiniz bir dizi
yardımcı program sunmaktadır.

::: warning Authorization
<!-- -->
Yalnızca `TUIST_OPS_USER_HANDLES` ortam değişkeninde listelenen kullanıcı
adlarına sahip kişiler `/ops/` uç noktalarına erişebilir.
<!-- -->
:::

- **Hatalar (`/ops/errors`):** Uygulamada meydana gelen beklenmedik hataları
  görüntüleyebilirsiniz. Bu, hata ayıklama ve neyin yanlış gittiğini anlamak
  için yararlıdır. Sorunlarla karşılaşırsanız, bu bilgileri bizimle paylaşmanızı
  isteyebiliriz.
- **Kontrol paneli (`/ops/dashboard`):** Uygulamanın performansı ve durumu (ör.
  bellek tüketimi, çalışan işlemler, istek sayısı) hakkında bilgi sağlayan bir
  kontrol panelini görüntüleyebilirsiniz. Bu kontrol paneli, kullandığınız
  donanımın yükü işlemek için yeterli olup olmadığını anlamak için oldukça
  yararlı olabilir.
