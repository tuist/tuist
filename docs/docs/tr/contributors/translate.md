---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Tercüme et {#translate}

Diller anlamanın önünde engel olabilir. Tuist'in mümkün olduğunca çok kişi
tarafından erişilebilir olmasını sağlamak istiyoruz. Tuist'in desteklemediği bir
dil konuşuyorsanız, Tuist'in çeşitli yüzeylerini tercüme ederek bize yardımcı
olabilirsiniz.

Çevirileri sürdürmek sürekli bir çaba olduğundan, dilleri sürdürmemize yardımcı
olmaya istekli katkıda bulunanları gördükçe ekliyoruz. Şu anda aşağıdaki diller
desteklenmektedir:

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
toplulukla tartışmak için yeni bir [topluluk forumunda
konu](https://community.tuist.io/c/general/4) oluşturun.
<!-- -->
:::

## Nasıl tercüme edilir {#how-to-translate}

translate.tuist.dev](https://translate.tuist.dev) adresinde çalışan bir
[Weblate](https://weblate.org/en-gb/) örneğimiz var.
Proje](https://translate.tuist.dev/engage/tuist/) adresine gidebilir, bir hesap
oluşturabilir ve çeviriye başlayabilirsiniz.

Çeviriler, bakımcıların gözden geçireceği ve birleştireceği GitHub çekme
istekleri kullanılarak kaynak deposuna geri senkronize edilir.

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
Weblate, kaynak ve hedef dilleri bağlamak için dosyaları bölümlere ayırır.
Kaynak dili değiştirirseniz, bağlamayı bozarsınız ve uzlaştırma beklenmedik
sonuçlar verebilir.
<!-- -->
:::

## Kılavuz İlkeler {#guidelines}

Aşağıda çeviri yaparken izlediğimiz yönergeler yer almaktadır.

### Özel konteynerler ve GitHub uyarıları {#custom-containers-and-github-alerts}

custom containers](https://vitepress.dev/guide/markdown#custom-containers)
çevrilirken yalnızca başlık ve içerik **çevrilir, uyarı türü** çevrilmez.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### Başlık başlıkları {#heading-titles}

Başlıkları çevirirken sadece başlığı çevirin, kimliği çevirmeyin. Örneğin,
aşağıdaki başlığı çevirirken:

```markdown
# Add dependencies {#add-dependencies}
```

Şu şekilde çevrilmelidir (kimliğin çevrilmediğine dikkat edin):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
