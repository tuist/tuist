---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist and Xcode projects."
}
---
# En iyi uygulamalar {#best-practices}

Farklı ekipler ve projelerle çalıştığımız yıllar boyunca, Tuist ve Xcode
projeleriyle çalışırken izlemenizi önerdiğimiz bir dizi en iyi uygulama
belirledik. Bu uygulamalar zorunlu değildir, ancak projelerinizi sürdürmeyi ve
ölçeklendirmeyi kolaylaştıracak şekilde yapılandırmanıza yardımcı olabilirler.

## Xcode {#xcode}

### Cesareti kırılmış modeller {#discouraged-patterns}

#### Uzak ortamları modellemek için konfigürasyonlar {#configurations-to-model-remote-environments}

Birçok kuruluş farklı uzak ortamları modellemek için derleme yapılandırmaları
kullanır (örneğin, `Debug-Production` veya `Release-Canary`), ancak bu
yaklaşımın bazı dezavantajları vardır:

- **Tutarsızlıklar:** Grafik boyunca yapılandırma tutarsızlıkları varsa, derleme
  sistemi bazı hedefler için yanlış yapılandırmayı kullanabilir.
- **Karmaşıklık:** Projeler, mantık yürütmesi ve sürdürmesi zor olan uzun bir
  yerel yapılandırmalar ve uzak ortamlar listesiyle sonuçlanabilir.

Derleme yapılandırmaları farklı derleme ayarlarını somutlaştırmak için
tasarlanmıştır ve projeler nadiren `Debug` ve `Release` adreslerinden daha
fazlasına ihtiyaç duyar. Farklı ortamları modelleme ihtiyacı farklı şekillerde
gerçekleştirilebilir:

- **Hata Ayıklama derlemelerinde:** Geliştirme sırasında erişilebilir olması
  gereken tüm yapılandırmaları uygulamaya dahil edebilir (örn. uç noktalar) ve
  bunları çalışma zamanında değiştirebilirsiniz. Geçiş, şema başlatma ortam
  değişkenleri kullanılarak veya uygulama içindeki bir kullanıcı arayüzü ile
  gerçekleştirilebilir.
- **Sürüm derlemelerinde:** Sürüm durumunda, yalnızca sürüm derlemesinin bağlı
  olduğu yapılandırmayı dahil edebilir ve derleyici yönergelerini kullanarak
  yapılandırmaları değiştirmek için çalışma zamanı mantığını dahil edemezsiniz.

::: info Non-standard configurations
<!-- -->
Tuist, standart olmayan yapılandırmaları destekler ve vanilya Xcode projelerine
kıyasla yönetilmelerini kolaylaştırırken, yapılandırmalar bağımlılık grafiği
boyunca tutarlı değilse uyarılar alırsınız. Bu, derleme güvenilirliğini
sağlamaya yardımcı olur ve yapılandırmayla ilgili sorunları önler.
<!-- -->
:::

## Oluşturulmuş projeler

### Oluşturulabilir klasörler

Tuist 4.62.0, birleştirme çakışmalarını azaltmak için Xcode 16'da sunulan bir
özellik olan **oluşturulabilir klasörler** (Xcode'un senkronize grupları) için
destek ekledi.

Tuist'in joker karakter kalıpları (örneğin, `Sources/**/*.swift`) oluşturulmuş
projele'deki birleştirme çakışmalarını zaten ortadan kaldırırken,
oluşturulabilir klasörler ek avantajlar sunar:

- **Otomatik senkronizasyon**: Proje yapınız dosya sistemiyle senkronize kalır -
  dosya eklerken veya çıkarırken yenileme gerekmez
- **Yapay zeka dostu iş akışları**: Kodlama asistanları ve aracıları, proje
  yenilenmesini tetiklemeden kod tabanınızı değiştirebilir
- **Daha basit yapılandırma**: Açık dosya listelerini yönetmek yerine klasör
  yollarını tanımlayın

Daha akıcı bir geliştirme deneyimi için geleneksel `Target.sources` ve
`Target.resources` öznitelikleri yerine derlenebilir klasörleri benimsemenizi
öneririz.

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### Bağımlılıklar

#### CI üzerinde çözümlenmiş sürümleri zorla

Swift paketi Bağımlılıklarını CI üzerine kurarken, deterministik derlemeler
sağlamak için `--force-resolved-versions` bayrağını kullanmanızı öneririz:

```bash
tuist install --force-resolved-versions
```

Bu bayrak, bağımlılıkların `Package.resolved` adresinde sabitlenen tam sürümler
kullanılarak çözümlenmesini sağlayarak bağımlılık çözümlemesinde belirsizlikten
kaynaklanan sorunları ortadan kaldırır. Bu özellikle tekrarlanabilir
derlemelerin kritik olduğu CI'da önemlidir.
