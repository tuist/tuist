## Makine metrikleri {#machine-metrics}

Derleme içgörülerinde, derleme sırasında yakalanan makine düzeyindeki performans metrikleri (CPU, bellek, ağ ve disk kullanımı) yer alabilir. Bunu etkinleştirmek için sistem metriklerini sürekli olarak örnekleyen hafif bir arka plan daemon'u kurun:

```bash
tuist setup insights
```

Bu işlem, arka planda metrikleri örnekleyen yerel bir daemon çalıştırır. Veriler `tuist inspect build` tarafından otomatik olarak alınır ve derleme raporuyla birlikte yüklenir.

> [!TIP]
> **CI**
>
> Makine metriklerini burada da yakalamak için derlemeden önce CI makinelerinizde `tuist setup insights` komutunu çalıştırın.

Makine metriklerinin toplanmasını durdurmak için şunu çalıştırın:

```bash
tuist teardown insights
```

Bu işlem, daemon'un LaunchAgent'ını devre dışı bırakır, plist dosyasını kaldırır ve `~/.local/state` konumundaki örneklenen metrikler ile daemon günlüklerini siler; böylece arka planda hiçbir şey çalışmaz.
