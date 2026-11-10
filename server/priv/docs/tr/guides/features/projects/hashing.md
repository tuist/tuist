---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist hashing'in ikili önbellekleme ve seçici testi nasıl desteklediği."
}
---
# Hashing {#hashing}

<.localized_link href="/guides/features/cache">Önbellekleme</.localized_link> veya seçici test yürütme gibi özellikler, bir hedefin değişip değişmediğini belirlemek için bir yol gerektirir. Tuist, bağımlılık grafiğindeki her hedef için bir karma değer hesaplayarak hedefin değişip değişmediğini belirler. Karma değer aşağıdaki özniteliklere göre hesaplanır:

- Hedefin öznitelikleri (örneğin ad, platform, ürün vb.)
- Hedefin dosyaları
- Hedefin bağımlılıklarının karma değeri

## Önbellek öznitelikleri {#cache-attributes}

Ek olarak, <.localized_link href="/guides/features/cache">önbellekleme</.localized_link> için karma değer hesaplarken aşağıdaki öznitelikleri de hash'leriz.

### Swift sürümü {#swift-version}

Hedefler ve ikili dosyalar arasında Swift sürümü uyumsuzluklarından kaynaklanan derleme hatalarını önlemek için `/usr/bin/xcrun swift --version` komutunu çalıştırarak elde edilen Swift sürümünü hash'leriz.

> [!NOTE]
> **Modül kararlılığı**
>
> Binary önbellekleme özelliğinin önceki sürümleri, [modül kararlılığını](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support) etkinleştirmek ve ikili dosyaların herhangi bir derleyici sürümüyle kullanılmasını sağlamak için `BUILD_LIBRARY_FOR_DISTRIBUTION` yapılandırma ayarına güveniyordu. Ancak bu durum, modül kararlılığını desteklemeyen hedefler içeren projelerde derleme sorunlarına yol açıyordu. Oluşturulan ikili dosyalar, bunları derlemek için kullanılan Swift sürümüne bağlıdır ve Swift sürümünün projeyi derlemek için kullanılan sürümle eşleşmesi gerekir.


### Yapılandırma {#configuration}

Önbellek karma değerlerini hesaplarken Tuist, her projenin ve hedefin ayarlarını çözümlenen yapı yapılandırmasına göre kapsar. Bu, `--configuration` ile adlandırılan yapılandırmadır; aksi takdirde projenin `defaultConfiguration` yapılandırması, yoksa ilk hata ayıklama yapılandırması kullanılır. Tuist, bu yapılandırmanın adını, varyantını, yapı ayarlarını ve yapılandırma dosyası içeriğini, ona uygulanan paylaşılan temel ayarlarla birlikte hash'ler. Başka bir yapılandırma eklemek, kaldırmak veya değiştirmek çözümlenen yapılandırmanın önbellek karma değerlerini etkilemez. Yalnızca çözümlenen yapılandırma önemli olduğundan, açık bir `--configuration` ile doldurulan bir önbellek, bayrağı geçmeden aynı yapılandırmaya çözümlenen bir komut tarafından okunabilir.

## Hata ayıklama {#debugging}

Farklı ortamlarda veya çağrılarda önbellekleme kullanırken deterministik olmayan davranışlar fark ederseniz, bu durum ortamlar arasındaki farklılıklardan veya hash mantığında bir hatadan kaynaklanıyor olabilir. Sorunu hata ayıklamak için şu adımları izlemenizi öneririz:

1. `tuist hash cache` veya `tuist hash selective-testing` (<.localized_link href="/guides/features/cache">ikili önbellekleme</.localized_link> veya <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link> için karma değerler) komutunu çalıştırın, karma değerleri kopyalayın, proje dizinini yeniden adlandırın ve komutu tekrar çalıştırın. Karma değerler eşleşmelidir.
2. Karmalar eşleşmiyorsa, oluşturulan projenin ortama bağlı olması muhtemeldir. Her iki durumda da `tuist graph --format json` komutunu çalıştırın ve grafikleri karşılaştırın. Alternatif olarak, projeleri oluşturun ve [Diffchecker](https://www.diffchecker.com) gibi bir fark karşılaştırma aracıyla `project.pbxproj` dosyalarını karşılaştırın.
3. Karma değerler aynıysa ancak ortamlar arasında farklılık gösteriyorsa (örneğin CI ve yerel ortam), her yerde aynı [yapılandırma](#configuration) ve [Swift sürümü](#swift-version)nün kullanıldığından emin olun. Swift sürümü Xcode sürümüne bağlıdır, bu nedenle Xcode sürümlerinin eşleştiğini doğrulayın.

Karma değerler hâlâ deterministik değilse bize bildirin, hata ayıklama konusunda yardımcı olabiliriz.


> [!NOTE]
> **Daha iyi hata ayıklama deneyimi planlanıyor**
>
> Hata ayıklama deneyimimizi iyileştirmek yol haritamızda yer alıyor. Farklılıkları anlamak için bağlamdan yoksun olan print-hashes komutunun yerine, karma değerler arasındaki farkları ağaç benzeri bir yapı kullanarak gösteren daha kullanıcı dostu bir komut gelecektir.
