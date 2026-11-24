---
{
  "title": "Apple",
  "titleTemplate": ":title · Paket içgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "iOS, iPadOS, macOS, watchOS ve tvOS paketlerini (.ipa, .xcarchive, .app) Tuist Paket İçgörüleri ile analiz edin."
}
---
# Apple {#bundle-insights-apple}

Bir arşiv, yüklenebilir bir paket veya derlenmiş bir uygulama üzerinde `tuist inspect bundle` komutunu çalıştırarak bir Apple paketini analiz edin:

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
```bash [Analyze by app name]
tuist inspect bundle App --platforms ios --configuration Debug
```
<!-- -->
:::

macOS'ta bir yol yerine bir uygulama adı verdiğinizde, Tuist derlenmiş `.app` dosyasını Xcode'un derleme ürünlerinden çözümler (`--derived-data-path` ayarlandığında bunu dikkate alır); bu işlem `tuist share` ile aynı şekilde çalışır.

<!-- @snippet: ./_upload-result -->

## App Store Connect ile Karşılaştırma {#app-store-connect}

Tuist paketi tam olarak sağladığınız gibi ölçer ve [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size) uygulamaz. Raporlanan boyutlar, \*\***universal**\*\* (inceletilmemiş) varyanta karşılık gelir — App Store Connect'in uygulama dosya boyutları raporunda "Universal" olarak etiketlenen satır — cihaz başına varyantlara değil.

Rakamların Universal satırıyla aynı aralıkta olmasını bekleyin, ancak birebir aynı olmayacaktır:

- **Kurulum boyutu**, Universal kurulum boyutuna yakındır. App Store Connect, dosya sistemi blok tahsisi ve Apple'ın kendi tahmini gibi cihaz üzerindeki ek yükleri içerdiğinden biraz daha yüksek bir değer bildirir; ham dosya boyutu ölçümü bu ek yükleri kapsamaz.
- **İndirme boyutu**, Universal indirme boyutundan daha düşüktür. Apple, yüklemeden sonra uygulama ikili dosyasını şifreler ve şifrelenmiş veriler daha az verimli sıkıştırıldığından App Store'daki sıkıştırılmış indirme, Tuist'in ölçtüğü `.ipa` arşivinden daha büyük olur. Bu durum yüklemeden sonra Apple tarafında gerçekleştiği için Tuist'in sayısına yansımaz.

App Store Connect'teki cihaz başına satırlar daha da küçüktür, çünkü app thinning belirli bir cihazın ihtiyaç duymadığı CPU mimarilerini ve varlık varyantlarını kaldırır. Tuist şu anda cihaz başına (inceltilmiş) boyutları raporlamamaktadır.

<!-- @snippet: ./_shared -->
