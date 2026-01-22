---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# Önbellek {#cache}

Xcode'un derleme sistemi, tek bir makinede verimliliği artıran [artımlı
derlemeler](https://en.wikipedia.org/wiki/Incremental_build_model) sağlar.
Ancak, derleme çıktıları farklı ortamlar arasında paylaşılmaz, bu da sizi aynı
kodu [Sürekli Entegrasyon (CI)
ortamlarınızda](https://en.wikipedia.org/wiki/Continuous_integration) veya yerel
geliştirme ortamlarınızda (Mac'inizde) tekrar tekrar derlemeye zorlar.

Tuist, önbellekleme özelliği ile bu zorlukları ortadan kaldırarak hem yerel
geliştirme hem de CI ortamlarında derleme sürelerini önemli ölçüde azaltır. Bu
yaklaşım, geri bildirim döngülerini hızlandırmakla kalmaz, aynı zamanda bağlam
değiştirme ihtiyacını da en aza indirerek üretkenliği artırır.

İki tür önbellekleme sunuyoruz:
- <LocalizedLink href="/guides/features/cache/module-cache">Modül
  önbelleği</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcode
  önbelleği</LocalizedLink>

## Modül önbelleği {#module-cache}

Tuist'in <LocalizedLink href="/guides/features/projects">proje
oluşturma</LocalizedLink> özelliklerini kullanan projeler için, tek tek
modülleri ikili dosyalar olarak önbelleğe alan ve bunları ekibiniz ve CI
ortamlarınız arasında paylaşan güçlü bir önbellek sistemi sunuyoruz.

Yeni Xcode önbelleğini de kullanabilirsiniz, ancak bu özellik şu anda yerel
derlemeler için optimize edilmiştir ve oluşturulmuş projele önbelleğe kıyasla
önbellek isabet oranı daha düşük olacaktır. Ancak, hangi önbellek çözümünü
kullanacağınız kararı, özel ihtiyaçlarınıza ve tercihlerinize bağlıdır. En iyi
sonuçları elde etmek için her iki önbellek çözümünü birleştirebilirsiniz.

<LocalizedLink href="/guides/features/cache/module-cache">Modül önbelleği
hakkında daha fazla bilgi edinin →</LocalizedLink>

## Xcode önbelleği {#xcode-cache}

::: warning STATE OF CACHE IN XCODE
<!-- -->
Xcode önbellekleme şu anda yerel artımlı derlemeler için optimize edilmiştir ve
tüm derleme görevleri henüz yoldan bağımsız değildir. Yine de Tuist'in uzak
önbelleğini takarak avantajlardan yararlanabilirsiniz. Derleme sisteminin
kapasitesi sürekli gelişirken, derleme sürelerinin de zamanla iyileşmesini
bekliyoruz.
<!-- -->
:::

Apple, Bazel ve Buck gibi diğer derleme sistemlerine benzer şekilde, derleme
düzeyinde yeni bir önbellekleme çözümü üzerinde çalışmaktadır. Yeni önbellekleme
özelliği Xcode 26'dan itibaren kullanılabilir ve Tuist artık bu özelliği
sorunsuz bir şekilde entegre etmektedir – Tuist'in
<LocalizedLink href="/guides/features/projects">proje oluşturma</LocalizedLink>
özelliklerini kullanıp kullanmadığınıza bakılmaksızın.

<LocalizedLink href="/guides/features/cache/xcode-cache">Xcode önbelleği
hakkında daha fazla bilgi edinin →</LocalizedLink>
