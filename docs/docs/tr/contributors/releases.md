---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# Sürümler

Tuist, anlamlı değişiklikler ana dala birleştirildiğinde yeni sürümleri otomatik
olarak yayınlayan sürekli bir sürüm sistemini kullanır. Bu yaklaşım,
bakımcıların manuel müdahalesi olmadan iyileştirmelerin kullanıcılara hızlı bir
şekilde ulaşmasını sağlar.

## Genel bakış

Üç ana bileşeni sürekli olarak yayınlıyoruz:
- **Tuist CLI** - CLI aracı
- **Tuist Sunucusu** - Arka uç hizmetleri
- **Tuist Uygulaması** - macOS ve iOS uygulamaları (iOS uygulaması yalnızca
  TestFlight'a sürekli olarak dağıtılır, daha fazla bilgi için [buraya] bakın
  (#app-store-release)

Her bileşen, ana dala her itme işleminde otomatik olarak çalışan kendi sürüm
boru hattına sahiptir.

## Nasıl çalışır?

### 1. Kurallara uyun

Commit mesajlarımızı yapılandırmak için [Conventional
Commits](https://www.conventionalcommits.org/) kullanıyoruz. Bu, araçlarımızın
değişikliklerin niteliğini anlamasına, sürüm artışlarını belirlemesine ve uygun
değişiklik günlükleri oluşturmasına olanak tanır.

Biçim: `tür(kapsam): açıklama`

#### Commit türleri ve etkileri

| Yazın                | Açıklama                       | Sürüm Etkisi                    | Örnekler                                                     |
| -------------------- | ------------------------------ | ------------------------------- | ------------------------------------------------------------ |
| `feat`               | Yeni özellik veya yetenek      | Küçük sürüm yükseltmesi (x.Y.z) | `feat(CLI): Swift 6 desteği ekleyin`                         |
| `düzelt`             | Hata düzeltme                  | Yama sürümü yükseltmesi (x.y.Z) | `fix(app): projeleri açarken yaşanan çökme sorunu çözüldü`   |
| `docs`               | Dokümantasyon değişiklikleri   | Yayın yok                       | `docs: kurulum kılavuzunu güncelle`                          |
| `stil`               | Kod stili değişiklikleri       | Yayın yok                       | `stil: swiftformat ile kod biçimlendirme`                    |
| `yeniden düzenleyin` | Kod yeniden düzenleme          | Yayın yok                       | `refactor(sunucu): kimlik doğrulama mantığını basitleştirin` |
| `perf`               | Performans iyileştirmeleri     | Yama sürümü yükseltmesi         | `perf(CLI): bağımlılık çözümünü optimize edin`               |
| `test`               | Test eklemeleri/değişiklikleri | Yayın yok                       | `test: önbellek için birim testleri ekleyin`                 |
| `chore`              | Bakım görevleri                | Yayın yok                       | `görev: bağımlılıkları güncelle`                             |
| `ci`                 | CI/CD değişiklikleri           | Yayın yok                       | `ci: sürümler için iş akışı ekleyin`                         |

#### Önemli değişiklikler

Önemli değişiklikler, ana sürümde büyük bir değişiklik (X.0.0) tetikler ve
commit gövdesinde belirtilmelidir:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Değişiklik algılama

Her bileşen [git cliff](https://git-cliff.org/) kullanarak şunları yapar:
- Son sürümden bu yana yapılan işlemleri analiz edin
- Kapsama göre taahhütleri filtreleyin (CLI, app, server)
- Yayınlanabilir değişiklikler olup olmadığını belirleyin.
- Değişiklik günlüklerini otomatik olarak oluşturun

### 3. Yayınlama süreci

Yayınlanabilir değişiklikler tespit edildiğinde:

1. **Sürüm hesaplama**: Boru hattı bir sonraki sürüm numarasını belirler.
2. **Değişiklik günlüğü oluşturma**: git cliff, commit mesajlarından bir
   değişiklik günlüğü oluşturur.
3. **Oluşturma süreci**: Bileşen oluşturulur ve test edilir.
4. **Sürüm oluşturma**: GitHub sürümü, artefaktlarla birlikte oluşturulur.
5. **Dağıtım**: Güncellemeler paket yöneticilerine (ör. CLI için Homebrew)
   gönderilir.

### 4. Kapsam filtreleme

Her bileşen, yalnızca ilgili değişiklikler olduğunda yayınlanır:

- **CLI**: `(CLI) ile commit yapar.` scope veya no scope
- **Uygulama**: `(app)` scope ile yapılan işlemler
- **Sunucu**: `(sunucu) ile taahhütler` kapsamı

## İyi commit mesajları yazma

Commit mesajları sürüm notlarını doğrudan etkilediğinden, açık ve açıklayıcı
mesajlar yazmak önemlidir:

### Yapılması gerekenler:
- Şimdiki zaman kullanın: "özellik ekle" değil, "özellik eklendi"
- Kısa ve öz, ancak açıklayıcı olun.
- Değişiklikler bileşene özgü ise kapsamı da ekleyin.
- Uygun olduğunda referans sorunları: `düzeltme (CLI): derleme önbelleği
  sorununu çözme (#1234)`

### Yapmamanız gerekenler:
- "Hata düzeltme" veya "kod güncelleme" gibi belirsiz mesajlar kullanın.
- Birden fazla ilgisiz değişikliği tek bir işlemde birleştirin
- Önemli değişiklik bilgilerini eklemeyi unutmayın.

### Önemli değişiklikler

Önemli değişiklikler için, `BREAKING CHANGE:` ifadesini commit gövdesine
ekleyin:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Yayın iş akışları

Yayın iş akışları şu şekilde tanımlanmıştır:
- `.github/workflows/cli-release.yml` - CLI sürümleri
- `.github/workflows/app-release.yml` - Uygulama sürümleri
- `.github/workflows/server-release.yml` - Sunucu sürümleri

Her iş akışı:
- Ana sayfaya gönderildiğinde çalışır.
- Manuel olarak tetiklenebilir
- Değişiklik tespiti için git cliff kullanır.
- Tüm yayın sürecini yönetir.

## Sürümleri izleme

Sürümleri şu şekilde takip edebilirsiniz:
- [GitHub Sürümleri sayfası](https://github.com/tuist/tuist/releases)
- İş akışı çalıştırmaları için GitHub Actions sekmesi
- Her bileşen dizinindeki değişiklik günlüğü dosyaları

## Avantajlar

Bu sürekli sürüm yaklaşımı şunları sağlar:

- **Hızlı teslimat**: Değişiklikler birleştirildikten hemen sonra kullanıcılara
  ulaşır.
- ****'da darboğazlar azaltıldı: Manuel sürümler için beklemek gerekmiyor
- **Net iletişim**: Commit mesajlarından otomatik değişiklik günlükleri
- **Tutarlı süreç**: Tüm bileşenler için aynı sürüm akışı
- **Kalite güvencesi**: Yalnızca test edilmiş değişiklikler yayınlanır.

## Sorun Giderme

Sürüm başarısız olursa:

1. Başarısız iş akışını GitHub Actions günlüklerinde kontrol edin.
2. Commit mesajlarınızın geleneksel biçimi izlediğinden emin olun.
3. Tüm testlerin başarılı olduğunu doğrulayın.
4. Bileşenin başarıyla oluşturulduğunu kontrol edin.

Acil olarak yayınlanması gereken acil düzeltmeler için:
1. Commit'inizin kapsamının net olduğundan emin olun.
2. Birleştirme işleminden sonra, yayın iş akışını izleyin.
3. Gerekirse, manuel yayınlamayı başlatın.

## App Store sürümü

CLI ve Sunucu yukarıda açıklanan sürekli sürüm sürecini izlerken, **iOS
uygulaması** Apple'ın App Store inceleme süreci nedeniyle bir istisnadır:

- **Manuel sürümler**: iOS uygulama sürümleri, App Store'a manuel olarak
  gönderilmelidir.
- **İnceleme gecikmeleri**: Her sürüm, 1-7 gün sürebilen Apple'ın inceleme
  sürecinden geçmelidir.
- **Toplu değişiklikler**: Birden fazla değişiklik genellikle her iOS sürümünde
  bir araya getirilir.
- **TestFlight**: Beta sürümleri, App Store'da yayınlanmadan önce TestFlight
  aracılığıyla dağıtılabilir.
- **Sürüm notları**: App Store yönergeleri için özel olarak yazılmalıdır.

iOS uygulaması hala aynı commit kurallarına uymakta ve değişiklik günlüğü
oluşturmak için git cliff kullanmaktadır, ancak kullanıcılara sunulan gerçek
sürümler daha seyrek ve manuel bir programla yayınlanmaktadır.
