---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# Tuist v3'ten v4'e {#from-tuist-v3-to-v4}

Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) sürümüyle birlikte,
projenin uzun vadede kullanımını ve bakımını daha kolay hale getireceğine
inandığımız bazı değişiklikleri projeye ekleme fırsatını yakaladık. Bu belge,
Tuist 3'ten Tuist 4'e yükseltmek için projenizde yapmanız gereken değişiklikleri
özetlemektedir.

### `tuistenv aracılığıyla sürüm yönetimi bırakıldı` {#dropped-version-management-through-tuistenv}

Tuist 4'ten önce, kurulum betiği, kurulum sırasında `tuist` olarak yeniden
adlandırılacak olan `tuistenv` adlı bir araç yüklüyordu. Bu araç, Tuist'in
sürümlerinin yüklenmesi ve etkinleştirilmesiyle ilgilenerek ortamlar arasında
determinizm sağlıyordu. Tuist'in özellik yüzeyini azaltmak amacıyla, aynı işi
yapan ancak daha esnek olan ve farklı araçlar arasında kullanılabilen bir araç
olan [Mise](https://mise.jdx.dev/) lehine `tuistenv` adresini bırakmaya karar
verdik. Eğer `tuistenv` kullanıyorsanız, `curl -Ls https://uninstall.tuist.io |
bash` çalıştırarak Tuist'in mevcut sürümünü kaldırmanız ve ardından seçtiğiniz
kurulum yöntemini kullanarak yüklemeniz gerekecektir. Mise kullanımını şiddetle
tavsiye ediyoruz çünkü sürümleri ortamlar arasında kararlı bir şekilde
yükleyebilir ve etkinleştirebilir.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: warning MISE IN CI ENVIRONMENTS AND XCODE PROJECTS
<!-- -->
Mise'ın getirdiği determinizmi benimsemeye karar verirseniz, Mise'ın [CI
ortamlarında](https://mise.jdx.dev/continuous-integration.html) ve [Xcode
projelerinde](https://mise.jdx.dev/ide-integration.html#xcode) nasıl
kullanılacağına ilişkin belgelere göz atmanızı öneririz.
<!-- -->
:::

::: info HOMEBREW IS SUPPORTED
<!-- -->
Tuist'i macOS için popüler bir paket yöneticisi olan Homebrew kullanarak da
yükleyebileceğinizi unutmayın. Tuist'in Homebrew kullanılarak nasıl kurulacağına
ilişkin talimatları
<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">kurulum kılavuzunda</LocalizedLink> bulabilirsiniz.
<!-- -->
:::

### `init` kurucuları `ProjectDescription` modellerinden çıkarıldı {#dropped-init-constructors-from-projectdescription-models}

API'lerin okunabilirliğini ve ifade gücünü artırmak amacıyla, `init`
yapıcılarını tüm `ProjectDescription` modellerinden kaldırmaya karar verdik.
Artık her model, modellerin örneklerini oluşturmak için kullanabileceğiniz
statik bir kurucu sağlamaktadır. Eğer `init` kurucularını kullanıyorsanız, bunun
yerine statik kurucuları kullanmak için projenizi güncellemeniz gerekecektir.

::: tip NAMING CONVENTION
<!-- -->
İzlediğimiz adlandırma kuralı, modelin adını statik kurucunun adı olarak
kullanmaktır. Örneğin, `Target` modeli için statik kurucu `Target.target`
şeklindedir.
<!-- -->
:::

### `--no-cache` adresi `--no-binary-cache olarak değiştirildi` {#renamed-nocache-to-nobinarycache}

`--no-cache` bayrağı belirsiz olduğundan, ikili önbelleğe atıfta bulunduğunu
açıkça belirtmek için `--no-binary-cache` olarak yeniden adlandırmaya karar
verdik. Eğer `--no-cache` bayrağını kullanıyorsanız, bunun yerine
`--no-binary-cache` bayrağını kullanmak için projenizi güncellemeniz
gerekecektir.

### `tuist fetch` adresinin adı `tuist install olarak değiştirildi` {#renamed-tuist-fetch-to-tuist-install}

`tuist fetch` komutunu endüstri kurallarına uygun hale getirmek için `tuist
install` olarak yeniden adlandırdık. Eğer `tuist fetch` komutunu
kullanıyorsanız, bunun yerine `tuist install` komutunu kullanmak için projenizi
güncellemeniz gerekecektir.

### [Bağımlılıklar için DSL olarak `Package.swift` adresini benimseyin](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4'ten önce, bağımlılıkları bir `Dependencies.swift` dosyasında
tanımlayabilirdiniz. Bu tescilli format,
[Dependabot](https://github.com/dependabot) veya
[Renovatebot](https://github.com/renovatebot/renovate) gibi araçların
bağımlılıkları otomatik olarak güncelleme desteğini bozuyordu. Dahası,
kullanıcılar için gereksiz dolaylamalar getiriyordu. Bu nedenle, Tuist'te
bağımlılıkları tanımlamanın tek yolu olarak `Package.swift` adresini benimsemeye
karar verdik. Eğer `Dependencies.swift` dosyasını kullanıyorsanız, içeriği
`Tuist/Dependencies.swift` dosyanızdan kök dizindeki `Package.swift` dosyasına
taşımanız ve entegrasyonu yapılandırmak için `#if TUIST` yönergesini kullanmanız
gerekir. Swift paketi bağımlılıklarının nasıl entegre edileceği hakkında daha
fazla bilgiyi
<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">buradan okuyabilirsiniz</LocalizedLink>

### `tuist önbelleği sıcak` olarak `tuist önbelleği olarak yeniden adlandırıldı` {#renamed-tuist-cache-warm-to-tuist-cache}

Kısalık için, `tuist cache warm` komutunu `tuist cache` olarak yeniden
adlandırmaya karar verdik. Eğer `tuist cache warm` komutunu kullanıyorsanız,
bunun yerine `tuist cache` komutunu kullanmak için projenizi güncellemeniz
gerekecektir.


### `tuist cache print-hashes` adresini `tuist cache --print-hashes olarak değiştirdi` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` komutunu, `tuist cache` komutunun bir bayrağı
olduğunu açıkça belirtmek için `tuist cache --print-hashes` olarak yeniden
adlandırmaya karar verdik. Eğer `tuist cache print-hashes` komutunu
kullanıyorsanız, bunun yerine `tuist cache --print-hashes` bayrağını kullanmak
için projenizi güncellemeniz gerekecektir.

### Önbelleğe alma profilleri kaldırıldı {#removed-caching-profiles}

Tuist 4'ten önce, önbellek için bir yapılandırma içeren `Tuist/Config.swift`
adresinde önbellek profillerini tanımlayabiliyordunuz. Bu özelliği kaldırmaya
karar verdik çünkü projeyi oluşturmak için kullanılandan başka bir profille
oluşturma sürecinde kullanıldığında karışıklığa yol açabilirdi. Ayrıca,
kullanıcıların uygulamanın yayın sürümünü oluşturmak için bir hata ayıklama
profili kullanmasına neden olabilir ve bu da beklenmedik sonuçlara yol açabilir.
Bunun yerine, projeyi oluştururken kullanmak istediğiniz yapılandırmayı
belirtmek için kullanabileceğiniz `--configuration` seçeneğini getirdik.
Önbelleğe alma profilleri kullanıyorsanız, bunun yerine `--configuration`
seçeneğini kullanmak için projenizi güncellemeniz gerekecektir.

### `--skip-cache` argümanları lehine kaldırıldı {#removed-skipcache-in-favor-of-arguments}

`--skip-cache` bayrağını, argümanları kullanarak ikili önbelleğin hangi hedefler
için atlanacağını kontrol etmek için `generate` komutundan kaldırdık. Eğer
`--skip-cache` bayrağını kullanıyorsanız, bunun yerine argümanları kullanmak
için projenizi güncellemeniz gerekecektir.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [İmzalama yetenekleri düştü](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

İmzalama, [Fastlane](https://fastlane.tools/) ve Xcode'un kendisi gibi topluluk
araçları tarafından zaten çözülmüştür ve bu konuda çok daha iyi bir iş
çıkarmaktadır. İmzalamanın Tuist için uzun vadeli bir hedef olduğunu ve projenin
temel özelliklerine odaklanmanın daha iyi olacağını düşündük. Depodaki
sertifikaları ve profilleri şifrelemek ve bunları oluşturma sırasında doğru
yerlere yüklemekten oluşan Tuist imzalama yeteneklerini kullanıyorsanız, bu
mantığı proje oluşturmadan önce çalışan kendi komut dosyalarınızda çoğaltmak
isteyebilirsiniz. Özellikle:
  - Dosya sisteminde veya bir ortam değişkeninde depolanan bir anahtarı
    kullanarak sertifikaların ve profillerin şifresini çözen ve sertifikaları
    anahtar zincirine ve provizyon profillerini
    `~/Library/MobileDevice/Provisioning\ Profiles` dizinine yükleyen bir komut
    dosyası.
  - Mevcut profilleri ve sertifikaları alıp şifreleyebilen bir betik.

::: tip SIGNING REQUIREMENTS
<!-- -->
İmzalama için anahtar zincirinde doğru sertifikaların bulunması ve provizyon
profillerinin `~/Library/MobileDevice/Provisioning\ Profiles` dizininde
bulunması gerekir. Anahtar zincirine sertifika yüklemek için `security` komut
satırı aracını ve provizyon profillerini doğru dizine kopyalamak için `cp`
komutunu kullanabilirsiniz.
<!-- -->
:::

### `Dependencies.swift aracılığıyla Carthage entegrasyonu bırakıldı` {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4'ten önce, Carthage bağımlılıkları bir `Dependencies.swift` dosyasında
tanımlanabiliyordu ve kullanıcılar bu dosyayı `tuist fetch` çalıştırarak
getirebiliyordu. Ayrıca, özellikle Swift paketi Paket Yöneticisinin
bağımlılıkları yönetmek için tercih edilen yol olacağı bir geleceği göz önünde
bulundurarak, bunun Tuist için zorlayıcı bir hedef olduğunu düşündük. Carthage
bağımlılıklarını kullanıyorsanız, önceden derlenmiş çerçeveleri ve
XCFrameworks'ü Carthage'ın standart dizinine çekmek için doğrudan `Carthage`
kullanmanız ve ardından `TargetDependency.xcframework` ve
`TargetDependency.framework` durumlarını kullanarak etiketlerinizden bu ikili
dosyalara başvurmanız gerekir.

::: info CARTHAGE IS STILL SUPPORTED
<!-- -->
Bazı kullanıcılar Carthage desteğini bıraktığımızı anladı. Biz bırakmadık. Tuist
ve Carthage'ın çıktısı arasındaki sözleşme, sistemde depolanan çerçevelere ve
XCFrameworks'e yöneliktir. Değişen tek şey bağımlılıkların getirilmesinden kimin
sorumlu olduğudur. Eskiden Carthage aracılığıyla Tuist'ti, şimdi Carthage.
<!-- -->
:::

### `TargetDependency.packagePlugin` API'sini bıraktı {#dropped-the-targetdependencypackageplugin-api}

Tuist 4'ten önce, `TargetDependency.packagePlugin` durumunu kullanarak bir paket
eklentisi bağımlılığı tanımlayabiliyordunuz. Swift paketi Paket Yöneticisinin
yeni paket türlerini tanıttığını gördükten sonra, API'yi daha esnek ve geleceğe
dönük olacak şekilde yinelemeye karar verdik. Eğer
`TargetDependency.packagePlugin` kullanıyorsanız, bunun yerine
`TargetDependency.package` kullanmanız ve kullanmak istediğiniz paket türünü bir
argüman olarak iletmeniz gerekecektir.

### [Kullanımdan kaldırılan API'ler](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Tuist 3'te kullanımdan kaldırılmış olarak işaretlenen API'leri kaldırdık.
Kullanımdan kaldırılmış API'lerden herhangi birini kullanıyorsanız, yeni
API'leri kullanmak için projenizi güncellemeniz gerekecektir.
