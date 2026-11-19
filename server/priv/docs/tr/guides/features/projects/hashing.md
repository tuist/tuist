---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist hashing'in ikili önbellekleme ve seçici testi nasıl desteklediği."
}
---
# Hashing {#hashing}

<.localized_link href="/guides/features/cache">Önbellekleme</.localized_link> veya seçici test çalıştırma gibi özellikler, bir hedefin değişip değişmediğini belirlemek için bir yol gerektirir. Tuist, bir hedefin değişip değişmediğini belirlemek amacıyla bağımlılık grafiğindeki her hedef için bir hash hesaplar. Hash aşağıdaki özniteliklere göre hesaplanır:

- Hedefin öznitelikleri (örneğin ad, platform, ürün vb.)
- Hedefin dosyaları
- Hedefin bağımlılıklarının hash değeri

## Önbellek öznitelikleri {#cache-attributes}

Ek olarak, <.localized_link href="/guides/features/cache">önbellekleme</.localized_link> için hash hesaplanırken aşağıdaki öznitelikler de hashlenir.

### Swift sürümü {#swift-version}

Hedefler ve ikili dosyalar arasında Swift sürümü uyumsuzluklarından kaynaklanan derleme hatalarını önlemek için `/usr/bin/xcrun swift --version` komutunu çalıştırarak elde edilen Swift sürümünü hashleriz.

> [!NOTE]
> **Modül kararlılığı**
>
> İkili önbellekleme'nin önceki sürümleri, [modül kararlılığını](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support) etkinleştirmek ve ikililerin herhangi bir derleyici sürümüyle kullanılmasını sağlamak için `BUILD_LIBRARY_FOR_DISTRIBUTION` yapılandırma ayarına güveniyordu. Ancak bu durum, modül kararlılığını desteklemeyen hedeflere sahip projelerde derleme sorunlarına neden oluyordu. Oluşturulan ikililer, bunları derlemek için kullanılan Swift sürümüne bağlıdır ve Swift sürümünün projeyi derlemek için kullanılan sürümle eşleşmesi gerekir.


### Yapılandırma {#configuration}

Önbellek hashlerini hesaplarken Tuist, her projenin ve hedefin ayarlarını çözümlenen derleme yapılandırmasına göre kapsar. Bu, `--configuration` ile adlandırılan yapılandırmadır; aksi takdirde projenin `defaultConfiguration` değeri, o da yoksa ilk hata ayıklama yapılandırması kullanılır. Tuist, bu yapılandırmanın adını, varyantını, derleme ayarlarını ve yapılandırma dosyası içeriğini, ona uygulanan paylaşılan temel ayarlarla birlikte hashler. Başka bir yapılandırma eklemek, kaldırmak veya değiştirmek, çözümlenen yapılandırmanın önbellek hashlerini etkilemez. Yalnızca çözümlenen yapılandırma önemli olduğundan, açık bir `--configuration` ile doldurulan bir önbellek, bayrağı geçmeden aynı yapılandırmaya çözümlenen bir komut tarafından okunabilir.

## Hata ayıklama {#debugging}

Önbellekleme'yi farklı ortamlarda veya çağrılarda kullanırken deterministik olmayan davranışlar fark ederseniz, bu durum ortamlar arasındaki farklılıklardan veya hashleme mantığında bir hatadan kaynaklanıyor olabilir. Sorunu hata ayıklamak için şu adımları izlemenizi öneririz:

1. `tuist hash cache` veya `tuist hash selective-testing` komutunu çalıştırın (<.localized_link href="/guides/features/cache">ikili önbellekleme</.localized_link> veya <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link> için hashler), hashleri kopyalayın, proje dizinini yeniden adlandırın ve komutu tekrar çalıştırın. Hashler eşleşmelidir.
2. Hashler eşleşmiyorsa, oluşturulan projenin ortama bağlı olması muhtemeldir. Her iki durumda da `tuist graph --format json` komutunu çalıştırın ve grafikleri karşılaştırın. Alternatif olarak, projeleri oluşturun ve [Diffchecker](https://www.diffchecker.com) gibi bir diff aracıyla `project.pbxproj` dosyalarını karşılaştırın.
3. Hashler aynıysa ancak ortamlar arasında farklılık gösteriyorsa (örneğin CI ve yerel ortam), her yerde aynı [yapılandırma](#configuration) ve [Swift sürümü](#swift-version)nün kullanıldığından emin olun. Swift sürümü Xcode sürümüne bağlıdır, bu nedenle Xcode sürümlerinin eşleştiğini doğrulayın.

Hashler hala deterministik değilse bize bildirin, hata ayıklama sürecinde size yardımcı olabiliriz.


> [!NOTE]
> **Daha iyi hata ayıklama deneyimi planlanıyor**
>
> Hata ayıklama deneyimimizi iyileştirmek yol haritamızda yer alıyor. Farklılıkları anlamak için bağlamdan yoksun olan print-hashes komutu, hashler arasındaki farkları ağaç benzeri bir yapı kullanarak gösteren daha kullanıcı dostu bir komutla değiştirilecek.
