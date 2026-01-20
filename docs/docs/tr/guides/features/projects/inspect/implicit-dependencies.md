---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# Örtük ithalat {#implicit-imports}

Apple, ham Xcode projesiyle bir Xcode proje grafiği tutmanın karmaşıklığını
hafifletmek için derleme sistemini bağımlılıkların dolaylı olarak tanımlanmasına
izin verecek şekilde tasarladı. Bu, bir ürünün, örneğin bir uygulamanın,
bağımlılığı açıkça bildirmeden bile bir çerçeveye bağlı olabileceği anlamına
gelir. Küçük ölçekte bu sorun teşkil etmez, ancak proje grafiği
karmaşıklaştıkça, örtüklük güvenilir olmayan artımlı derlemeler veya önizlemeler
veya kod tamamlama gibi düzenleyici tabanlı özellikler olarak ortaya çıkabilir.

Sorun şu ki, örtük bağımlılıkların oluşmasını engelleyemezsiniz. Herhangi bir
geliştirici Swift koduna bir `import` ifadesi ekleyebilir ve örtük bağımlılık
oluşturulur. İşte bu noktada Tuist devreye giriyor. Tuist, projenizdeki kodu
statik olarak analiz ederek örtük bağımlılıkları incelemek için bir komut
sağlar. Aşağıdaki komut, projenizin örtük bağımlılıklarının çıktısını
verecektir:

```bash
tuist inspect implicit-imports
```

Komut herhangi bir örtük içe aktarma tespit ederse, sıfırdan farklı bir çıkış
koduyla çıkar.

::: tip VALIDATE IN CI
<!-- -->
Bu komutu, her yeni kod yayınlandığında
<LocalizedLink href="/guides/features/automate/continuous-integration">sürekli entegrasyon</LocalizedLink> komutunuzun bir parçası olarak çalıştırmanızı
şiddetle tavsiye ederiz.
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Tuist, örtük bağımlılıkları tespit etmek için statik kod analizine
dayandığından, tüm durumları yakalayamayabilir. Örneğin, Tuist koddaki derleyici
direktifleri aracılığıyla koşullu içe aktarmaları anlayamaz.
<!-- -->
:::
