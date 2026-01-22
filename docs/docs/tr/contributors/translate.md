---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Çevir {#translate}

Diller, anlaşılmayı engelleyebilir. Tuist'in mümkün olduğunca çok kişi
tarafından erişilebilir olmasını istiyoruz. Tuist'in desteklemediği bir dil
konuşuyorsanız, Tuist'in çeşitli yüzeylerini çevirerek bize yardımcı
olabilirsiniz.

Çevirileri korumak sürekli bir çaba gerektirdiğinden, çevirileri korumamıza
yardımcı olmak isteyen katkıcılar gördükçe diller ekliyoruz. Şu anda aşağıdaki
diller desteklenmektedir:

- İngilizce
- Korece
- Japonca
- Rusça
- Çince
- İspanyolca
- Portekizce

::: tip REQUEST A NEW LANGUAGE
<!-- -->
Tuist'in yeni bir dili desteklemesinin faydalı olacağını düşünüyorsanız, lütfen
[topluluk forumunda yeni bir konu
oluşturun](https://community.tuist.io/c/general/4) ve bunu toplulukla tartışın.
<!-- -->
:::

## Nasıl çevrilir? {#how-to-translate}

[Weblate](https://weblate.org/en-gb/) örneğimiz
[translate.tuist.dev](https://translate.tuist.dev) adresinde çalışmaktadır.
[Projeye](https://translate.tuist.dev/engage/tuist/) gidip bir hesap oluşturarak
çeviriye başlayabilirsiniz.

Çeviriler, bakımcıların inceleyip birleştireceği GitHub çekme istekleri
kullanılarak kaynak depoya geri senkronize edilir.

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
Weblate, kaynak ve hedef dilleri birbirine bağlamak için dosyaları bölümlere
ayırır. Kaynak dili değiştirirseniz, bu bağlantı bozulur ve uzlaştırma işlemi
beklenmedik sonuçlar verebilir.
<!-- -->
:::

## Yönergeler {#guidelines}

Aşağıda, çeviri yaparken uyduğumuz kurallar yer almaktadır.

### Özel kaplar ve GitHub uyarıları {#custom-containers-and-github-alerts}

[custom containers](https://vitepress.dev/guide/markdown#custom-containers)
çevirirken, yalnızca başlığı ve içeriği **çevirin, uyarı türünü** çevirmeyin.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### Başlık başlıkları {#heading-titles}

Başlıkları çevirirken, yalnızca başlığı çevirin, kimliği çevirmeyin. Örneğin,
aşağıdaki başlığı çevirirken:

```markdown
# Add dependencies {#add-dependencies}
```

Şu şekilde çevrilmelidir (id'nin çevrilmediğine dikkat edin):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
