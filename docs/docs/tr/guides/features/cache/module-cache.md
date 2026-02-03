---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# Modül önbelleği {#module-cache}

::: warning REQUIREMENTS
<!-- -->
- 1} tarafından oluşturulan bir projele</LocalizedLink>
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
  projesi</LocalizedLink>
<!-- -->
:::

Tuist Modül önbelleği, modüllerinizi ikili dosyalar (`.xcframework`s) olarak
önbelleğe alarak ve farklı ortamlarda paylaşarak derleme sürelerinizi optimize
etmenin güçlü bir yolunu sunar. Bu özellik, önceden oluşturulmuş ikili
dosyalardan yararlanmanıza olanak tanıyarak, tekrarlı derleme ihtiyacını azaltır
ve geliştirme sürecini hızlandırır.

## Isınma {#warming}

Tuist, bağımlılık grafiğindeki her hedef için değişiklikleri tespit etmek üzere
<LocalizedLink href="/guides/features/projects/hashing">hash'leri</LocalizedLink>
verimli bir şekilde kullanır. Bu verileri kullanarak, bu hedeflerden türetilen
ikili dosyalara benzersiz tanımlayıcılar oluşturur ve atar. Grafik
oluşturulurken Tuist, orijinal hedefleri karşılık gelen ikili sürümleriyle
sorunsuz bir şekilde değiştirir.

*"warming" olarak bilinen bu işlem,* yerel kullanım veya Tuist aracılığıyla
takım arkadaşları ve CI ortamlarıyla paylaşım için ikili dosyalar üretir.
Önbelleği ısıtma işlemi basittir ve basit bir komutla başlatılabilir:


```bash
tuist cache
```

Komut, işlemi hızlandırmak için ikili dosyaları yeniden kullanır.

## Kullanım {#usage}

Varsayılan olarak, Tuist komutları proje oluşturmayı gerektirdiğinde, varsa
bağımlılıkları otomatik olarak önbellekten ikili eşdeğerleriyle değiştirir.
Ayrıca, odaklanılacak hedeflerin bir listesini belirtirseniz, Tuist, varsa
bağımlı hedefleri de önbellekteki ikili dosyalarla değiştirir. Farklı bir
yaklaşımı tercih edenler için, belirli bir bayrak kullanarak bu davranışı
tamamen devre dışı bırakma seçeneği vardır:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: warning
<!-- -->
İkili önbellekleme, uygulamayı simülatörde veya cihazda çalıştırma ya da testler
yapma gibi geliştirme iş akışları için tasarlanmış bir özelliktir. Sürüm
derlemeleri için tasarlanmamıştır. Uygulamayı arşivlerken, `--cache-profile
none` komutunu kullanarak kaynaklarla bir proje oluşturun.
<!-- -->
:::

## Önbellek profilleri {#cache-profiles}

Tuist, projeler oluşturulurken hedeflerin önbelleğe alınmış ikili dosyalarla ne
kadar agresif bir şekilde değiştirileceğini kontrol etmek için önbellek
profillerini destekler.

- Yerleşik öğeler:
  - `only-external`: yalnızca harici bağımlılıkları değiştir (sistem
    varsayılanı)
  - `all-possible`: mümkün olduğunca çok sayıda hedefi (dahili hedefler dahil)
    değiştirin.
  - `yok`: önbelleğe alınmış ikili dosyalarla asla değiştirmeyin

`--cache-profile` ile bir profil seçin `tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

::: info DEPRECATED FLAG
<!-- -->
`--no-binary-cache` bayrağı kullanımdan kaldırılmıştır. Bunun yerine
`--cache-profile none` kullanın. Kullanımdan kaldırılan bayrak, geriye dönük
uyumluluk için hala çalışmaktadır.
<!-- -->
:::

Etkili davranışı belirlerken öncelik sırası (en yüksekten en düşüğe):

1. `--cache-profile none`
2. Hedef odak ( `'e hedefleri aktararak` oluşturmak) → profil `tüm olasılıklar`
3. `--cache-profile `
4. Varsayılan yapılandırma (ayarlanmışsa)
5. Sistem varsayılanı (`only-external`)

## Desteklenen ürünler {#supported-products}

Tuist tarafından yalnızca aşağıdaki hedef ürünler önbelleğe alınabilir:

