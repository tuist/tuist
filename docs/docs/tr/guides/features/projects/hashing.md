---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# Hashing {#hashing}

<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> veya seçici test yürütme gibi özellikler, bir hedefin
değişip değişmediğini belirlemenin bir yolunu gerektirir. Tuist, bir hedefin
değişip değişmediğini belirlemek için bağımlılık grafiğindeki her hedef için bir
hash hesaplar. Hash, aşağıdaki özniteliklere göre hesaplanır:

- Hedefin özellikleri (ör. isim, platform, ürün, vb.)
- Hedefin dosyaları
- Hedefin bağımlılıklarının hash'i

### Önbellek öznitelikleri {#cache-attributes}

Ek olarak, <LocalizedLink href="/guides/features/cache">caching</LocalizedLink>
için hash hesaplarken aşağıdaki öznitelikleri de hashleriz.

#### Hızlı versiyon {#swift-version}

Hedefler ve ikili dosyalar arasındaki Swift sürüm uyuşmazlıklarından kaynaklanan
derleme hatalarını önlemek için `/usr/bin/xcrun swift --version` komutunu
çalıştırarak elde edilen Swift sürümünü hash ediyoruz.

::: info MODULE STABILITY
<!-- -->
İkili önbelleğe almanın önceki sürümleri, [modül
kararlılığını](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)
etkinleştirmek ve herhangi bir derleyici sürümüyle ikili dosyaları kullanmayı
sağlamak için `BUILD_LIBRARY_FOR_DISTRIBUTION` derleme ayarına dayanıyordu.
Ancak, modül kararlılığını desteklemeyen hedeflere sahip projelerde derleme
sorunlarına neden oldu. Oluşturulan ikili dosyalar, onları derlemek için
kullanılan Swift sürümüne bağlıdır ve Swift sürümü, projeyi derlemek için
kullanılan sürümle eşleşmelidir.
<!-- -->
:::

#### Konfigürasyon {#configuration}

`-configuration` bayrağının arkasındaki fikir, hata ayıklama ikili dosyalarının
sürüm derlemelerinde kullanılmamasını ve bunun tersini sağlamaktı. Ancak,
kullanılmalarını önlemek için diğer yapılandırmaları projelerden kaldırmak için
hala bir mekanizma eksik.

## Hata Ayıklama {#debugging}

Ortamlar veya çağrılar arasında önbelleğe almayı kullanırken deterministik
olmayan davranışlar fark ederseniz, bu durum ortamlar arasındaki farklılıklarla
veya karma mantığındaki bir hatayla ilgili olabilir. Sorunu ayıklamak için
aşağıdaki adımları izlemenizi öneririz:

1. `tuist hash cache` veya `tuist hash selective-testing`
   (<LocalizedLink href="/guides/features/cache">binary caching</LocalizedLink>
   veya <LocalizedLink href="/guides/features/selective-testing">seçmeli test</LocalizedLink> için hashler) komutunu çalıştırın, hashleri kopyalayın,
   proje dizinini yeniden adlandırın ve komutu tekrar çalıştırın. Hash'ler
   eşleşmelidir.
2. Hash'ler eşleşmiyorsa, oluşturulmuş projele'nin ortama bağlı olması
   muhtemeldir. Her iki durumda da `tuist graph --format json` çalıştırın ve
   grafikleri karşılaştırın. Alternatif olarak, projeleri oluşturun ve
   `project.pbxproj` dosyalarını [Diffchecker](https://www.diffchecker.com) gibi
   bir fark aracı ile karşılaştırın.
3. Karmalar aynıysa ancak ortamlar arasında farklılık gösteriyorsa (örneğin, CI
   ve yerel), her yerde aynı [yapılandırma](#configuration) ve [Swift
   sürümü](#swift-version) kullanıldığından emin olun. Swift sürümü Xcode
   sürümüne bağlıdır, bu nedenle Xcode sürümlerinin eşleştiğini doğrulayın.

Hash'ler hala deterministik değilse, bize bildirin ve hata ayıklama konusunda
yardımcı olabiliriz.


::: info BETTER DEBUGGING EXPERIENCE PLANNED
<!-- -->
Hata ayıklama deneyimimizi iyileştirmek yol haritamızda yer alıyor. Farkları
anlamak için bağlamdan yoksun olan print-hashes komutu, hash'ler arasındaki
farkları göstermek için ağaç benzeri bir yapı kullanan daha kullanıcı dostu bir
komutla değiştirilecektir.
<!-- -->
:::
