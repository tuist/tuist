---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Modüler bir Xcode projesini bildirimsel Swift koduna dönüştürerek modül önbellekleme, seçici test, paket kayıt defteri ve grafik tabanlı derleme ile test içgörülerinin kilidini açın."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

Tuist'in Swift manifest dosyalarından Xcode projenizi tanımlamasını ve oluşturmasını istediğinizde bu yolu izleyin. Oluşturulan bir proje, modüler bir Xcode projesinin karmaşıklığını grafın öz, bildirimsel bir tanımına sıkıştırır. Ayrıca modül önbelleği ve seçici test için katı bir gerekliliktir.

Aşağıdaki her bölüm, bugün eksik olanla başlar ve ardından bu boşluğu dolduran özelliği adım adım açıklar.

## Ön koşullar

- Xcode yüklü macOS.
- <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzü</.localized_link>.

## Projeyi oluşturun

Çalıştığını görmek için en hızlı yol yeni bir projedir. Boş bir dizinde `tuist init` çalıştırın ve **Oluşturulan bir proje oluştur** seçeneğini belirleyin, platformu seçin, adı onaylayın, ardından kimlik doğrulaması yapın ve projeye sahip olması gereken hesabı seçin.

```bash
mkdir MyApp && cd MyApp
tuist init
```

Bunu bir kodlama aracısı veya betik üzerinden yürütüyorsanız, önce `tuist auth login` çalıştırın (tarayıcı akışı Enter tuşuna basmanızı bekler), ardından etkileşimsiz formu kullanın:

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

init tamamlandığında, `tuist generate` çalıştırın. Tuist, manifest dosyalarınızın yanına bir `.xcworkspace` yazar ve bunu Xcode'da açar. Hedefi derleyip çalıştırın. Örnek uygulamanın simülatörde başladığını görmelisiniz.

Bu, "bağlı + oluşturma" durumudur. Aşağıdakilerin tümü isteğe bağlı ve bağımsızdır.

Mevcut bir uygulamayı taşıyorsanız, önce [Xcode projesi geçiş kılavuzu](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) ile bağlayın, ardından geri dönün ve sorununuza uygun bölümlerle devam edin.

## Proje oluşturma

Bir `.xcodeproj`, uygulamanızın şeklini XML içine paketler: dosya referansları, derleme aşamaları, hedef bağımlılıkları, şemalar ve derleme ayarlarının tümü aynı ağaçta yaşar ve grafı bir graf olarak akıl yürütme için hiçbir ilkel bulunmaz. Proje büyüdükçe, bu şekli zihninizde tutmak zorlaşır ve Xcode'un araçların onu hash'lemesi ve hiçbir şey değişmediğinde işi atlaması için kararlı bir tutamacı yoktur.