- [XCTest](https://developer.apple.com/documentation/xctest)'e bağlı olmayan
  çerçeveler (statik ve dinamik)
- Paketler
- Swift Makroları

XCTest'e bağlı kütüphaneleri ve hedefleri desteklemek için çalışıyoruz.

::: info UPSTREAM DEPENDENCIES
<!-- -->
Hedef önbelleğe alınamıyorsa, yukarı akış hedefleri de önbelleğe alınamaz hale
gelir. Örneğin, bağımlılık grafiği `A &gt; B` şeklindeyse ve A, B'ye bağımlıysa,
B önbelleğe alınamıyorsa A da önbelleğe alınamaz.
<!-- -->
:::

## Verimlilik {#efficiency}

İkili önbellekleme ile elde edilebilecek verimlilik düzeyi, grafik yapısına
büyük ölçüde bağlıdır. En iyi sonuçları elde etmek için aşağıdakileri öneririz:

1. Çok iç içe geçmiş bağımlılık grafiklerinden kaçının. Grafik ne kadar sığ
   olursa o kadar iyidir.
2. Bağımlılıkları, uygulama hedefleri yerine protokol/arayüz hedefleriyle
   tanımlayın ve en üstteki hedeflerden bağımlılık enjeksiyonu uygulamaları
   yapın.
3. Sık sık değiştirilen hedefleri, değiştirilme olasılığı daha düşük olan daha
   küçük hedeflere bölün.

Yukarıdaki öneriler, projelerinizi yapılandırarak ikili önbelleklemenin yanı
sıra Xcode'un yeteneklerinden de en iyi şekilde yararlanmanızı sağlamak için
önerdiğimiz
<LocalizedLink href="/guides/features/projects/tma-architecture">Modüler
Mimari</LocalizedLink>nin bir parçasıdır.

## Önerilen ayar {#recommended-setup}

Önbelleği ısıtmak için, ana dalda** her commit'te **tarafından çalıştırılan bir
CI işi olmasını öneririz. Bu, önbelleğin her zaman `ana` değişiklikleri için
ikili dosyaları içermesini sağlayarak, yerel ve CI dalının bunlara göre aşamalı
olarak derlenmesini sağlar.

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` komutu da ısınmayı hızlandırmak için ikili önbelleği kullanır.
<!-- -->
:::

Aşağıda, yaygın iş akışlarına ilişkin bazı örnekler verilmiştir:

### Bir geliştirici yeni bir özellik üzerinde çalışmaya başlar. {#a-developer-starts-to-work-on-a-new-feature}

1. `ana` adresinden yeni bir dal oluştururlar.
2. `tuist generate`.
3. Tuist, `ana` adresinden en son ikili dosyaları alır ve bunları kullanarak
   projeyi oluşturur.

### Bir geliştirici değişiklikleri yukarı akışa gönderir {#a-developer-pushes-changes-upstream}

1. CI boru hattı, projeyi derlemek veya test etmek iç `xcodebuild build` veya
   `tuist test` komutlarını çalıştıracaktır.
2. İş akışı, `main` adresinden en son ikili dosyaları alır ve bunları kullanarak
   projeyi oluşturur.
3. Ardından projeyi aşamalı olarak derler veya test eder.

## Konfigürasyon {#configuration}

### Önbellek eşzamanlılık sınırı {#cache-concurrency-limit}

Varsayılan olarak, Tuist herhangi bir eşzamanlılık sınırı olmaksızın önbellek
öğelerini indirir ve yükler, böylece verimi en üst düzeye çıkarır. Bu davranışı,
`TUIST_CACHE_CONCURRENCY_LIMIT` ortam değişkenini kullanarak kontrol
edebilirsiniz:

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

Bu, ağ bant genişliğinin sınırlı olduğu ortamlarda veya önbellek işlemleri
sırasında sistem yükünü azaltmak için yararlı olabilir.

## Sorun Giderme {#troubleshooting}

### Hedeflerim için ikili dosyalar kullanmıyor {#it-doesnt-use-binaries-for-my-targets}

<LocalizedLink href="/guides/features/projects/hashing#debugging">hash'lerin tüm
ortamlarda ve çalışmalarda deterministik</LocalizedLink> olduğundan emin olun.
Bu, projenin örneğin mutlak yollar aracılığıyla ortama referanslar içermesi
durumunda meydana gelebilir. `diff` komutunu kullanarak, `tuist generate`
komutunun iki ardışık çağrısıyla oluşturulan projeleri karşılaştırabilirsiniz.

Ayrıca, hedefin doğrudan veya dolaylı olarak
<LocalizedLink href="/guides/features/cache/generated-project#supported-products">önbelleğe
alınamayan hedef</LocalizedLink>'ye bağlı olmadığından emin olun.

### Eksik semboller {#missing-symbols}

Kaynakları kullanırken, Xcode'un derleme sistemi, Türetilmiş Veriler
aracılığıyla, açıkça belirtilmeyen bağımlılıkları çözebilir. Ancak, ikili
önbelleğe güvendiğinizde, bağımlılıklar açıkça belirtilmelidir; aksi takdirde,
semboller bulunamadığında derleme hatalarıyla karşılaşabilirsiniz. Bu hatayı
gidermek için,
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist
inspect dependencies --only implicit`</LocalizedLink> komutunu kullanmanızı ve
örtük bağlamada gerilemeleri önlemek için CI'da bunu ayarlamanızı öneririz.

### Eski modül önbelleği {#legacy-module-cache}

Tuist `4.128.0` sürümünde, modül önbelleği için yeni altyapımızı varsayılan
olarak belirledik. Bu yeni sürümde sorun yaşarsanız, `TUIST_LEGACY_MODULE_CACHE`
ortam değişkenini ayarlayarak eski önbellek davranışına geri dönebilirsiniz.

Bu eski modül önbelleği geçici bir yedekleme aracıdır ve gelecekteki bir
güncellemede sunucu tarafında kaldırılacaktır. Bu modülden uzaklaşmayı
planlayın.

```bash
export TUIST_LEGACY_MODULE_CACHE=1
tuist generate
```
