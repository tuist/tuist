---
{
  "title": "Örtük içe aktarmalar",
  "titleTemplate": ":title · İncele · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Örtük içe aktarmaları bulmak için Tuist'in nasıl kullanılacağını öğrenin."
}
---
# Örtük içe aktarmalar {#implicit-imports}

Ham Xcode projesiyle bir Xcode proje grafiğini yönetmenin karmaşıklığını azaltmak için Apple, bağımlılıkların örtük olarak tanımlanmasına olanak tanıyan bir yapıda derleme sistemi tasarladı. Bu, bir ürünün (örneğin bir uygulamanın) bağımlılığı açıkça bildirmese bile bir çerçeveye (framework) bağlı olabileceği anlamına gelir. Küçük ölçekte bu sorun değildir, ancak proje grafiğinin karmaşıklığı arttıkça örtüklük, güvenilmez artımlı derlemeler veya ön izlemeler ve kod tamamlama gibi düzenleyici tabanlı özelliklerde kendini gösterebilir.

Sorun, örtük bağımlılıkların oluşmasını engelleyememenizdir. Herhangi bir geliştirici Swift koduna bir `import` ifadesi ekleyebilir ve örtük bağımlılık oluşturulur. İşte tam burada Tuist devreye girer. Tuist, projenizdeki kodu statik olarak analiz ederek örtük bağımlılıkları inceleyen bir komut sunar. Aşağıdaki komut, projenizin örtük bağımlılıklarını listeleyecektir:

```bash
tuist inspect dependencies --only implicit
```

Komut herhangi bir örtük içe aktarma tespit ederse, sıfırdan farklı bir çıkış koduyla sonlanır.

> [!TIP]
> **CI’da doğrulayın**
>
> Yeni kod yukarı akışa her gönderildiğinde bu komutu <.localized_link href="/guides/integrations/continuous-integration">sürekli entegrasyon</.localized_link> sürecinizin bir parçası olarak çalıştırmanızı şiddetle öneririz.


> [!WARNING]
> **Tüm örtük durumlar tespit edilmez**
>
> Tuist örtük bağımlılıkları tespit etmek için statik kod analizine dayandığından tüm durumları yakalayamayabilir. Örneğin, Tuist kod içindeki derleyici yönergeleri aracılığıyla koşullu içe aktarmaları anlayamaz.
