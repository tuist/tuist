---
{
  "title": "Sürümler",
  "titleTemplate": ":title | Katkıda Bulunanlar | Tuist",
  "description": "Tuist'in sürekli sürüm sürecinin nasıl çalıştığını öğrenin"
}
---
# Sürümler

Tuist, değişiklikler ana dala birleştirildiğinde yeni sürümleri otomatik olarak yayımlar. CLI, sunucu ve Kura önbellek sunucusu, önerilen kurulumun kararlı ve yavaş ilerlemesini sağlamak için sürüm kanalları (canary, sürüm adayı, kararlı) üzerinden dağıtılır; bir sürüm adayını kesmek ve onu kararlı hale getirmek kasıtlı, haftalık adımlardır. Uygulama sürekli olarak yayımlanır (iOS uygulaması yalnızca TestFlight'a sürekli olarak dağıtılır, daha fazla bilgi için [buraya](#app-store-release) bakın).

## Genel Bakış

Bu ana bileşenleri yayımlıyoruz:
- **Tuist CLI** - Komut satırı aracı, canary, sürüm adayı ve kararlı [kanallar](#release-channels) üzerinden dağıtılır
- **Tuist Server** - Arka uç hizmetleri, CLI ile aynı kanal modeli üzerinden dağıtılır
- **Kura** - Önbellek sunucusu, CLI ile aynı kanal modeli üzerinden dağıtılır
- **Tuist App** - macOS ve iOS uygulamaları, sürekli olarak yayımlanır (iOS uygulaması yalnızca TestFlight'a sürekli olarak dağıtılır, daha fazla bilgi için [buraya](#app-store-release) bakın)

`main` adresine yapılan her push işlemi, CLI, sunucu ve Kura için bir canary ön sürümü yayımlar. Bu bileşenlerin her biri için kararlı bir sürüm, yalnızca bir bakımcı iyice test edilmiş bir sürüm adayını terfi ettirdiğinde kesilir ve haftalık takvim üç treni de senkronize şekilde çalıştırır (bkz. [Sürüm kanalları](#release-channels)). Uygulama, `main` adresine yapılan her push işleminde kararlı sürüm yayımlar.

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

CLI için bu artışlar canary sürümünü ve değişiklik günlüğü gruplamasını belirler. Kararlı CLI sürümleri elle kesilen minör satırlardır (`X.Y.0`) ve kararlı patch'ler (`X.Y.Z`) yalnızca geri taşımalardan gelir; bu nedenle bir `feat` veya `fix` CLI kullanıcılarına anında kararlı bir sürüm olarak değil, aşağıdaki kanal akışı üzerinden ulaşır.

#### Kırıcı değişiklikler

Kırıcı değişiklikler majör sürüm artışını (X.0.0) tetikler ve commit gövdesinde belirtilmelidir:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Değişiklik tespiti

Her bileşen, şunları yapmak için [git cliff](https://git-cliff.org/) kullanır:
- Son sürümden bu yana yapılan commit'leri analiz eder
- Commit'leri kapsamına göre filtreler (cli, app, server)
- Yayımlanabilir değişiklik olup olmadığını belirler
- Değişiklik günlüklerini otomatik olarak oluşturur

### 3. Sürüm hattı

Yayımlanabilir değişiklikler tespit edildiğinde:

1. **Sürüm hesaplama**: Hat, bir sonraki sürüm numarasını belirler
2. **Değişiklik günlüğü oluşturma**: git cliff, commit mesajlarından bir değişiklik günlüğü oluşturur
3. **Derleme süreci**: Bileşen derlenir ve test edilir
4. **Yapıtların oluşturulması**: CLI paketleri, sağlama toplamları ve `tuist --experimental-dump-help` üzerinden üretilen `tuist.spec.json` CLI spesifikasyonu gibi sürüme özel varlıklar üretilir
5. **Sürüm oluşturma**: Yapıtlarla birlikte bir GitHub sürümü oluşturulur
6. **Dağıtım**: Güncellemeler paket yöneticilerine gönderilir (örneğin, CLI için Homebrew)

Uygulama için bu, her birleştirmede kararlı bir sürüm üretir. CLI, sunucu ve Kura için aynı otomatik hat yalnızca bir **canary** ön sürümü üretir; sürüm adayları ve kararlı sürümler haftalık sürüm treninde kesilir (bkz. [Sürüm kanalları](#release-channels)).

### 4. Kapsam filtreleme

Her bileşen yalnızca ilgili değişikliklere sahip olduğunda sürüm yayımlar:

- **CLI**: `(cli)` kapsamına sahip veya kapsamı olmayan commit'ler
- **App**: `(app)` kapsamına sahip commit'ler
- **Server**: `(server)` kapsamına sahip commit'ler

## Sürüm kanalları

CLI, sunucu ve Kura, `main` adresine yapılan her push işleminde kararlı bir sürüme terfi ettirilmez. Her biri üç kanal üzerinden dağıtılır; böylece önerilen kurulum kararlı ve yavaş ilerlerken, erken benimseyenler commit başına derlemeleri korur. Kullanıcıya yönelik belgeler <.localized_link href="/cli/release-channels">CLI sürüm kanalları</.localized_link> ve <.localized_link href="/guides/server/self-host/release-channels">Sunucu sürüm kanalları</.localized_link> adreslerinde bulunur; bu bölüm bakımcı çalışma kılavuzudur.

Her bileşen aynı üç kanalı kullanır:

| Kanal | Sürüm | Kesim yöntemi |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | Otomatik olarak, `main` adresine yapılan ve bileşeni etkileyen her push işleminde (`<component>-release.yml`; Kura için, `kura/` değiştiğinde `server-production-deployment.yml` tarafından çağrılır) |
| Sürüm adayı | `X.Y.0-rc.N` | Her Pazartesi veya manuel olarak, bir `releases/<component>-<major>.<minor>.x` dalında (`<component>-rc.yml`) |
| Kararlı | `X.Y.Z` | Her Pazartesi veya manuel olarak, iyice test edilmiş bir RC'yi terfi ettirerek (`<component>-promote.yml`); patch'ler `<component>-backport.yml` yoluyla |

Canary ve RC derlemeleri GitHub ön sürümleri olarak yayımlanır (asla "Latest" olarak işaretlenmez, GHCR'da `:latest` asla hareket ettirilmez, CLI için Homebrew'e asla gönderilmez), bu nedenle paket yöneticileri ve görüntü çözücüleri bunları yalnızca açıkça tercih edildiğinde alır. Canary her zaman yayınlanmamış bir sonraki minör sürümü hedefler: bir RC satırı kesildiğinde, `main`'nin canary'si bir sonraki minör sürüme geçer.

Barındırılan Tuist kararlı treni beklemez: sunucu commit başına dağıtılır ve barındırılan canary ile üretim en yeni Kura canary'sini çalıştırır. Dağıtım zinciri, onu dağıtmadan önce o canary'nin kendisini yayımlar, bu nedenle `kura-release.yml` kendi tetikleyicisine sahip değildir. Yalnızca Kura sürüm araçlarında yapılan değişiklikler (`mise/tasks/kura/**`, `kura-*.yml` iş akışları) bir canary kesmez.

Sürüm numaralarını asla elle seçmezsiniz. Her kanalın bir sonraki sürümü, aşağıdaki iş akışlarının çağırdığı `mise/tasks/<component>/release/channel-version.sh` tarafından mevcut git etiketlerinden türetilir.

Sürüm dalları bileşen başına ad alanına ayrılmıştır (CLI için `releases/server-X.Y.x`, `releases/kura-X.Y.x`, `releases/X.Y.x`), böylece üç bileşenin satırları aynı minör sürümde asla çarpışmaz.

### Haftalık takvim

Her Pazartesi saat 06:00 UTC'de, üç bileşenin terfi işleri senkronize şekilde çalışır: **CLI'yi Kararlıya Terfi Et**, **Sunucuyu Kararlıya Terfi Et** ve **Kura'yı Kararlıya Terfi Et**. Her biri, henüz kararlı olmayan en yeni RC satırını terfi ettirir; bu genellikle önceki Pazartesi kesilen sattır. Böyle bir satır yoksa, bu iş hiçbir şey yayımlamaz.

Bir terfi tamamlandığında, sonuç ne olursa olsun, eşleşen **Sürüm Adayı** iş akışı (`cli-rc.yml`, `server-rc.yml`, `kura-rc.yml`) `workflow_run` yoluyla tetiklenir ve `main` adresinden bir sonraki satırı keser.

Planlanan çalıştırmalardan herhangi biri başarısız olur veya iptal edilirse Slack'e bir mesaj gönderilir. Sürüm dalında en son RC'den sonra commit'ler varsa terfi başarısız olur. O satırı yayımlamak için üzerinde yeni bir RC kesin ve manuel olarak terfi ettirin. Aksi takdirde, bir sonraki Pazartesi daha yeni satırı terfi ettirir.

### Sürüm adayı kesme

Haftalık takvimin dışında yeni bir satır kesmek için (aşağıda bileşenin iş akışı adını yerine koyun):

1. `branch` girişi boş bırakarak **\<Bileşen\> Sürüm Adayı** iş akışını çalıştırın (örneğin `server-rc.yml`).
2. `X.Y.0-rc.1` yayımlar ve bu başarılı olduktan sonra, oluşturulan commit'te korumalı `releases/<component>-X.Y.x` dalını oluşturur.

Kritik bir düzeltmeyi veya regresyonu bekleyen bir satıra çekmek için, onu bir PR aracılığıyla sürüm dalına cherry-pick yapın (backport'larla aynı akış; CI asla cherry-pick yapmaz), ardından RC'yi yineleyin:

1. `releases/<component>-X.Y.x` adresinden dallanın, düzeltmeyi cherry-pick yapın, sürüm dalına geri bir PR açın, varsa çakışmaları çözün ve birleştirin.
2. `branch=releases/<component>-X.Y.x` ile **Sürüm Adayı** iş akışını tekrar çalıştırın. Dal HEAD'inden `X.Y.0-rc.(N+1)` yayımlar.

Bekleyen bir satır özellik dondurulmuştur: üzerine yalnızca kritik düzeltmeler ve regresyonlar alınır.

### Kararlıya terfi ettirme

RC'si temizce beklemiş bir satırı haftalık takvimin dışında terfi ettirmek için:

1. `branch=releases/<component>-X.Y.x` ile **\<Bileşen\> Kararlıya Terfi Et** iş akışını çalıştırın (örneğin `server-promote.yml`).
2. GHCR `:latest` etiketini ve GitHub "En Son" işaretçisini taşıyarak, `make_latest=true` ile semver etiketli imajı yayımlar. CLI ayrıca Homebrew formülünü günceller.

Dal HEAD'i en son RC'nin işaret ettiği commit ile tam olarak eşleşmedikçe terfi çalışmayı reddeder. Bu nedenle, son RC'den sonra satıra herhangi bir düzeltme birleştirildiyse, kararlı olarak yayımlanabilmesi önce yeni bir RC kesmeniz ve onun beklemesine izin vermeniz gerekir.

### Düzeltmeleri kararlı bir satıra backport etme

Bir satır kararlı hale geldikten sonra, yalnızca CLI için olan **Backport Sürümü** iş akışı (`cli-backport.yml`) ile yamaları yayımlayın: düzeltmeyi bir PR aracılığıyla `releases/X.Y.x` üzerine cherry-pick yapın, ardından `X.Y.(Z+1)` kesmek için iş akışını o dal ile çalıştırın. Backport'lar asla "En Son" işaretçisini veya Homebrew formülünü hareket ettirmez. Aynı anda iki satır korunur: mevcut satır regresyonları ve güvenlik düzeltmelerini alır, önceki satır yalnızca kritik ve güvenlik düzeltmelerini alır. Diğer hata düzeltmeleri backport edilmez ve bir sonraki minör sürümle yayımlanır.

Sunucu ve Kura için **Sunucu Backport Sürümü** (`server-backport.yml`) veya **Kura Backport Sürümü** (`kura-backport.yml`) kullanın. Terfi, yalnızca bir RC'nin `X.Y.0` sürümünü yayımlar; zaten kararlı olan bir satırı yamalayamaz.

1. Seçilen `X.Y` satırındaki en son yayımlanan kararlı bileşen etiketinden başlayın ve mevcut `releases/server-X.Y.x` veya `releases/kura-X.Y.x` dalına cerrahi bir düzeltme PR'si açın. Daha yeni bir minör veya majör sürüm, bakımı yapılan bir satırı yamalamanızı engellemez. İlgisiz main değişikliklerini dışarıda tutun.
2. Kaynak PR'yi inceleyin ve birleştirin. Uzak sürüm dalını getirin ve bileşenin desteklenen platformları ile TLS pozitif/negatif kontrolleri dahil olmak üzere **son birleştirilmiş ucunu** nitelendirin. Başarılı bir ön-birleştirme başlığı, farklı bir squash veya birleştirme commit'inin niteliği değildir.
3. Ayrı yayımlama onayı ile, eşleşen backport iş akışını **main'den** tetikleyin; `source_sha` değerini tam olarak nitelenmiş birleştirilmiş uca, `base_tag` değerini ise `server@X.Y.Z` veya `kura@X.Y.Z` gibi mevcut kararlı etikete ayarlayın. İş akışı `X.Y.(Z+1)` türetir; operatörler minör artış seçmez veya canary içeriğini terfi ettirmez.

Planlama, tam uzak dalı ve temel etiketi yeniler, seçilen kaynağın dal ucuna eşit olmasını gerektirir, değişmemiş bir kaynağı veya bileşen dışındaki değişiklikleri, güven politikası girişlerini ve doğrulamayı reddeder ve çözümlenen temel commit'i sabitler. Main kaynaklı kontroller, sürümlü imaj ve GitHub yayımlamasından hemen önce bu kontrolleri tekrarlar. Kaynak dal, kararlı temel veya mevcut sürüm değişirse, yeni bir kaynakla değiştirmek yerine durun ve yeniden nitelendirin.

Backport'lar, GitHub'ın "En Son" işaretçisini veya GHCR `:latest` etiketini hareket ettirmeden mevcut çoklu platform yayımcılarını kullanır. Yayımlama, barındırılan dağıtımdan ayrıdır: bu iş akışları barındırılan bir sunucu veya Kura filosunu terfi ettirmez, canary kabulünü atlamaz veya kurulu bir çalışma zamanını nitelendirmez. Derleme yardımcıları ve Dockerfile'lar hala seçilen kararlı kaynaktan gelir. Kontroller, kimlik bilgisi gerektirmeyen derleme işleri değil, yayımlama kapılarıdır; derlemeler son kapıdan önce etiketsiz imaj özetlerini yükleyebilir. İmaj ve GitHub yayımlaması atomik değildir: bir imaj etiketi yayımlandıktan sonra sonraki kapı başarısız olursa, kısmi sürümü inceleyin ve orijinal kaynağını ile yapıtlarını koruyun. Mevcut bir sürümü asla değiştirmeyin veya etiketi altında farklı baytlar kullanmayın.

## İyi commit mesajları yazma

Commit mesajları sürüm notlarını doğrudan etkilediğinden, net ve açıklayıcı mesajlar yazmak önemlidir:

### Yapılması gerekenler:
- Şimdiki zaman kullanın: "özellik eklendi" değil "özellik ekle"
- Özlü ama açıklayıcı olun
- Değişiklikler bileşene özgüyse kapsamı dahil edin
- Uygun olduğunda sorunlara referans verin: `fix(cli): resolve build cache issue (#1234)`

### Yapılmaması gerekenler:
- "hatayı düzelt" veya "kodu güncelle" gibi belirsiz mesajlar kullanmayın
- Birden fazla ilgisiz değişikliği tek bir commit'te birleştirmeyin
- Kırıcı değişiklik bilgilerini dahil etmeyi unutmayın

### Kırıcı değişiklikler

Kırıcı değişiklikler için, commit gövdesine `BREAKING CHANGE:` ekleyin:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Sürüm iş akışları

CLI, sunucu ve Kura'nın her biri, aynı yapıyı takip eden kendi kanal iş akışlarına sahiptir:

- `<component>-release.yml` - `main` adresine yapılan her bileşen temaslı push'ta bir canary yayımlar (Kura'nınki, `kura/` değiştiğinde `server-production-deployment.yml` tarafından çağrılan yeniden kullanılabilir bir iş akışıdır)
- `<component>-rc.yml` - her Pazartesi bir sürüm adayı keser (terfiden sonra `workflow_run` yoluyla) veya manuel olarak bir tane keser veya yineletir
- `<component>-promote.yml` - her Pazartesi saat 06:00 UTC'de bekleyen RC'yi kararlıya terfi ettirir veya manuel olarak beklemiş bir RC'yi terfi ettirir
- `<component>-build-publish.yml` - yukarıdaki üçünün çağırdığı paylaşılan derleme ve yayımlama hattı

CLI, sunucu ve Kura ayrıca kararlı bir satır üzerinde yamalar kesmek için `<component>-backport.yml` içerir. Bir bileşenin tüm iş akışları, sürüm çözümleme ve etiketlemenin asla yarışmaması için tek bir `<component>-publish` eşzamanlılık grubu üzerinden seri hale gelir. Kura istisnadır: canary'si `kura-canary-publish` kullanır ve RC, terfi ve backport'u `kura-stable-publish` kullanır, böylece uzun süren bir kararlı derleme dağıtım zincirini asla bekletmez. Etiket ad alanları ayrık olduğundan, iki grup çarpışamaz.

Helm şeması ve altyapı imajları (CAPI operatörü, çalıştırıcı denetleyicisi, xcresult işleyici imajı, Linux çalıştırıcı imajı vb.) hâlâ `.github/workflows/server-production-deployment.yml` üzerinden yayımlanır. Bu iş akışı, `main` adresine yapılan push'larda çalışır ve barındırılan dağıtım için canary → kabul testleri → üretim zincirini izler; bu altyapı bileşenlerinde değişiklik olduğunda onları da yayımlar. Uygulama, önbellek, Gradle eklentisi, beceriler, Noora ve bağımsız altyapı denetleyicilerinin her biri kendi `*-release.yml` iş akışına sahiptir. Hepsi değişim algılamayı paylaşır: `mise/tasks/release/components.json` her bileşenin etiket ön ekini ve dahil etme yollarını bildirir; git cliff ise eşleşen commit'leri sürüm notlarına dönüştürür.

CLI derlemesi (`cli-build-publish.yml`) ayrıca bir `tuist.spec.json` yapıtı üretir ve yayımlar (`tuist --experimental-dump-help` komutundan üretilir) böylece alt zincir araçları komut arayüzünü tüketebilir.

## Sürümleri izleme

Sürümleri şu yollarla izleyebilirsiniz:
- [GitHub Sürümler sayfası](https://github.com/tuist/tuist/releases)
- İş akışı çalıştırmaları için GitHub Actions sekmesi
- Her bileşen dizinindeki değişiklik günlüğü dosyaları

## Faydalar

Bu sürekli sürüm yaklaşımı şunları sağlar:

- **Hızlı teslimat**: Değişiklikler birleştirildikten hemen sonra kullanıcılara ulaşır
- **Darboğazların azalması**: Manuel sürümler için bekleme yok
- **Net iletişim**: Commit mesajlarından otomatik oluşturulan değişiklik günlükleri
- **Tutarlı süreç**: Tüm bileşenler için aynı sürüm akışı
- **Kalite güvencesi**: Yalnızca test edilmiş değişiklikler yayımlanır

## Sorun giderme

Bir sürüm başarısız olursa:

1. Başarısız iş akışı için GitHub Actions günlüklerini kontrol edin
2. Commit mesajlarınızın geleneksel biçimi takip ettiğinden emin olun
3. Tüm testlerin geçtiğini doğrulayın
4. Bileşenin başarıyla derlendiğini kontrol edin

Acil ve hemen yayımlanması gereken düzeltmeler için:
1. Commit'inizin net bir kapsamı olduğundan emin olun
2. Birleştirmeden sonra sürüm iş akışını izleyin
3. Sunucu veya uygulama için düzeltme sonraki push ile yayımlanır; gerekirse manuel bir sürümü tetikleyin
4. CLI için düzeltme otomatik olarak canary'a iner. Kararlı kullanıcılar için bunu sürdürülen kararlı satır(lar)a backport edin (bkz. [Bir kararlı satıra düzeltmeleri backport etme](#backporting-fixes-to-a-stable-line))

## App Store sürümü

CLI ve Sunucu yukarıda açıklanan sürekli sürüm sürecini takip ederken, Apple'ın App Store inceleme süreci nedeniyle **iOS uygulaması** bir istisnadır:

- **Manuel sürümler**: iOS uygulama sürümleri App Store'a manuel gönderim gerektirir
- **İnceleme gecikmeleri**: Her sürüm, 1-7 gün sürebilen Apple'ın inceleme sürecinden geçmelidir
- **Toplu değişiklikler**: Genellikle birden fazla değişiklik her iOS sürümünde birlikte paketlenir
- **TestFlight**: Beta sürümleri, App Store sürümünden önce TestFlight aracılığıyla dağıtılabilir
- **Sürüm notları**: App Store yönergelerine özel olarak yazılmalıdır

iOS uygulaması hâlâ aynı commit kurallarını takip eder ve değişiklik günlüğü oluşturmak için git cliff kullanır, ancak kullanıcılara yönelik gerçek sürüm daha seyrek, manuel bir takvime göre gerçekleşir.
