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
-  tarafından oluşturulan bir projele
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve projesi</LocalizedLink>
<!-- -->
:::

Tuist Modül önbelleği, modüllerinizi ikili dosyalar (`.xcframework`s) olarak
önbelleğe alarak ve bunları farklı ortamlarda paylaşarak derleme sürelerinizi
optimize etmek için güçlü bir yol sağlar. Bu özellik, önceden oluşturulmuş ikili
dosyaları kullanmanıza olanak tanıyarak tekrarlanan derleme ihtiyacını azaltır
ve geliştirme sürecini hızlandırır.

## Isınma {#warming}

Tuist, değişiklikleri tespit etmek için bağımlılık grafiğindeki her hedef için
verimli bir şekilde <LocalizedLink href="/guides/features/projects/hashing"> hash</LocalizedLink> kullanır. Bu verileri kullanarak, bu hedeflerden türetilen
ikililere benzersiz tanımlayıcılar oluşturur ve atar. Tuist, grafik oluşturma
sırasında, orijinal hedefleri karşılık gelen ikili sürümleriyle sorunsuz bir
şekilde değiştirir.

*"ısıtma" olarak bilinen bu işlem,* yerel kullanım için veya Tuist aracılığıyla
ekip arkadaşları ve CI ortamlarıyla paylaşmak için ikili dosyalar üretir.
Önbelleği ısıtma işlemi basittir ve basit bir komutla başlatılabilir:


```bash
tuist cache
```

Komut, süreci hızlandırmak için ikili dosyaları yeniden kullanır.

## Kullanım {#usage}

Varsayılan olarak, Tuist komutları proje oluşturmayı gerektirdiğinde, varsa,
bağımlılıkları otomatik olarak önbellekteki ikili eşdeğerleriyle değiştirir. Ek
olarak, odaklanılacak hedeflerin bir listesini belirtirseniz, Tuist, mevcut
olmaları koşuluyla, bağımlı hedefleri önbellekteki ikili dosyalarıyla da
değiştirecektir. Farklı bir yaklaşımı tercih edenler için, belirli bir bayrak
kullanarak bu davranışı tamamen devre dışı bırakma seçeneği vardır:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: warning
<!-- -->
İkili önbelleğe alma, uygulamayı bir simülatörde veya cihazda çalıştırmak ya da
testler yapmak gibi geliştirme iş akışları için tasarlanmış bir özelliktir.
Sürüm derlemeleri için tasarlanmamıştır. Uygulamayı arşivlerken,
`--no-binary-cache` bayrağını kullanarak kaynakları içeren bir proje oluşturun.
<!-- -->
:::

## Önbellek profilleri {#cache-profiles}

Tuist, oluşturulmuş projele'de agresif hedeflerin önbelleğe alınmış ikili
dosyalarla nasıl değiştirileceğini kontrol etmek için önbellek profillerini
destekler.

- Ankastre:
  - `only-external`: sadece harici bağımlılıkları değiştir (sistem varsayılanı)
  - `all-possible`: mümkün olduğunca çok hedefi değiştirin (dahili hedefler
    dahil)
  - `none`: asla önbelleğe alınmış ikili dosyalarla değiştirmeyin

