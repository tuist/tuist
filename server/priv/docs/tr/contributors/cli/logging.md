---
{
  "title": "Günlük Kaydı",
  "titleTemplate": ":title · CLI · Katkıda Bulunanlar · Tuist",
  "description": "Tuist CLI'da günlük kaydının nasıl çalıştığı ve katkıda bulunanlar için yönergeler."
}
---
# Günlükleme {#logging}

CLI, günlükleme için [swift-log](https://github.com/apple/swift-log) arayüzünü benimser. Paket, günlükleme uygulama ayrıntılarını soyutlayarak CLI'nin günlük arka ucundan bağımsız olmasını sağlar. Günlükleyici, görev yerelleri kullanılarak bağımlılık enjekte edilir ve şu şekilde her yerden erişilebilir:

```bash
Logger.current
```

> [!NOTE]
> `Dispatch` veya kopuk görevler kullanılırken görev yerelleri değeri yaymaz; bu nedenle bunları kullanıyorsanız, değeri almanız ve eşzamansız işleme iletmeniz gerekir.


## Nelerin günlükleneceği {#what-to-log}

Günlükler, CLI'nin kullanıcı arayüzü değildir. Sorunlar ortaya çıktığında teşhis etmek için bir araçtır. Bu nedenle, sağladığınız bilgi ne kadar çok olursa o kadar iyidir. Yeni özellikler geliştirirken, beklenmedik bir davranışla karşılaşan bir geliştiricinin yerine kendinizi koyun ve onlar için hangi bilgilerin yararlı olacağını düşünün. Doğru [günlük düzeyini](https://www.swift.org/documentation/server/guides/libraries/log-levels.html) kullandığınızdan emin olun. Aksi takdirde geliştiriciler gürültüyü filtreleyemez.
