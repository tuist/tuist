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
- **Tuist CLI** - Komut satırı aracı; canary, release candidate ve stable [kanalları](#release-channels) üzerinden dağıtılır
- **Tuist Server** - Arka uç hizmetleri; CLI ile aynı kanal modeli üzerinden dağıtılır
- **Kura** - Önbellek sunucusu; CLI ile aynı kanal modeli üzerinden dağıtılır
- **Tuist App** - macOS ve iOS uygulamaları; sürekli olarak yayımlanır (iOS uygulaması yalnızca TestFlight’a sürekli olarak dağıtılır, daha fazla bilgi için [buraya](#app-store-release) bakın)

`main` adresine yapılan her gönderim, CLI, sunucu ve Kura için bir canary ön sürümü yayımlar. Bu bileşenlerin her biri için stable sürüm yalnızca bir bakıcı ıslatılmış bir release candidate’ı yükselttiğinde kesilir ve haftalık takvim üç treni de senkronize şekilde tetikler (bkz. [Sürüm kanalları](#release-channels)). Uygulama, `main` adresine yapılan her gönderimde stable sürüm yayımlar.

## Nasıl çalışır

### 1. Commit kuralları

Commit mesajlarımızı yapılandırmak için [Conventional Commits](https://www.conventionalcommits.org/) kullanıyoruz. Bu, araçlarımızın değişikliklerin doğasını anlamasına, sürüm artışlarını belirlemesine ve uygun değişiklik günlükleri oluşturmasına olanak tanır.

Biçim: `type(scope): description`

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

CLI için bu artışlar canary sürümünü ve değişiklik günlüğü gruplamasını belirler. Stable CLI sürümleri elle kesilen minör hatlardır (`X.Y.0`) ve stable patch’ler (`X.Y.Z`) yalnızca backport’lardan gelir; bu nedenle bir `feat` veya `fix`, CLI kullanıcılarına anında bir stable sürüm olarak değil, aşağıdaki kanal akışı üzerinden ulaşır.

#### Kırıcı değişiklikler

Kırıcı değişiklikler majör sürüm artışını (X.0.0) tetikler ve commit gövdesinde belirtilmelidir:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Değişiklik algılama

Her bileşen, şunları yapmak için [git cliff](https://git-cliff.org/) kullanır:
- Son sürümden bu yana yapılan commit’leri analiz eder
- Commit’leri kapsamına göre filtreler (cli, app, server)
- Sürüme çıkarılabilecek değişiklik olup olmadığını belirler
- Değişiklik günlüklerini otomatik olarak oluşturur

### 3. Sürüm hattı

Sürüme çıkarılabilecek değişiklikler algılandığında:

1. **Sürüm hesaplama**: Hat, bir sonraki sürüm numarasını belirler
2. **Değişiklik günlüğü oluşturma**: git cliff, commit mesajlarından bir değişiklik günlüğü oluşturur
3. **Derleme süreci**: Bileşen derlenir ve test edilir
4. **Yapıt üretimi**: CLI paketleri, sağlama toplamları ve `tuist --experimental-dump-help` komutundan üretilen `tuist.spec.json` CLI belirtimi gibi sürüme özgü varlıklar oluşturulur
5. **Sürüm oluşturma**: Yapıtlarla birlikte bir GitHub sürümü oluşturulur
6. **Dağıtım**: Güncellemeler paket yöneticilerine gönderilir (örneğin, CLI için Homebrew)

Uygulama için bu, her birleştirmede bir stable sürüm üretir. CLI, sunucu ve Kura için aynı otomatik hat yalnızca bir **canary** ön sürümü üretir; release candidate’lar ve stable sürümler haftalık sürüm treninde kesilir (bkz. [Sürüm kanalları](#release-channels)).

### 4. Kapsam filtreleme

Her bileşen yalnızca ilgili değişikliklere sahip olduğunda sürüm yayımlar:

- **CLI**: `(cli)` kapsamına sahip veya kapsamı olmayan commit’ler
- **App**: `(app)` kapsamına sahip commit’ler
- **Server**: `(server)` kapsamına sahip commit’ler

## Sürüm kanalları

CLI, sunucu ve Kura, `main` adresine yapılan her gönderimde stable sürüme yükseltilmez. Her biri üç kanal üzerinden dağıtılır; böylece önerilen kurulum stable ve yavaş ilerlerken, erken benimseyenler commit başına derlemeleri korur. Kullanıcıya yönelik belgeler <.localized_link href="/cli/release/channels">CLI sürüm kanalları</.localized_link> ve <.localized_link href="/guides/server/self-host/release/channels">Sunucu sürüm kanalları</.localized_link> sayfalarında bulunur; bu bölüm bakıcılar için çalışma kılavuzudur.

Her bileşen aynı üç kanalı kullanır:

| Kanal | Sürüm | Kesilme yöntemi |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | Otomatik olarak, `main` adresine bileşeni etkileyen her gönderimde (`<component>-release.yml`; Kura için, `kura/` değiştiğinde `server-production-deployment.yml` tarafından çağrılır) |
| Release candidate | `X.Y.0-rc.N` | Her Pazartesi veya manuel olarak, bir `releases/<component>-<major>.<minor>.x` dalında (`<component>-rc.yml`) |
| Stable | `X.Y.Z` | Her Pazartesi veya manuel olarak, ıslatılmış bir RC’yi yükselterek (`<component>-promote.yml`); patch’ler `<component>-backport.yml` yoluyla |

Canary ve RC derlemeleri GitHub ön sürümleri olarak yayımlanır (asla "Latest" olarak işaretlenmez, GHCR üzerinde `:latest` asla taşınmaz, CLI için Homebrew’e asla gönderilmez), bu nedenle paket yöneticileri ve imaj çözücüleri bunları yalnızca açıkça tercih edildiğinde alır. Canary her zaman bir sonraki yayımlanmamış minör sürümü hedefler: bir RC hattı kesildiğinde, `main` canary’si sonraki minör sürüme geçer.

Barındırılan Tuist, stable trenini beklemek zorunda değildir: sunucu commit başına dağıtılır ve barındırılan canary ile production en yeni Kura canary’sini çalıştırır. Dağıtım zinciri, o canary’yi dağıtmadan önce kendisi yayımlar; bu nedenle `kura-release.yml` kendi tetikleyicisine sahip değildir. Yalnızca Kura sürüm araçlarında yapılan değişiklikler (`mise/tasks/kura/**`, `kura-*.yml` iş akışları) bir canary kesmez.

Sürüm numaralarını asla elle seçmezsiniz. Her kanalın bir sonraki sürümü, aşağıdaki iş akışlarının çağırdığı `mise/tasks/<component>/release/channel-version.sh` tarafından mevcut git etiketlerinden türetilir.

Sürüm dalları bileşen başına ad alanına ayrılmıştır (CLI için `releases/server-X.Y.x`, `releases/kura-X.Y.x`, `releases/X.Y.x`), böylece üç bileşenin hatları aynı minör sürümde asla çakışmaz.

### Haftalık takvim

Her Pazartesi saat 06:00 UTC’de, üç bileşenin yükseltme işleri senkronize şekilde çalışır: **CLI’yi Stable’a Yükselt**, **Sunucuyu Stable’a Yükselt** ve **Kura’yı Stable’a Yükselt**. Her biri, henüz stable olmayan en yeni RC hattını yükseltir; bu genellikle önceki Pazartesi kesilen hattır. Böyle bir hat yoksa, bu iş hiçbir şey yayımlamaz.

Bir yükseltme tamamlandığında, sonuç ne olursa olsun, eşleşen **Release Candidate** iş akışı (`cli-rc.yml`, `server-rc.yml`, `kura-rc.yml`) `workflow_run` aracılığıyla tetiklenir ve `main` adresinden sonraki hattı keser.

Zamanlanmış çalışmalardan herhangi biri başarısız olur veya iptal edilirse Slack’e bir mesaj gönderilir. Release dalında en son RC’sinden sonra commit’ler varsa yükseltme başarısız olur. O hattı sürmek için üzerinde yeni bir RC kesin ve manuel olarak yükseltin. Aksi takdirde, bir sonraki Pazartesi daha yeni hattı yükseltir.

### Bir release candidate kesme

Haftalık takvimin dışında yeni bir hat kesmek için (aşağıda bileşenin iş akışı adını yerine koyun):

1. `branch` girişi boş bırakarak **\<Component\> Release Candidate** iş akışını çalıştırın (örneğin `server-rc.yml`).
2. `X.Y.0-rc.1` yayımlar ve bu başarılı olduktan sonra, derlenen commit’te korumalı `releases/<component>-X.Y.x` dalını oluşturur.

Kritik bir düzeltmeyi veya regresyonu ıslatma hattına çekmek için, bir PR aracılığıyla release dalına cherry-pick yapın (backport’larla aynı akış; CI asla cherry-pick yapmaz), ardından RC’yi yineleyin:

1. `releases/<component>-X.Y.x` adresinden dallanın, düzeltmeyi cherry-pick edin, release dalına geri doğru bir PR açın, varsa çakışmaları çözün ve birleştirin.
2. `branch=releases/<component>-X.Y.x` ile **Release Candidate** iş akışını tekrar çalıştırın. Dal HEAD’inden `X.Y.0-rc.(N+1)` yayımlar.

Bir ıslatma hattı özellik donduruludur: üzerine yalnızca kritik düzeltmeler ve regresyonlar alınır.

### Stable’a yükseltme

RC’si temizce ıslatıldıktan sonra, haftalık takvimin dışında bir hattı yükseltmek için:

1. `branch=releases/<component>-X.Y.x` ile **\<Component\> Promote to Stable** iş akışını çalıştırın (örneğin `server-promote.yml`).
2. Semver etiketli imajı `make_latest=true` ile yayımlar, GHCR `:latest` etiketini ve GitHub “Latest” işaretçisini taşır. CLI ayrıca Homebrew formülünü günceller.

Dal HEAD’i tam olarak en son RC’nin işaret ettiği commit değilse yükseltme çalışmayı reddeder. Bu nedenle, son RC’den sonra hatta herhangi bir düzeltme birleştirildiyse, stable olarak sürülebilmesi önce yeni bir RC kesmeniz ve onu ıslatmanız gerekir.

### Düzeltmeleri stable bir hatta backport etme

Bir hat stable olduktan sonra, yamaları yalnızca CLI’ye özel **Backport Release** iş akışıyla (`cli-backport.yml`) sürün: düzeltmeyi bir PR aracılığıyla `releases/X.Y.x` üzerine cherry-pick edin, ardından `X.Y.(Z+1)` kesmek için iş akışını o dallarla çalıştırın. Backport’lar asla “Latest” işaretçisini veya Homebrew formülünü taşımaz. Aynı anda iki hat korunur: mevcut hat regresyonları ve güvenlik düzeltmelerini alır, önceki hat yalnızca kritik ve güvenlik düzeltmelerini alır. Diğer hata düzeltmeleri backport edilmez ve bir sonraki minörle birlikte sürülür.

Sunucu ve Kura için **Server Backport Release** (`server-backport.yml`) veya **Kura Backport Release** (`kura-backport.yml`) kullanın. Yükseltme yalnızca bir RC’nin `X.Y.0` sürümünü yayımlar; zaten stable olan bir hattı yamalayamaz.

1. Seçilen `X.Y` hattındaki en son yayımlanan stable bileşen etiketinden başlayın ve mevcut `releases/server-X.Y.x` veya `releases/kura-X.Y.x` dalına cerrahi bir düzeltme PR’si açın. Daha yeni bir minör veya major sürüm, bakımı yapılan bir hattı yamalamayı engellemez. İlgisiz main değişikliklerini dışarıda tutun.
2. Kaynak PR’yi inceleyin ve birleştirin. Uzak release dalını çekin ve bileşenin desteklediği platformlar ile TLS pozitif/negatif kontrolleri dahil olmak üzere **final merged tip** niteliğini belirleyin. Birleşme öncesi geçen bir head, farklı bir squash veya merge commit’in niteliği değildir.
3. Ayrı yayınlama onayıyla, eşleşen backport iş akışını **from main** üzerinden dispatch edin; `source_sha` değerini tam olarak niteliklendirilmiş birleşmiş uca, `base_tag` değerini ise mevcut stable etikete ayarlayın, örneğin `server@X.Y.Z` veya `kura@X.Y.Z`. İş akışı `X.Y.(Z+1)` türetir; operatörler minör artışı seçmez veya canary içeriğini yükseltmez.

Planlama, tam uzak dalı ve base etiketi yeniler, seçilen kaynağın dal ucuna eşit olmasını gerektirir, değişmemiş bir kaynağı veya bileşen dışındaki değişiklikleri, güven politikası girdilerini ve doğrulamayı reddeder ve çözümlenen base commit’i sabitler. Main kaynaklı kontroller, sürümlü imaj ve GitHub yayınlamasından hemen önce bu kontrolleri tekrarlar. Kaynak dal, stable base veya kullanılabilir sürüm değişirse, yeni bir kaynak ikame etmek yerine durun ve yeniden nitelendirin.

Backport’lar, GitHub’ın “Latest” işaretçisini veya GHCR `:latest` etiketini taşımadan mevcut çoklu platform yayımcılarını kullanır. Yayınlama, barındırılan dağıtımdan ayrıdır: bu iş akışları barındırılan bir sunucu veya Kura filosunu yükseltmez, canary kabulünü atlamaz veya kurulu bir çalışma zamanını nitelendirmez. Derleme yardımcıları ve Dockerfile’lar hâlâ seçilen stable kaynaktan gelir. Kontroller yayınlama kapılarıdır, kimlik bilgisi gerektirmeyen derleme işleri değildir; derlemeler, son kapıdan önce etiketsiz imaj özetlerini yükleyebilir. İmaj ve GitHub yayınlaması atomik değildir: bir imaj etiketi yayımlandıktan sonra sonraki kapı başarısız olursa, kısmi sürümü inceleyin ve orijinal kaynağını ile yapıtlarını koruyun. Mevcut bir sürümü asla değiştirmeyin veya etiketi altında farklı baytlar kullanmayın.

## İyi commit mesajları yazma

Commit mesajları sürüm notlarını doğrudan etkilediğinden, açık ve açıklayıcı mesajlar yazmak önemlidir:

### Yapılması gerekenler:
- Şimdiki zaman kullanın: “added feature” değil “add feature”
- Özlü ama açıklayıcı olun
- Değişiklikler bileşene özgüyse kapsamı dahil edin
- Uygun olduğunda sorunlara atıfta bulunun: `fix(cli): resolve build cache issue (#1234)`

### Yapılmaması gerekenler:
- “fix bug” veya “update code” gibi belirsiz mesajlar kullanmayın
- Birden fazla ilgisiz değişikliği tek bir commit’te karıştırmayın
- Breaking change bilgilerini eklemeyi unutmayın

### Breaking changes

Breaking change’ler için, commit gövdesine `BREAKING CHANGE:` ekleyin:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Sürüm iş akışları

CLI, sunucu ve Kura’nın her biri, aynı yapıyı izleyen kendi kanal iş akışlarına sahiptir:

- `<component>-release.yml` - `main` adresine bileşeni etkileyen her push’ta bir canary yayımlar (Kura’nınki, `kura/` değiştiğinde `server-production-deployment.yml` tarafından çağrılan yeniden kullanılabilir bir iş akışıdır)
- `<component>-rc.yml` - her Pazartesi bir release candidate keser (yükseltmeden sonra `workflow_run` aracılığıyla) veya manuel olarak birini keser ya da yineletir
- `<component>-promote.yml` - bekleyen RC’yi her Pazartesi saat 06:00 UTC’de stable’a yükseltir veya ıslatılmış bir RC’yi manuel olarak yükseltir
- `<component>-build-publish.yml` - yukarıdaki üçünün çağırdığı ortak derleme ve yayınlama hattı

CLI, sunucu ve Kura ayrıca stable bir hatta yama kesmek için `<component>-backport.yml` içerir. Bir bileşenin tüm iş akışları, sürüm çözümleme ve etiketlemenin asla yarışmaması için tek bir `<component>-publish` eşzamanlılık grubu üzerinden serileştirilir. Kura istisnadır: canary’si `kura-canary-publish` kullanır ve RC, yükseltme ile backport’ları `kura-stable-publish` kullanır, böylece uzun bir stable derleme dağıtım zincirini asla bekletmez. Etiket ad alanları ayrık olduğundan, iki grup çakışamaz.

Helm şeması ve altyapı imajları (CAPI operator, runners controller, xcresult processor image, linux runner image vb.) hâlâ `.github/workflows/server-production-deployment.yml` üzerinden yayımlanır. `main` adresine yapılan push’larda çalışır ve barındırılan dağıtım için canary → kabul testleri → production zincirini izler; bu altyapı bileşenleri değiştikçe yayımlanır. Uygulama, önbellek, Gradle eklentisi, skills, Noora ve bağımsız altyapı denetleyicilerinin her biri ayrı bir `*-release.yml` iş akışına sahiptir. Hepsi değişiklik algılamayı paylaşır: `mise/tasks/release/components.json` her bileşenin etiket ön ekini ve dahil etme yollarını bildirir ve git cliff eşleşen commit’leri sürüm notlarına dönüştürür.

CLI derlemesi (`cli-build-publish.yml`) ayrıca bir `tuist.spec.json` yapıtı üretir ve yayımlar (`tuist --experimental-dump-help` komutundan üretilir) böylece downstream araçlar komut arayüzünü tüketebilir.

## Sürümleri izleme

Sürümleri şu yollarla izleyebilirsiniz:
- [GitHub Releases sayfası](https://github.com/tuist/tuist/releases)
- İş akışı çalışmaları için GitHub Actions sekmesi
- Her bileşen dizinindeki changelog dosyaları

## Avantajlar

Bu sürekli sürüm yaklaşımı şunları sağlar:

- **Hızlı teslimat**: Değişiklikler birleştirildikten hemen sonra kullanıcılara ulaşır
- **Darboğazların azalması**: Manuel sürümler için bekleme yok
- **Net iletişim**: Commit mesajlarından otomatik oluşturulan changelog’lar
- **Tutarlı süreç**: Tüm bileşenler için aynı sürüm akışı
- **Kalite güvencesi**: Yalnızca test edilmiş değişiklikler yayımlanır

## Sorun giderme

Bir sürüm başarısız olursa:

1. Başarısız iş akışı için GitHub Actions günlüklerini kontrol edin
2. Commit mesajlarınızın geleneksel biçimi izlediğinden emin olun
3. Tüm testlerin geçtiğini doğrulayın
4. Bileşenin başarıyla derlendiğini kontrol edin

Acil ve hemen yayımlanması gereken düzeltmeler için:
1. Commit’inizin net bir kapsamı olduğundan emin olun
2. Birleştirmeden sonra sürüm iş akışını izleyin
3. Sunucu veya uygulama için düzeltme sonraki push’ta yayımlanır; gerekirse manuel bir sürümü tetikleyin
4. CLI için düzeltme otomatik olarak canary’a iner. Stable kullanıcılarına ulaştırmak için bunu bakımı yapılan stable hat(lar)a backport edin (bkz. [Bir stable hatta düzeltmeleri backport etme](#backporting-fixes-to-a-stable-line))

## App Store sürümü

CLI ve Sunucu yukarıda anlatılan sürekli sürüm sürecini izlerken, **iOS uygulaması** Apple’ın App Store inceleme süreci nedeniyle bir istisnadır:

- **Manuel sürümler**: iOS uygulama sürümleri App Store’a manuel gönderim gerektirir
- **İnceleme gecikmeleri**: Her sürüm, 1-7 gün sürebilen Apple’ın inceleme sürecinden geçmelidir
- **Toplu değişiklikler**: Birden fazla değişiklik genellikle her iOS sürümünde birlikte paketlenir
- **TestFlight**: Beta sürümleri, App Store sürümünden önce TestFlight üzerinden dağıtılabilir
- **Sürüm notları**: App Store yönergeleri için özel olarak yazılmalıdır

iOS uygulaması hâlâ aynı commit kurallarını izler ve changelog oluşturma için git cliff kullanır, ancak kullanıcılara yönelik gerçek sürüm daha seyrek, manuel bir takvime göre gerçekleşir.
