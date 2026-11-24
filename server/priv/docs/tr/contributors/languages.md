---
{
  "title": "Diller",
  "titleTemplate": ":title · Katkıda Bulunanlar · Tuist",
  "description": "Tuist'in yeni dilleri desteklemesine ve yerelleştirme bağlamını iyileştirmesine yardımcı olun."
}
---
# Diller {#translate}

Diller, anlayış önünde engeller oluşturabilir. Tuist’in mümkün olduğunca çok kişi tarafından erişilebilir olmasını istiyoruz. Eğer Tuist’in henüz desteklemediği bir dili konuşuyorsanız, İngilizce kaynak içeriği ve [Glossia](https://glossia.ai)’nın çeviri için kullandığı yerelleştirme bağlamını iyileştirerek Tuist’in o dili konuşmasına yardımcı olabilirsiniz.

Dil desteği sürekli bir çaba gerektirdiğinden, bu dillerin bakımına yardımcı olmaya istekli katkıcılar gördükçe yeni diller ekliyoruz. Şu anda desteklenen diller şunlardır:

- İngilizce
- Arapça
- İspanyolca
- Japonca
- Gürcüce
- Korece
- Rusça
- Kantonca
- Basitleştirilmiş Çince
- Geleneksel Çince

> [!TIP]
> **Yeni bir dil talep edin**
>
> Tuist’in yeni bir dili desteklemesinin faydalı olacağını düşünüyorsanız, lütfen toplulukla tartışmak üzere [topluluk forumunda yeni bir konu](https://community.tuist.io/c/general/4) açın.


## Nasıl yardımcı olunur {#how-to-translate}

Tuist dil desteği depodan yönetilir. Katkıcılar İngilizce kaynak içeriğini ve çeviri bağlamını günceller; [Glossia](https://glossia.ai) ise yerelleştirilmiş dosyaları otomatik olarak üretir.

İş akışı şöyledir:

1. İngilizce kaynak içeriğini güncelleyin.
2. Çevirmenlerin daha fazla yönlendirmeye ihtiyacı varsa ilgili `L10N.md` bağlamını güncelleyin.
3. Bu kaynak değişikliklerini içeren bir çekme isteği (pull request) açın.
4. Değişiklikler `main` dalına birleştirildikten sonra Glossia değişen kısımları çevirir ve güncellenmiş yerelleştirilmiş dosyalarla açık bir çeviri çekme isteği tutar.

> [!WARNING]
> **Oluşturulan yerelleştirilmiş içeriği değiştirmeyin**
>
> Oluşturulan yerelleştirilmiş içeriği doğrudan düzenlemeyin. Bunun yerine İngilizce kaynağı ve dil bağlamını güncelleyin.


## L10N.md yapısı {#l10n-md-structure}

`L10N.md` dosyaları, Glossia’nın çeviri sırasında kullandığı bağlamı tanımlar. Bunları farklı dizin seviyelerinde bulunabilen kapsamlı dil talimatları olarak düşünmek en kolay yoldur.

Örneğin:

```text
.
|-- L10N.md
|-- server
|   |-- L10N.md
|   |-- L10N
|   |   `-- es.md
|   `-- priv
|       `-- gettext
|           `-- marketing.pot
```


## Dizin bağlamı {#directory-context}

Glossia, depo kökünden başlayıp çevrilen dizine kadar inerken bu yol üzerinde bulduğu her `L10N.md` dosyasını birleştirir.

Yukarıdaki örnekte:

- `L10N.md` genel olarak uygulanır.
- `server/L10N.md` sunucuya özel bağlam ekler.
- `server/L10N/es.md` aynı alan için yalnızca İspanyolcaya yönelik geçersiz kılmalar ekler.

Bu, bağlamı ait olduğu yere yerleştirebileceğiniz anlamına gelir:

- kök dizinde depo genelinde geçerli rehberlik
- alt dizinde alana özgü rehberlik
- `L10N/<locale>.md` içinde dile özgü rehberlik
