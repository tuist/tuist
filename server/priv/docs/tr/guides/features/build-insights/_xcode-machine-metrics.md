## Makine metrikleri {#machine-metrics}

Derleme içgörileri, derleme sırasında yakalanan makine düzeyi performans metriklerini (CPU, bellek, ağ ve disk kullanımı) içerebilir. Bunu etkinleştirmek için sistem metriklerini sürekli örnekleyen hafif bir arka plan daemon'u kurun:

```bash
tuist setup insights
```

Bu işlem, metrikleri arka planda örnekleyen yerel bir daemon çalıştırır. Veriler `tuist inspect build` tarafından otomatik olarak alınır ve derleme raporuyla birlikte yüklenir.

Disk metrikleri okuma/yazma etkinliğini ve uyumlu bir CLI ile sunucu kullanıldığında macOS sistem Veri birimindeki (`/System/Volumes/Data`) toplam ve kullanılabilir alanı içerir. Kullanılabilir alan, temizlenebilir alanı hariç tutar. Disk alanı grafiği, yalnızca yükleme anında değil, derleme süreci boyunca kullanılan alanı (toplam eksi kullanılabilir) toplam kapasiteyle birlikte gösterir. Checkout veya DerivedData için kullanılan harici birimleri ölçmez.

CLI'yı yükselttikten sonra mevcut örnekleme aracını `tuist teardown insights` komutunu ve ardından `tuist setup insights` komutunu çalıştırarak yeniden başlatın. Örnekleme, derleme sırasında çalışıyor olmalıdır; eski raporlar ve başarısız ölçümlerde disk alanı değerleri bulunmaz ve sıfır olarak gösterilmez. Disk alanı örneklemeleri, mevcut 90 günlük makine metrikleri saklama süresini takip eder.

> [!TIP]
> **CI**
>
> Makine metriklerini burada da yakalamak için derlemeden önce CI makinelerinizde `tuist setup insights` komutunu çalıştırın.

Makine metriklerini toplamayı durdurmak için şunu çalıştırın:

```bash
tuist teardown insights
```

Bu işlem, daemon'un LaunchAgent'ını kaldırır, plist dosyasını siler ve `~/.local/state` konumundaki örneklenen metrikler ile daemon günlüklerini temizler; böylece arka planda çalışan hiçbir şey kalmaz.
