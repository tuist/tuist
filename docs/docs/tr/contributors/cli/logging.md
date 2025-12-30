---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Loglama {#logging}

CLI, günlük kaydı için [swift-log](https://github.com/apple/swift-log) arayüzünü
benimser. Paket, loglama uygulamanın ayrıntılarını soyutlayarak CLI'nin loglama
arka ucundan bağımsız olmasını sağlar. Kaydedici, görev yerelleri kullanılarak
bağımlılık enjekte edilir ve kullanılarak herhangi bir yerden erişilebilir:

```bash
Logger.current
```

::: info
<!-- -->
Görev yerelleri, `Dispatch` veya ayrılmış görevleri kullanırken değeri yaymaz,
bu nedenle bunları kullanırsanız, değeri almanız ve asenkron işleme aktarmanız
gerekir.
<!-- -->
:::

## Ne loglenmeli {#what-to-log}

Günlükler CLI'nin kullanıcı arayüzü değildir. Ortaya çıktıklarında sorunları
teşhis etmek için bir araçtır. Bu nedenle, ne kadar çok bilgi sağlarsanız o
kadar iyi olur. Yeni özellikler geliştirirken, kendinizi beklenmedik
davranışlarla karşılaşan bir geliştiricinin yerine koyun ve hangi bilgilerin
onlara yardımcı olacağını düşünün. Doğru [log
level](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)
kullandığınızdan emin olun. Aksi takdirde geliştiriciler gürültüyü
filtreleyemeyecektir.
