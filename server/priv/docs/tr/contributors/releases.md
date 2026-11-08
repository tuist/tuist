---
{
  "title": "Sürümler",
  "titleTemplate": ":title | Katkıda Bulunanlar | Tuist",
  "description": "Tuist'in sürekli sürüm sürecinin nasıl çalıştığını öğrenin"
}
---
# Sürümler

Tuist, değişiklikler ana dala birleştirildikçe yeni sürümleri otomatik olarak yayımlar. CLI, sunucu ve Kura önbellek sunucusu, önerilen kurulumun kararlı ve yavaş ilerlemesini sağlamak için sürüm kanalları (canary, release candidate, stable) üzerinden dağıtılır; bir release candidate oluşturmak ve onu stable’a yükseltmek kasıtlı, haftalık adımlardır. Uygulama sürekli olarak yayımlanır (iOS uygulaması yalnızca TestFlight’a sürekli olarak dağıtılır, daha fazla bilgi için [buraya](#app-store-release) bakın).

## Genel Bakış

Şu ana bileşenleri yayımlıyoruz:
- **Tuist CLI** - Komut satırı aracı, canary, release candidate ve stable [kanalları](#release-channels) üzerinden dağıtılır
- **Tuist Server** - Arka uç hizmetleri, CLI ile aynı kanal modeli üzerinden dağıtılır
- **Kura** - Önbellek sunucusu, CLI ile aynı kanal modeli üzerinden dağıtılır
- **Tuist App** - macOS ve iOS uygulamaları, sürekli olarak yayımlanır (iOS uygulaması yalnızca TestFlight’a sürekli olarak dağıtılır, daha fazla bilgi için [buraya](#app-store-release) bakın)

`main` dalına yapılan her push, CLI, sunucu ve Kura için bir canary ön sürümü yayımlar. Bu bileşenlerin her biri için stable sürüm, yalnızca bir bakıcı yeterince test edilmiş bir release candidate’i stable’a yükselttiğinde kesilir ve haftalık program üç treni de senkronize şekilde tetikler (bkz. [Sürüm kanalları](#release-channels)). Uygulama, `main` dalına yapılan her push’ta stable sürüm yayımlar.

## Nasıl çalışır

### 1. Commit kuralları

Commit mesajlarımızı yapılandırmak için [Conventional Commits](https://www.conventionalcommits.org/) kullanıyoruz. Bu, araçlarımızın değişikliklerin doğasını anlamasına, sürüm artışlarını belirlemesine ve uygun değişiklik günlükleri oluşturmasına olanak tanır.

Format: `type(scope): description`

#### Commit türleri ve etkileri

| Tür | Açıklama | Sürüm Etkisi | Örnek |
|------|-------------|----------------|---------|
| `feat` | Yeni özellik veya yetenek | Minör sürüm artışı (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | Hata düzeltmesi | Patch sürüm artışı (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | Belgeleme değişiklikleri | Sürüm yok | `docs: update installation guide` |
| `style` | Kod stili değişiklikleri | Sürüm yok | `style: format code with swiftformat` |
| `refactor` | Kod yeniden düzenleme | Sürüm yok | `refactor(server): simplify auth logic` |
| `perf` | Performans iyileştirmeleri | Patch sürüm artışı | `perf(cli): optimize dependency resolution` |
| `test` | Test eklemeleri/değişiklikleri | Sürüm yok | `test: add unit tests for cache` |
| `chore` | Bakım görevleri | Sürüm yok | `chore: update dependencies` |
| `ci` | CI/CD değişiklikleri | Sürüm yok | `ci: add workflow for releases` |

CLI için bu artışlar canary sürümünü ve değişiklik günlüğü gruplamasını belirler. Stable CLI sürümleri elle kesilen minör serilerdir (`X.Y.0`) ve stable patch’ler (`X.Y.Z`) yalnızca backport’lardan gelir; bu nedenle bir `feat` veya `fix` aşağıdaki kanal akışı aracılığıyla CLI kullanıcılarına ulaşır, anında bir stable sürüm olarak değil.

#### Breaking changes

Breaking changes, major sürüm artışını (X.0.0) tetikler ve commit gövdesinde belirtilmelidir:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Değişiklik algılama

Her bileşen, şunları yapmak için [git cliff](https://git-cliff.org/) kullanır:
- Son sürümden bu yana yapılan commit’leri analiz eder
- Commit’leri kapsamına göre filtreler (cli, app, server)
- Yayınlanabilir değişiklik olup olmadığını belirler
- Değişiklik günlüklerini otomatik olarak oluşturur

### 3. Sürüm hattı

Yayınlanabilir değişiklikler algılandığında:

1. **Sürüm hesaplama**: Hat, bir sonraki sürüm numarasını belirler
2. **Değişiklik günlüğü oluşturma**: git cliff, commit mesajlarından bir değişiklik günlüğü oluşturur
3. **Derleme süreci**: Bileşen derlenir ve test edilir
4. **Yapıt oluşturma**: CLI paketleri, checksum’lar ve `tuist --experimental-dump-help` komutundan üretilen `tuist.spec.json` CLI spesifikasyonu gibi sürüme özel varlıklar üretilir
5. **Sürüm oluşturma**: Yapıtlarla birlikte bir GitHub sürümü oluşturulur
6. **Dağıtım**: Güncellemeler paket yöneticilerine itilir (örneğin, CLI için Homebrew)

Uygulama için bu, her merge işleminde bir stable sürüm üretir. CLI, sunucu ve Kura için bu aynı otomatik hat yalnızca bir **canary** ön sürümü üretir; release candidate’ler ve stable sürümler haftalık sürüm treninde kesilir (bkz. [Sürüm kanalları](#release-channels)).

### 4. Kapsam filtreleme

Her bileşen yalnızca ilgili değişikliklere sahip olduğunda sürüm yayımlar:

- **CLI**: `(cli)` kapsamlı veya kapsam içermeyen commit’ler
- **App**: `(app)` kapsamlı commit’ler
- **Server**: `(server)` kapsamlı commit’ler

## Sürüm kanalları

CLI, sunucu ve Kura, `main` dalına yapılan her push’ta stable sürüme yükseltilmez. Her biri üç kanal üzerinden dağıtılır; böylece önerilen kurulum stable ve yavaş değişirken, erken benimseyenler commit başına derlemeleri korur. Kullanıcıya yönelik belgeler <.localized_link href="/cli/release/channels">CLI sürüm kanalları</.localized_link> ve <.localized_link href="/guides/server/self-host/release/channels">Sunucu sürüm kanalları</.localized_link> adreslerinde bulunur; bu bölüm bakıcı çalışma rehberidir.

Her bileşen aynı üç kanalı kullanır:

| Kanal | Sürüm | Kesilme yöntemi |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | Otomatik olarak, `main` dalına bileşeni etkileyen her push’ta (`<component>-release.yml`; Kura için, `kura/` değiştiğinde `server-production-deployment.yml` tarafından çağrılır) |
| Release candidate | `X.Y.0-rc.N` | Her Pazartesi veya manuel olarak, bir `releases/<component>-<major>.<minor>.x` dalında (`<component>-rc.yml`) |
| Stable | `X.Y.Z` | Her Pazartesi veya manuel olarak, yeterince test edilmiş bir RC’yi yükselterek (`<component>-promote.yml`); patch’ler `<component>-backport.yml` aracılığıyla |

Canary ve RC derlemeleri GitHub ön sürümleri olarak yayımlanır (asla "Latest" olarak işaretlenmez, GHCR üzerinde `:latest` asla hareket ettirilmez, CLI için Homebrew’e asla itilmez), bu nedenle paket yöneticileri ve imaj çözücüleri bunları yalnızca açıkça tercih edildiğinde alır. Canary her zaman yayınlanmamış bir sonraki minör sürümü hedefler: bir RC serisi kesildiğinde, `main` üzerindeki canary bir sonraki minör sürüme geçer.

Barındırılan Tuist, stable trenini beklemez: sunucu commit başına dağıtılır ve barındırılan canary ile production en yeni Kura canary’sini çalıştırır. Dağıtım zinciri, onu dağıtmadan önce o canary’yi kendisi yayımlar, bu nedenle `kura-release.yml` kendi tetikleyicisine sahip değildir. Yalnızca Kura sürüm araçlarına yapılan değişiklikler (`mise/tasks/kura/**`, `kura-*.yml` iş akışları) bir canary kesmez.

Sürüm numaralarını asla elle seçmezsiniz. Her kanalın bir sonraki sürümü, aşağıdaki iş akışlarının çağırdığı `mise/tasks/<component>/release/channel-version.sh` tarafından mevcut git etiketlerinden türetilir.

Sürüm dalları bileşen başına ad alanına ayrılmıştır (CLI için `releases/server-X.Y.x`, `releases/kura-X.Y.x`, `releases/X.Y.x`), böylece üç bileşenin serileri aynı minör sürümde asla çakışmaz.

### Haftalık program

Her Pazartesi saat 06:00 UTC’de, üç bileşenin yükseltme işleri senkronize şekilde çalışır: **CLI’yi Stable’a Yükselt**, **Sunucuyu Stable’a Yükselt** ve **Kura’yı Stable’a Yükselt**. Her biri, henüz stable olmayan en yeni RC serisini yükseltir; bu genellikle önceki Pazartesi kesilen seridir. Böyle bir seri yoksa, bu iş hiçbir şey yayımlamaz.

Bir yükseltme tamamlandığında, sonuç ne olursa olsun, eşleşen **Release Candidate** iş akışı (`cli-rc.yml`, `server-rc.yml`, `kura-rc.yml`) `workflow_run` aracılığıyla tetiklenir ve `main` dalından bir sonraki seriyi keser.

Planlanan çalıştırmalardan herhangi biri başarısız olursa veya iptal edilirse, Slack’e bir mesaj gönderilir. Sürüm dalında en son RC’sinden sonra commit’ler varsa yükseltme başarısız olur. Bu seriyi yayınlamak için üzerinde yeni bir RC kesin ve manuel olarak yükseltin. Aksi takdirde, bir sonraki Pazartesi daha yeni seriyi yükseltir.

### Release candidate kesme

Haftalık programın dışında yeni bir seri kesmek için (aşağıda bileşenin iş akışı adını yerine koyun):

1. `branch` girdisini boş bırakarak **\<Component\> Release Candidate** iş akışını (örneğin `server-rc.yml`) çalıştırın.
2. `X.Y.0-rc.1` yayımlar ve bu başarılı olduktan sonra, derlenen commit’te korumalı `releases/<component>-X.Y.x` dalını oluşturur.

Kritik bir düzeltmeyi veya regresyonu bekleme aşamasındaki bir seriye çekmek için, bunu bir PR aracılığıyla sürüm dalına cherry-pick ile ekleyin (backport’larla aynı akış; CI asla cherry-pick yapmaz), ardından RC’yi yineleyin:

1. `releases/<component>-X.Y.x` dalından dallanın, düzeltmeyi cherry-pick ile ekleyin, sürüm dalına geri bir PR açın, varsa çakışmaları çözün ve birleştirin.
2. `branch=releases/<component>-X.Y.x` ile **Release Candidate** iş akışını tekrar çalıştırın. Dal HEAD’inden `X.Y.0-rc.(N+1)` yayımlar.

Bekleme aşamasındaki bir seri özellik dondurulmuştur: yalnızca kritik düzeltmeler ve regresyonlar üzerine eklenir.

### Stable’a yükseltme

RC’si temiz bir şekilde beklemişken, haftalık programın dışında bir seriyi yükseltmek için:

1. `branch=releases/<component>-X.Y.x` ile **\<Component\> Promote to Stable** iş akışını (örneğin `server-promote.yml`) çalıştırın.
2. GHCR `:latest` etiketini ve GitHub “Latest” işaretçisini taşıyarak, `make_latest=true` ile semver etiketli imajı yayımlar. CLI ayrıca Homebrew formülünü günceller.

Dal HEAD’i tam olarak en son RC’nin işaret ettiği commit değilse yükseltme çalışmayı reddeder. Bu nedenle, son RC’den sonra seriye herhangi bir düzeltme birleştirildiyse, stable olarak yayımlanabilmesi için önce yeni bir RC kesmeniz ve onun beklemesine izin vermeniz gerekir.

### Düzeltmeleri stable bir seriye backport etme

Bir seri stable olduktan sonra, yalnızca CLI için kullanılan **Backport Release** iş akışıyla (`cli-backport.yml`) yamaları yayımlayın: düzeltmeyi bir PR aracılığıyla `releases/X.Y.x` üzerine cherry-pick ile ekleyin, ardından `X.Y.(Z+1)` kesmek için iş akışını o dalda çalıştırın. Backport’lar asla “Latest” işaretçisini veya Homebrew formülünü taşımaz. Aynı anda iki seri korunur: mevcut seri regresyonları ve güvenlik düzeltmelerini alır, önceki seri yalnızca kritik ve güvenlik düzeltmelerini alır. Diğer hata düzeltmeleri backport edilmez ve bir sonraki minör sürümle yayımlanır.

Sunucu ve Kura için **Server Backport Release** (`server-backport.yml`) veya **Kura Backport Release** (`kura-backport.yml`) kullanın. Yükseltme yalnızca bir RC’nin `X.Y.0` sürümünü yayımlar; zaten stable olan bir seriyi yamalayamaz.

1. Seçilen `X.Y` serisindeki en son yayımlanmış stable bileşen etiketinden başlayın ve mevcut `releases/server-X.Y.x` veya `releases/kura-X.Y.x` dalına cerrahi bir düzeltme PR’si açın. Daha yeni bir minör veya major sürüm, bakımı yapılan bir serinin yamalanmasını engellemez. İlgisiz main değişikliklerini dışarıda tutun.
2. Kaynak PR’yi inceleyin ve birleştirin. Uzak sürüm dalını alın ve bileşenin desteklediği platformlar ile TLS pozitif/negatif kontrolleri dahil olmak üzere **son birleştirilmiş ucunu** nitelendirin. Birleştirme öncesi geçen bir head, farklı bir squash veya merge commit’in niteliğini taşımaz.
3. Ayrı bir yayımlama onayıyla, eşleşen backport iş akışını **main’dan** tetikleyin; `source_sha` değerini tam olarak nitelenmiş birleştirilmiş uca, `base_tag` değerini ise mevcut stable etikete ayarlayın, örneğin `server@X.Y.Z` veya `kura@X.Y.Z`. İş akışı `X.Y.(Z+1)` türetir; operatörler minör artış seçmez veya canary içeriğini yükseltmez.

Planlama, tam uzak dalı ve temel etiketi yeniler, seçilen kaynağın dal ucuna eşit olmasını gerektirir, değişmemiş bir kaynağı veya bileşen dışındaki değişiklikleri, güven politikası girdilerini ve doğrulamayı reddeder ve çözümlenen temel commit’i sabitler. Main kaynaklı kontroller, sürümlü imaj ve GitHub yayımlamasından hemen önce bu kontrolleri tekrarlar. Kaynak dal, stable temel veya kullanılabilir sürüm değişirse, yeni bir kaynakla değiştirmek yerine durun ve yeniden nitelendirin.

Backport’lar, GitHub’ın “Latest” işaretçisini veya GHCR `:latest` etiketini taşımadan mevcut çoklu platform yayımcılarını kullanır. Yayımlama, barındırılan dağıtımdan ayrıdır: bu iş akışları barındırılan bir sunucu veya Kura filosunu yükseltmez, canary kabulünü atlamaz veya kurulu bir çalışma zamanını nitelendirmez. Derleme yardımcıları ve Dockerfile’lar hâlâ seçilen stable kaynaktan gelir. Kontroller yayımlama kapılarıdır, kimlik bilgisi gerektirmeyen derleme işleri değildir; derlemeler, son kapıdan önce etiketsiz imaj özetlerini yükleyebilir. İmaj ve GitHub yayımlaması atomik değildir: bir imaj etiketi yayımlandıktan sonra sonraki kapı başarısız olursa, kısmi sürümü inceleyin ve orijinal kaynağını ile yapıtlarını koruyun. Mevcut bir sürümü asla değiştirmeyin veya etiketi altında farklı baytlar kullanmayın.

## İyi commit mesajları yazma

Commit mesajları sürüm notlarını doğrudan etkilediğinden, net ve açıklayıcı mesajlar yazmak önemlidir:

### Yapılması gerekenler:
- Şimdiki zaman kullanın: “added feature” değil, “add feature”
- Özlü ama açıklayıcı olun
- Değişiklikler bileşene özgüyse kapsamı belirtin
- Uygun olduğunda sorunlara referans verin: `fix(cli): resolve build cache issue (#1234)`

### Yapılmaması gerekenler:
- “fix bug” veya “update code” gibi belirsiz mesajlar kullanmayın
- Birden fazla ilgisiz değişikliği tek bir commit’te birleştirmeyin
- Breaking change bilgilerini eklemeyi unutmayın

### Breaking changes

Breaking change’ler için commit gövdesine `BREAKING CHANGE:` ekleyin:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Sürüm iş akışları

CLI, sunucu ve Kura’nın her biri, aynı yapıyı takip eden kendi kanal iş akışlarına sahiptir:

- `<component>-release.yml` - `main` dalına bileşeni etkileyen her push’ta bir canary yayımlar (Kura’nınki, `kura/` değiştiğinde `server-production-deployment.yml` tarafından çağrılan yeniden kullanılabilir bir iş akışıdır)
- `<component>-rc.yml` - her Pazartesi bir release candidate keser (yükseltmeden sonra `workflow_run` aracılığıyla) veya manuel olarak bir tane keser/yineletir
- `<component>-promote.yml` - her Pazartesi saat 06:00 UTC’de bekleyen RC’yi stable’a yükseltir veya manuel olarak beklemiş bir RC’yi yükseltir
- `<component>-build-publish.yml` - yukarıdaki üçünün çağırdığı ortak derleme ve yayımlama hattı

CLI, sunucu ve Kura ayrıca stable bir seri üzerinde yamalar kesmek için `<component>-backport.yml` içerir. Bir bileşenin tüm iş akışları, sürüm çözümleme ve etiketlemenin asla yarışmaması için tek bir `<component>-publish` eşzamanlılık grubu üzerinden seri hale gelir. Kura istisnadır: canary’si `kura-canary-publish` kullanır; RC, yükseltme ve backport işlemleri ise `kura-stable-publish` kullanır, böylece uzun süren bir stable derleme dağıtım zincirini asla geciktirmez. Etiket ad alanları ayrık olduğundan, iki grup çakışamaz.

Helm grafiği ve altyapı imajları (CAPI operator, runners controller, xcresult processor image, linux runner image vb.) hâlâ `.github/workflows/server-production-deployment.yml` üzerinden yayımlanır. Bu iş akışı, `main` dalına yapılan push’larda çalışır ve barındırılan dağıtım için canary → kabul testleri → production zincirini izler; bu altyapı bileşenlerinde değişiklik olduğunda onları da yayımlar. Uygulama, önbellek, Gradle eklentisi, skills, Noora ve bağımsız altyapı denetleyicilerinin her biri kendi özel `*-release.yml` iş akışına sahiptir. Hepsi aynı değişiklik algılama mekanizmasını paylaşır: `mise/tasks/release/components.json`, her bileşenin etiket ön ekini ve dahil etme yollarını bildirir; git cliff ise eşleşen commit’leri sürüm notlarına dönüştürür.

CLI derlemesi (`cli-build-publish.yml`) ayrıca bir `tuist.spec.json` yapıtı üretip yayımlar (`tuist --experimental-dump-help` komutundan üretilir) böylece downstream araçlar komut arayüzünü tüketebilir.

## Sürümleri izleme

Sürümleri şu yollarla izleyebilirsiniz:
- [GitHub Releases sayfası](https://github.com/tuist/tuist/releases)
- İş akışı çalıştırmaları için GitHub Actions sekmesi
- Her bileşen dizinindeki changelog dosyaları

## Faydalar

Bu sürekli sürüm yaklaşımı şunları sağlar:

- **Hızlı teslimat**: Değişiklikler birleştirildikten hemen sonra kullanıcılara ulaşır
- **Darboğazların azalması**: Manuel sürümler için bekleme yok
- **Net iletişim**: Commit mesajlarından otomatik oluşturulan changelog’lar
- **Tutarlı süreç**: Tüm bileşenler için aynı sürüm akışı
- **Kalite güvencesi**: Yalnızca test edilmiş değişiklikler yayımlanır

## Sorun giderme

Bir sürüm başarısız olursa:

1. Başarısız iş akışı için GitHub Actions günlüklerini kontrol edin
2. Commit mesajlarınızın geleneksel biçimi takip ettiğinden emin olun
3. Tüm testlerin geçtiğini doğrulayın
4. Bileşenin başarıyla derlendiğini kontrol edin

Acil düzeltmeler ve hemen yayımlanması gereken durumlar için:
1. Commit’inizin net bir kapsama sahip olduğundan emin olun
2. Birleştirmeden sonra sürüm iş akışını izleyin
3. Sunucu veya uygulama için düzeltme sonraki push’ta yayımlanır; gerekirse manuel bir sürümü tetikleyin
4. CLI için düzeltme otomatik olarak canary’e iner. Stable kullanıcılarına ulaştırmak için bunu bakımı devam eden stable seri(ler)e backport edin (bkz. [Bir stable seriye düzeltmeleri backport etme](#backporting-fixes-to-a-stable-line))

## App Store sürümü

CLI ve Sunucu yukarıda anlatılan sürekli sürüm sürecini takip ederken, Apple’ın App Store inceleme süreci nedeniyle **iOS uygulaması** bir istisnadır:

- **Manuel sürümler**: iOS uygulama sürümleri App Store’a manuel gönderim gerektirir
- **İnceleme gecikmeleri**: Her sürüm, 1-7 gün sürebilen Apple’ın inceleme sürecinden geçmelidir
- **Toplu değişiklikler**: Birden fazla değişiklik genellikle her iOS sürümünde birlikte paketlenir
- **TestFlight**: Beta sürümleri, App Store sürümünden önce TestFlight üzerinden dağıtılabilir
- **Sürüm notları**: App Store yönergelerine uygun şekilde özel olarak yazılmalıdır

iOS uygulaması hâlâ aynı commit kurallarını takip eder ve changelog oluşturmak için git cliff kullanır, ancak kullanıcılara yönelik gerçek sürüm daha seyrek ve manuel bir takvime göre gerçekleşir.
