---
{
  "title": "Örtük içe aktarmalar",
  "titleTemplate": ":title · İncele · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Örtük içe aktarmaları bulmak için Tuist'in nasıl kullanılacağını öğrenin."
}
---
# Örtük içe aktarmalar {#implicit-imports}

Apple, ham Xcode projeleriyle bir Xcode proje grafiğini yönetmenin karmaşıklığını azaltmak için bağımlılıkların örtük olarak tanımlanmasına olanak tanıyan bir derleme sistemi tasarladı. Bu, bir ürünün (örneğin bir uygulamanın) bağımlılığı açıkça bildirmese bile bir çerçeveye (framework) bağlı olabileceği anlamına gelir. Küçük ölçekte bu sorun değildir, ancak proje grafiğinin karmaşıklığı arttıkça örtüklük, güvenilmez artımlı derlemeler veya ön izlemeler ve kod tamamlama gibi düzenleyici tabanlı özelliklerde kendini gösterebilir.

Sorun, örtük bağımlılıkların oluşmasını engelleyememenizdir. Herhangi bir geliştirici Swift koduna bir `import` ifadesi ekleyebilir ve örtük bağımlılık oluşturulur. İşte Tuist burada devreye girer. Tuist, projenizdeki kodu statik olarak analiz ederek örtük bağımlılıkları inceleyen bir komut sağlar. Aşağıdaki komut, projenizin örtük bağımlılıklarını listeler:

```bash
tuist inspect dependencies --only implicit
```

Komut herhangi bir örtük içe aktarma tespit ederse, sıfırdan farklı bir çıkış koduyla sonlanır.

> [!TIP]
> **CI'da doğrula**
>
> Bu komutu, yeni kod her yukarı akışa gönderildiğinde <.localized_link href="/guides/integrations/continuous-integration">sürekli entegrasyon</.localized_link> sürecinizin bir parçası olarak çalıştırmanızı şiddetle tavsiye ederiz.


> [!WARNING]
> **Tüm örtük durumlar tespit edilmez**
>
> Tuist örtük bağımlılıkları tespit etmek için statik kod analizine güvendiğinden, tüm durumları yakalayamayabilir. Örneğin, Tuist kod içindeki derleyici yönergeleri aracılığıyla koşullu içe aktarmaları anlayamaz.