Oluşturulan projeler grafı bildirimsel Swift içine sıkıştırır. `Project.swift` hedefleri, bağımlılıkları ve kaynakları doğrudan tanımlar ve Tuist arkasında grafın kararlı bir modelini korur. Bu model, aşağıdaki bölümlerin kilidini açan şeydir: modül önbellekleme ikili dosyaları yeniden kullanmak için onu hash'ler ve seçici test girdileri değişmemiş testleri atlamak için onu hash'ler.

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            sources: ["MyApp/Sources/**"],
            dependencies: []
        )
    ]
)
```

Her `tuist generate`, manifest dosyalarından deterministik bir çalışma alanı üretir. `.xcodeproj` ve `.xcworkspace` öğelerini `.gitignore` dosyasına ekleyin.

## Modül önbelleği

Modüler bir Xcode projesini sıfırdan derlemek makine başına bir maliyettir. Her takım arkadaşı ve her CI çalıştırıcısı aynı nesne dosyalarının kendi kopyasını üretir. Xcode derleme önbelleği iç döngüyü kısaltır ancak her hedefin makine başına derlenmesini ortadan kaldırmaz ve tüm bir framework'ü önceden oluşturulmuş bir ikili dosya ile değiştiremez.

Modül önbelleği bunu yapar. Grafınızdaki önbelleklenebilir her bağımlılığı bir kez derler (framework'ler, kütüphaneler, paketler), ortaya çıkan ikili dosyaları hedefin girdilerinin hash değerine karşı saklar ve sonraki oluşturmalarda hedefi ikili dosyasıyla değiştirir. Değişmeyen modüller derlenmeyi durdurur:

```bash
tuist cache
```

İlk çalıştırma her şeyi derler ve ikili dosyaları hesabınıza yükler. Sonraki `tuist generate` sırasında, değişmeyen bağımlılıklar önbelleğe alınmış ikili dosyalarıyla değiştirilir ve Xcode kaynaktan derlemek yerine `.xcframework` dosyalarına bağlanır.

## Seçici test

`xcodebuild test` bir değişikliğin hangi testleri etkilediğini bilmez, bu nedenle CI her push işlemesinde tüm paketi çalıştırır. Paket büyüdükçe, gerçekten çalışması gerekenler ile çalışanlar arasındaki fark dakikalardan onlarca dakikaya uzar.

Seçici test, son başarılı test çalışmasından bu yana değişenlerden etkilenen testleri yalnızca çalıştırır; proje grafını ve modül önbelleğinin güvendiği aynı hash algoritmasını kullanır:

```bash
tuist test
```

İlk `tuist test` her şeyi çalıştırır ve hedef başına hash değerlerini kalıcı hale getirir. Sonraki çalıştırmalar girdileri değişmemiş hedefleri atlar. `tuist test` öğesini CI'da `xcodebuild test` yerine kullanın ve geri bildirim dakikalar yerine saniyeler içinde gelir.

## Paket kayıt defteri

Swift Package Manager, paketler bir kayıt defteri yerine URL ile adreslendiği için her paketin git geçmişini derin klonlayarak bağımlılıkları çözer. Onlarca geçişli pakete sahip bir projede, çözümleme temiz bir checkout'ta dakikalar sürer ve her CI işinde tekrarlanır.

Tuist Paket Kayıt Defteri, Swift Package Index'in izlediği aynı paketleri sunar, ancak gerçek bir kayıt defteri olarak sunduğu için SwiftPM yalnızca gerçekten ihtiyacınız olan commit'i alır. `Tuist.swift` dosyanızda `registryEnabled: true` ayarını yaparak bir kez etkinleştirin:

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

Yeniden oluşturun. Paket çözümlemesi dakikalardan saniyelere düşer.

## Derleme içgörüsü

Xcode, hedef başına derleme sürelerini logda ve derleme raporunda kaydeder. Hiçbiri çalıştırmalar veya makineler arasında toplanmaz, bu nedenle derleme süresi gerilemesi genellikle yalnızca CI'nin genel olarak yavaşlaması olarak ortaya çıkar.

Derleme içgörüsü, oluşturulan şemalar için her derlemenin süresini ve aşama zamanlamalarını otomatik olarak kaydeder. Ekstra yapılandırılacak bir şey yoktur. Bir sonraki `tuist generate` + derleme döngünüzden sonra panonun **Derlemeler** sekmesini açın.

## Test içgörüsü

Xcode, test başına sonuçları tek tek çalıştırma bazında raporlar. Gerçekten ihtiyacınız olan çapraz-çalıştırma sinyalini toplamaz: kararsızlık oranı, hafta bazında süre, hangi simülatör varyantlarının başarısız olduğu.

Test içgörüsü, oluşturulan şemalar için her testin sonucunu ve süresini otomatik olarak kaydeder ve sonuçları çalıştırmalar arasında ilişkilendirir. Kararsız testler, yavaş testler ve başarısızlıklar panonun **Testler** sekmesinde görünür. Kararsızlıklar biriktiğinde, birleşmeleri engellemeyi durdurmaları için bunları panodan karantinaya alın.

## Takımı dahil edin

Modül önbelleği ve seçici test, herkes aynı ortak yüzeye hit ettiğinde en çok karşılık verir. Takım arkadaşlarınızı panodaki hesap ayarlarından organizasyona davet edin ve <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> (Google, Okta, Microsoft) kurulumunu yapın, böylece kişisel `tuist auth login` yerine onboarding bir tıklama olsun.
