---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# Örtük içe aktarmalar {#implicit-imports}

Apple, ham Xcode projesiyle Xcode proje grafiğini sürdürmenin karmaşıklığını
azaltmak için, bağımlılıkların örtük olarak tanımlanmasına olanak tanıyan bir
derleme sistemi tasarladı. Bu, bir ürünün (örneğin bir uygulama) bağımlılığı
açıkça belirtmeden bile bir çerçeveye bağımlı olabileceği anlamına gelir. Küçük
ölçekte bu sorun değildir, ancak proje grafiği karmaşıklaştıkça, örtük
bağımlılıklar güvenilmez artımlı derlemeler veya önizleme veya kod tamamlama
gibi düzenleyici tabanlı özellikler olarak ortaya çıkabilir.

Sorun, örtük bağımlılıkların oluşmasını engelleyememenizdir. Herhangi bir
geliştirici, Swift koduna `import` ifadesini ekleyebilir ve örtük bağımlılık
oluşturulur. Tuist burada devreye girer. Tuist, projenizdeki kodu statik olarak
analiz ederek örtük bağımlılıkları incelemek için bir komut sağlar. Aşağıdaki
komut, projenizin örtük bağımlılıklarını görüntüler:

```bash
tuist inspect dependencies --only implicit
```

Komut herhangi bir örtük içe aktarma tespit ederse, sıfırdan farklı bir çıkış
koduyla sonlanır.

::: tip VALIDATE IN CI
<!-- -->
Yeni kod her yukarı aktarıldığında, bu komutu
<LocalizedLink href="/guides/features/automate/continuous-integration">sürekli
entegrasyon</LocalizedLink> komutunuzun bir parçası olarak çalıştırmanızı
şiddetle tavsiye ederiz.
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Tuist, örtük bağımlılıkları tespit etmek için statik kod analizine
dayandığından, tüm durumları yakalayamayabilir. Örneğin, Tuist, koddaki
derleyici yönergeleri aracılığıyla koşullu içe aktarmaları anlayamaz.
<!-- -->
:::
