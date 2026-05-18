---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# Sürümler

Tuist, anlamlı değişiklikler ana dalla birleştirildiğinde yeni sürümleri
otomatik olarak yayınlayan sürekli bir sürüm sistemi kullanır. Bu yaklaşım,
bakımcıların manuel müdahalesi olmadan iyileştirmelerin kullanıcılara hızlı bir
şekilde ulaşmasını sağlar.

## Genel Bakış

Sürekli olarak üç ana bileşeni piyasaya sürüyoruz:
- **Tuist CLI** - Komut satırı aracı
- **Tuist Sunucusu** - Arka uç hizmetleri
- **Tuist Uygulaması** - macOS ve iOS uygulamaları (iOS uygulaması yalnızca
  TestFlight'a sürekli olarak dağıtılır, daha fazla bilgi için [buraya] bakın}

Her bileşenin, ana dala yapılan her gönderimde otomatik olarak çalışan kendi
sürüm işlem hattı vardır.

## Nasıl çalışır

### 1. Sözleşmeleri taahhüt edin

Taahhüt mesajlarımızı yapılandırmak için [Conventional
Commits](https://www.conventionalcommits.org/) kullanıyoruz. Bu, araçlarımızın
değişikliklerin doğasını anlamasına, sürüm atlamalarını belirlemesine ve uygun
değişiklik günlükleri oluşturmasına olanak tanır.

Biçim: `tür (kapsam): açıklama`

#### Taahhüt türleri ve etkileri

| Tip          | Açıklama                       | Sürüm Etkisi                    | Örnekler                                              |
| ------------ | ------------------------------ | ------------------------------- | ----------------------------------------------------- |
| `feat`       | Yeni özellik veya kabiliyet    | Küçük sürüm yükseltmesi (x.Y.z) | `feat(CLI): Swift 6 için destek ekleyin`              |
| `düzeltmek`  | Hata düzeltme                  | Yama sürümü çarpması (x.y.Z)    | `fix(app): projeler açılırken oluşan çökme giderildi` |
| `dokümanlar` | Dokümantasyon değişiklikleri   | Serbest bırakma yok             | `dokümanlar: güncelleme kurulum kilavuzu`             |
| `stil`       | Kod stili değişiklikleri       | Serbest bırakma yok             | `style: swiftformat ile kodu biçimlendir`             |
| `refactor`   | Kod yeniden düzenleme          | Serbest bırakma yok             | `refactor(server): auth mantığını basitleştirin`      |
| `mükemmel`   | Performans iyileştirmeleri     | Yama sürümü yükseltme           | `perf(CLI): bağımlılık çözümlemesini optimize eder`   |
| `test`       | Test eklemeleri/değişiklikleri | Serbest bırakma yok             | `test: önbellek için birim testleri ekleyin`          |
| `chore`      | Bakım görevleri                | Serbest bırakma yok             | `chore: bağımlılıkları güncelle`                      |
| `ci`         | CI/CD değişiklikleri           | Serbest bırakma yok             | `ci: sürümler için iş akışı ekleyin`                  |

#### Kırılma değişiklikleri

Kırıcı değişiklikler büyük sürüm artışını (X.0.0) tetikler ve commit gövdesinde
belirtilmelidir:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Değişiklik tespiti

Her bileşen [git cliff](https://git-cliff.org/) kullanır:
- Son sürümden bu yana yapılan değişiklikleri analiz edin
- İşlemleri kapsama göre filtreleme (CLI, app, server)
- Serbest bırakılabilir değişiklikler olup olmadığını belirleyin
- Değişiklik günlüklerini otomatik olarak oluşturun

### 3. Boru hattını serbest bırakın

Serbest bırakılabilir değişiklikler tespit edildiğinde:

1. **Sürüm hesaplama**: Boru hattı bir sonraki sürüm numarasını belirler
2. **Değişiklik günlüğü oluşturma**: git cliff, commit mesajlarından bir
   değişiklik günlüğü oluşturur
3. **Oluşturma süreci**: Bileşen oluşturulur ve test edilir
4. **Sürüm oluşturma**: Artifact'lar ile bir GitHub sürümü oluşturulur
5. **Dağıtım**: Güncellemeler paket yöneticilerine gönderilir (örneğin, CLI için
   Homebrew)

### 4. Kapsam filtreleme

Her bileşen yalnızca ilgili değişiklikler olduğunda yayınlanır:

- **CLI**: `(cli)` kapsamı veya kapsamı olmayan komutlar
- **Uygulama**: ` (app)` kapsamı ile commitler
- **Sunucu**: ` (sunucu)` kapsamı ile commitler

## İyi commit mesajları yazma

Taahhüt mesajları sürüm notlarını doğrudan etkilediğinden, net ve açıklayıcı
mesajlar yazmak önemlidir:

### Yap:
- Şimdiki zaman kullanın: "özellik eklendi" değil "özellik eklendi"
- Kısa ama açıklayıcı olun
- Değişiklikler bileşene özgü olduğunda kapsamı dahil edin
- Uygun olduğunda sorunlara referans verin: `fix(CLI): derleme önbelleği
  sorununu çözün (#1234)`

### Yapma:
- "Hatayı düzelt" veya "kodu güncelle" gibi belirsiz mesajlar kullanın
- Birden fazla ilgisiz değişikliği tek bir işlemde karıştırma
- Son dakika değişiklik bilgilerini eklemeyi unutun

### Kırılma değişiklikleri

Kırılma değişiklikleri için, commit gövdesine `BREAKING CHANGE:` adresini
ekleyin:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Yayın iş akışları

Sürüm iş akışları şurada tanımlanmıştır:
- `.github/workflows/cli-release.yml` - CLI sürümleri
- `.github/workflows/app-release.yml` - Uygulama sürümleri
- `.github/workflows/server-release.yml` - Sunucu sürümleri

Her iş akışı:
- Ana şebekeye itme ile çalışır
- Manuel olarak tetiklenebilir
- Değişiklik tespiti için git cliff kullanır
- Tüm sürüm sürecini yönetir

## Salımların izlenmesi

Sürümleri şu yolla izleyebilirsiniz:
- [GitHub Sürümler sayfası](https://github.com/tuist/tuist/releases)
- İş akışı çalıştırmaları için GitHub Eylemleri sekmesi
- Her bileşen dizinindeki değişiklik günlüğü dosyaları

## Avantajlar

Bu sürekli sürüm yaklaşımı şunları sağlar:

- **Hızlı teslimat**: Değişiklikler birleştirildikten hemen sonra kullanıcılara
  ulaşır
- **Azaltılmış darboğazlar**: Manuel sürümler için beklemek yok
- **Açık iletişim**: Commit mesajlarından otomatik değişiklik günlükleri
- **Tutarlı süreç**: Tüm bileşenler için aynı sürüm akışı
- **Kalite güvencesi**: Sadece test edilen değişiklikler yayınlanır

## Sorun Giderme

Serbest bırakma başarısız olursa:

1. Başarısız iş akışı için GitHub Actions günlüklerini kontrol edin
2. Taahhüt mesajlarınızın geleneksel formatı takip ettiğinden emin olun
3. Tüm testlerin geçtiğini doğrulayın
4. Bileşenin başarıyla derlendiğini kontrol edin

Hemen yayınlanması gereken acil düzeltmeler için:
1. Taahhüdünüzün net bir kapsamı olduğundan emin olun
2. Birleştirmeden sonra sürüm iş akışını izleyin
3. Gerekirse manuel serbest bırakmayı tetikleyin

## App Store sürümü

CLI ve Sunucu yukarıda açıklanan sürekli sürüm sürecini takip ederken, **iOS
uygulaması** Apple'ın App Store inceleme süreci nedeniyle bir istisnadır:

- **Manuel sürümler**: iOS uygulama sürümlerinin App Store'a manuel olarak
  gönderilmesi gerekir
- **İnceleme gecikmeleri**: Her sürüm Apple'ın inceleme sürecinden geçmelidir ve
  bu süreç 1-7 gün sürebilir
- **Toplu değişiklikler**: Her iOS sürümünde genellikle birden fazla değişiklik
  bir araya getirilir
- **TestFlight**: Beta sürümleri App Store'da yayınlanmadan önce TestFlight
  aracılığıyla dağıtılabilir
- **Sürüm notları**: App Store yönergeleri için özel olarak yazılmalıdır

iOS uygulaması hala aynı commit kurallarını takip ediyor ve değişiklik günlüğü
oluşturmak için git cliff kullanıyor, ancak kullanıcılara gerçek sürüm daha az
sıklıkta, manuel bir programda gerçekleşiyor.
