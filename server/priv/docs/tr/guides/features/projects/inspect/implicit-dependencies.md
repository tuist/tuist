---
{
  "title": "Örtük içe aktarmalar",
  "titleTemplate": ":title · İncele · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist kullanarak örtük içe aktarmaları nasıl bulacağınızı öğrenin."
}
---
# Örtük içe aktarmalar {#implicit-imports}

Ham Xcode projesiyle bir Xcode proje grafiğini yönetmenin karmaşıklığını azaltmak için Apple, bağımlılıkların örtük olarak tanımlanmasına olanak tanıyan bir derleme sistemi tasarladı. Bu, örneğin bir uygulamanın, bağımlılığı açıkça bildirmese bile bir çerçeveye bağlı olabileceği anlamına gelir. Küçük ölçekte bu sorun değildir, ancak proje grafiğinin karmaşıklığı arttıkça örtüklük, güvenilmez artımlı derlemeler veya önizlemeler ve kod tamamlama gibi düzenleyici tabanlı özellikler olarak ortaya çıkabilir.

Sorun, örtük bağımlılıkların oluşmasını engelleyememenizdir. Herhangi bir geliştirici Swift koduna bir `import` ifadesi ekleyebilir ve örtük bağımlılık oluşturulur. İşte tam bu noktada Tuist devreye girer. Tuist, projenizdeki kodu statik olarak analiz ederek örtük bağımlılıkları inceleyen bir komut sağlar. Aşağıdaki komut, projenizin örtük bağımlılıklarını listeler:

```bash
tuist inspect dependencies --only implicit
```

Komut herhangi bir örtük içe aktarma algılarsa, sıfır dışındaki bir çıkış koduyla sonlanır.

> [!TIP]
> **CI'da doğrulayın**
>
> Bu komutu, her yeni kod yukarı akışa gönderildiğinde <.localized_link href="/guides/integrations/continuous-integration">sürekli entegrasyon</.localized_link> sürecinizin bir parçası olarak çalıştırmanızı şiddetle öneririz.


> [!WARNING]
> **Tüm örtük durumlar algılanmaz**
>
> Tuist örtük bağımlılıkları algılamak için statik kod analizine güvendiğinden tüm durumları yakalayamayabilir. Örneğin Tuist, kod içindeki derleyici yönergeleri aracılığıyla koşullu içe aktarmaları anlayamaz.