`--cache-profile` ile `tuist generate` üzerinde bir profil seçin:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely (backwards compatible)
tuist generate --no-binary-cache  # equivalent to --cache-profile none
```

Etkili davranışı çözerken öncelik (en yüksekten en düşüğe):

1. `--no-binary-cache` → profile `none`
2. Hedef odağı (hedefleri `'a geçirmek` oluşturur) → profil `mümkün olan her
   şey`
3. `--cache-profile `
4. Varsayılan yapılandırma (ayarlanmışsa)
5. Sistem varsayılanı (`only-external`)

## Desteklenen ürünler {#supported-products}

Sadece aşağıdaki hedef ürünler Tuist tarafından önbelleğe alınabilir:

- XCTest](https://developer.apple.com/documentation/xctest)'e bağlı olmayan
  çerçeveler (statik ve dinamik)
- Paketler
- Swift Makroları

XCTest'e bağlı olan kütüphaneleri ve hedefleri desteklemek için çalışıyoruz.

::: info UPSTREAM DEPENDENCIES
<!-- -->
Bir hedef önbelleklenemez olduğunda, yukarı akış hedefleri de önbelleklenemez
hale gelir. Örneğin, A'nın B'ye bağlı olduğu `A &gt; B` bağımlılık grafiğine
sahipseniz, B önbelleğe alınamazsa, A da önbelleğe alınamaz olacaktır.
<!-- -->
:::

## Verimlilik {#efficiency}

İkili önbellekleme ile elde edilebilecek verimlilik seviyesi büyük ölçüde grafik
yapısına bağlıdır. En iyi sonuçları elde etmek için aşağıdakileri öneriyoruz:

1. Çok iç içe geçmiş bağımlılık grafiklerinden kaçının. Grafik ne kadar sığ
   olursa o kadar iyidir.
2. Uygulama hedefleri yerine protokol/arayüz hedefleri ile bağımlılıkları
   tanımlayın ve en üst hedeflerden bağımlılık enjekte uygulamalarını kullanın.
3. Sık değiştirilen hedefleri, değişme olasılığı daha düşük olan daha küçük
   hedeflere bölün.

Yukarıdaki öneriler, yalnızca ikili önbelleğe almanın değil, aynı zamanda
Xcode'un yeteneklerinin de faydalarını en üst düzeye çıkarmak için projelerinizi
yapılandırmanın bir yolu olarak önerdiğimiz
<LocalizedLink href="/guides/features/projects/tma-architecture"> Modüler Mimarinin</LocalizedLink> bir parçasıdır.

## Önerilen kurulum {#recommended-setup}

Önbelleği ısıtmak için **ana** dalındaki her işlemde çalışan bir CI işine sahip
olmanızı öneririz. Bu, önbelleğin her zaman `ana` 'daki değişiklikler için ikili
dosyalar içermesini sağlayacaktır, böylece yerel ve CI şubesi bunlar üzerinde
artımlı olarak derlenir.

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` komutu da ısınmayı hızlandırmak için ikili önbellekten yararlanır.
<!-- -->
:::

Aşağıda yaygın iş akışlarına bazı örnekler verilmiştir:

### Bir geliştirici yeni bir özellik üzerinde çalışmaya başlar {#a-developer-starts-to-work-on-a-new-feature}

1. `ana` adresinden yeni bir şube oluştururlar.
2. `tuist'i çalıştırarak` adresini oluştururlar.
3. Tuist, `ana` adresinden en son ikili dosyaları çeker ve projeyi bunlarla
   oluşturur.

### Bir geliştirici değişiklikleri yukarı akışa gönderir {#a-developer-pushes-changes-upstream}

1. CI boru hattı, projeyi derlemek veya test etmek için `xcodebuild build` veya
   `tuist test` çalıştıracaktır.
2. İş akışı, `ana` adresinden en son ikili dosyaları çekecek ve projeyi bunlarla
   oluşturacaktır.
3. Daha sonra projeyi aşamalı olarak oluşturacak veya test edecektir.

## Konfigürasyon {#configuration}

### Önbellek eşzamanlılık sınırı {#cache-concurrency-limit}

Varsayılan olarak, Tuist önbellek eserlerini herhangi bir eşzamanlılık sınırı
olmadan indirir ve yükler, böylece verimi en üst düzeye çıkarır. Bu davranışı
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

Bu, sınırlı ağ bant genişliğine sahip ortamlarda veya önbellek işlemleri
sırasında sistem yükünü azaltmak için yararlı olabilir.

## Sorun Giderme {#troubleshooting}

### Hedeflerim için ikili dosyalar kullanmıyor {#it-doesnt-use-binaries-for-my-targets}

hash'lerin ortamlar ve çalıştırmalar arasında deterministik
olduğundan emin olun. Bu durum, örneğin mutlak yollar aracılığıyla projenin
ortama referansları varsa ortaya çıkabilir. ` tuist generate` komutunun iki
ardışık çağrısı tarafından veya ortamlar ya da çalıştırmalar arasında
oluşturulan projeleri karşılaştırmak için `diff` komutunu kullanabilirsiniz.

Ayrıca hedefin doğrudan ya da dolaylı olarak
<LocalizedLink href="/guides/features/cache/generated-project#supported-products">önbelleğe alınamayan hedefe</LocalizedLink> bağlı olmadığından emin olun.

### Eksik semboller {#missing-symbols}

Kaynakları kullanırken, Xcode'un derleme sistemi, Türetilmiş Veriler
aracılığıyla, açıkça bildirilmeyen bağımlılıkları çözebilir. Ancak, ikili
önbelleğe güvendiğinizde, bağımlılıklar açıkça bildirilmelidir; aksi takdirde,
semboller bulunamadığında derleme hataları görmeniz muhtemeldir. Bu hatayı
ayıklamak için,
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect implicit-imports`</LocalizedLink> komutunu kullanmanızı ve örtük
bağlamadaki gerilemeleri önlemek için CI'da ayarlamanızı öneririz.
