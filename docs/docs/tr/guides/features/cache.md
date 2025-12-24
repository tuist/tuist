---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# Önbellek {#cache}

Xcode'un derleme sistemi [artımlı
derlemeler](https://en.wikipedia.org/wiki/Incremental_build_model) sağlayarak
tek bir makinede verimliliği artırır. Ancak derleme yapıları farklı ortamlar
arasında paylaşılmaz, bu da sizi [Sürekli Entegrasyon (CI)
ortamlarınızda](https://en.wikipedia.org/wiki/Continuous_integration) veya yerel
geliştirme ortamlarınızda (Mac'inizde) aynı kodu tekrar tekrar oluşturmaya
zorlar.

Tuist, hem yerel geliştirme hem de CI ortamlarında derleme sürelerini önemli
ölçüde azaltan önbellekleme özelliği ile bu zorlukların üstesinden gelir. Bu
yaklaşım yalnızca geri bildirim döngülerini hızlandırmakla kalmaz, aynı zamanda
bağlam değiştirme ihtiyacını da en aza indirir ve sonuçta üretkenliği artırır.

İki tür önbellekleme sunuyoruz:
- <LocalizedLink href="/guides/features/cache/module-cache">Modül önbelleği</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcode önbelleği</LocalizedLink>

## Modül önbelleği {#module-cache}

Tuist'in <LocalizedLink href="/guides/features/projects">proje oluşturma</LocalizedLink> yeteneklerini kullanan projeler için, tek tek
modülleri ikili dosyalar olarak önbelleğe alan ve bunları ekibiniz ve CI
ortamlarınız arasında paylaşan güçlü bir önbellekleme sistemi sağlıyoruz.

Yeni Xcode önbelleğini de kullanabilirsiniz, ancak bu özellik şu anda yerel
derlemeler için optimize edilmiştir ve oluşturulmuş projele önbelleğine kıyasla
muhtemelen daha düşük bir önbellek isabet oranına sahip olacaksınız. Bununla
birlikte, hangi önbellekleme çözümünün kullanılacağına ilişkin karar, özel
ihtiyaçlarınıza ve tercihlerinize bağlıdır. En iyi sonuçları elde etmek için her
iki önbellekleme çözümünü de birleştirebilirsiniz.

<LocalizedLink href="/guides/features/cache/module-cache">Modül önbelleği hakkında daha fazla bilgi edinin →</LocalizedLink>

## Xcode önbelleği {#xcode-cache}

::: warning STATE OF CACHE IN XCODE
<!-- -->
Xcode önbelleği şu anda yerel artımlı derlemeler için optimize edilmiştir ve
derleme görevlerinin tamamı henüz yoldan bağımsız değildir. Yine de Tuist'in
uzak önbelleğini takarak avantajlar elde edebilirsiniz ve derleme sisteminin
kapasitesi gelişmeye devam ettikçe derleme sürelerinin de zaman içinde
iyileşmesini bekliyoruz.
<!-- -->
:::

Apple, Bazel ve Buck gibi diğer derleme sistemlerine benzer şekilde derleme
düzeyinde yeni bir önbellekleme çözümü üzerinde çalışıyor. Yeni önbellekleme
özelliği Xcode 26'dan beri mevcut ve Tuist artık Tuist'in
<LocalizedLink href="/guides/features/projects">proje oluşturma</LocalizedLink>
yeteneklerini kullanıp kullanmadığınıza bakılmaksızın sorunsuz bir şekilde
entegre oluyor.

<LocalizedLink href="/guides/features/cache/xcode-cache">Xcode önbelleği hakkında daha fazla bilgi edinin →</LocalizedLink>
