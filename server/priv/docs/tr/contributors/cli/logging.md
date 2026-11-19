---
{
  "title": "Günlük Kaydı",
  "titleTemplate": ":title · CLI · Katkıda Bulunanlar · Tuist",
  "description": "Tuist CLI'da günlük kaydı nasıl çalışır ve katkıda bulunanlar için yönergeler."
}
---
# Günlük Kaydı {#logging}

CLI, günlük kaydı için [swift-log](https://github.com/apple/swift-log) arayüzünü benimser. Bu paket, günlük kaydının uygulama ayrıntılarını soyutlayarak CLI'nin günlük kaydı altyapısından bağımsız olmasını sağlar. Günlük kaydedici, görev yerelleri kullanılarak bağımlılık enjeksiyonu ile sağlanır ve şu şekilde her yerden erişilebilir:

```bash
Logger.current
```

> [!NOTE]
> `Dispatch` veya ayrılmış görevler kullanılırken görev yerelleri değeri yaymaz; bu nedenle bunları kullanıyorsanız, değeri alıp eşzamansız işleme iletmeniz gerekir.


## Neler günlüğe kaydedilmeli {#what-to-log}

Günlük kayıtları, CLI'nin kullanıcı arayüzü değildir. Sorunlar ortaya çıktığında teşhis etmek için bir araçtır. Bu nedenle, ne kadar çok bilgi sağlarsanız o kadar iyi olur. Yeni özellikler geliştirirken, beklenmeyen bir davranışla karşılaşan bir geliştiricinin yerine koyun ve hangi bilgilerin onlara yardımcı olacağını düşünün. Doğru [günlük düzeyini](https://www.swift.org/documentation/server/guides/libraries/log-levels.html) kullandığınızdan emin olun. Aksi takdirde geliştiriciler gürültüyü filtreleyemez.
