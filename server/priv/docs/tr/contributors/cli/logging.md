---
{
  "title": "Günlük Kaydı",
  "titleTemplate": ":title · CLI · Katkıda Bulunanlar · Tuist",
  "description": "Tuist CLI'da günlük kaydının nasıl çalıştığı ve katkıda bulunanlar için yönergeler."
}
---
# Günlük kaydı {#logging}

CLI, günlük kaydı için [swift-log](https://github.com/apple/swift-log) arayüzünü benimser. Bu paket, günlük kaydının uygulama ayrıntılarını soyutlayarak CLI'nin günlük kaydı altyapısından bağımsız olmasını sağlar. Günlük kaydedici, görev yerelleri kullanılarak bağımlılık enjeksiyonu ile sağlanır ve şu şekilde her yerden erişilebilir:

```bash
Logger.current
```

> [!NOTE]
> `Dispatch` veya ayrık görevler kullanılırken görev yerelleri değeri yaymaz; bu nedenle bunları kullanıyorsanız, değeri alıp eşzamansız işleme iletmeniz gerekir.


## Nelerin günlüğe kaydedileceği {#what-to-log}

Günlük kayıtları, CLI'nin kullanıcı arayüzü değildir. Sorunlar ortaya çıktığında teşhis etmek için bir araçtır. Bu nedenle, ne kadar çok bilgi sağlarsanız o kadar iyi olur. Yeni özellikler geliştirirken, beklenmeyen bir davranışla karşılaşan bir geliştiricinin yerine kendinizi koyun ve hangi bilgilerin onlar için yararlı olacağını düşünün. Doğru [günlük düzeyini](https://www.swift.org/documentation/server/guides/libraries/log-levels.html) kullandığınızdan emin olun. Aksi takdirde geliştiriciler gürültüyü filtreleyemez.
