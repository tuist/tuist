## Makine metrikleri {#machine-metrics}

Derleme içgörülerine, derleme sırasında yakalanan makine düzeyi performans metrikleri (CPU, bellek, ağ ve disk kullanımı) dahil edilebilir. Bunu etkinleştirmek için sistem metriklerini sürekli olarak örnekleyen hafif bir arka plan daemon'u kurun:

```bash
tuist setup insights
```

Bu işlem, metrikleri arka planda örnekleyen yerel bir daemon çalıştırır. Veriler `tuist inspect build` tarafından otomatik olarak alınır ve derleme raporuyla birlikte yüklenir.

Disk metrikleri, okuma/yazma etkinliğini ve uyumlu bir CLI ile sunucu kullanıldığında macOS sistem Veri birimindeki (`/System/Volumes/Data`) toplam ve kullanılabilir alanı içerir. Kullanılabilir alan, temizlenebilir alanı dışlar. Disk alanı grafiği, yalnızca yükleme zamanında değil, derleme süresince toplam kapasiteyle birlikte kullanılan alanı (toplam eksi kullanılabilir) gösterir. Checkout veya DerivedData için kullanılan harici birimleri ölçmez.

CLI'yı yükselttikten sonra, mevcut örnekleme aracını `tuist teardown insights` komutuyla durdurup ardından `tuist setup insights` komutuyla yeniden başlatın. Örnekleme, derleme sırasında çalışıyor olmalıdır; eski raporlarda ve başarısız ölçümlerde disk alanı değerleri bulunmaz ve sıfır olarak gösterilmez. Disk alanı örneklemeleri, mevcut 90 günlük makine metrikleri saklama politikasına tabidir.

> [!TIP]
> **CI**
>
> Makine metriklerini CI makinelerinizde de yakalamak için derlemeden önce `tuist setup insights` komutunu çalıştırın.

Makine metriklerini toplamayı durdurmak için şunu çalıştırın:

```bash
tuist teardown insights
```

Bu işlem, daemon'un LaunchAgent'ını kaldırır, plist dosyasını siler ve `~/.local/state` konumundaki örneklenen metrikler ile daemon günlüklerini temizler; böylece arka planda hiçbir şey çalışmaya devam etmez.
