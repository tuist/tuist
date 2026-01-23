---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Loglama {#logging}

CLI, günlük kaydı için [swift-log](https://github.com/apple/swift-log) arayüzünü
kullanır. Paket, günlük kaydı için uygulama ayrıntılarını soyutlayarak CLI'nin
günlük kaydı arka ucundan bağımsız olmasını sağlar. Günlük kaydedici, görev
yerel değişkenleri kullanılarak bağımlılık enjeksiyonu ile eklenir ve şu komutla
her yerden erişilebilir:

```bash
Logger.current
```

::: info
<!-- -->
`, Dispatch` veya ayrılmış görevler kullanıldığında görev yerel değişkenleri
değeri yaymaz, bu nedenle bunları kullanıyorsanız değeri alıp asenkron işleme
aktarmanız gerekir.
<!-- -->
:::

## Ne loglenmeli {#what-to-log}

Günlükler CLI'nin kullanıcı arayüzü değildir. Günlükler, sorunlar ortaya
çıktığında bunları teşhis etmek için kullanılan bir araçtır. Bu nedenle, ne
kadar fazla bilgi sağlarsanız o kadar iyidir. Yeni özellikler oluştururken,
beklenmedik bir davranışla karşılaşan bir geliştiricinin yerine kendinizi koyun
ve onlara hangi bilgilerin yardımcı olabileceğini düşünün. Doğru [günlük
düzeyini](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)
kullandığınızdan emin olun. Aksi takdirde, geliştiriciler gereksiz bilgileri
filtreleyemezler.
