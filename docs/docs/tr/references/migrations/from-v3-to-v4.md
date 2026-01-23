---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# Tuist v3'ten v4'e {#from-tuist-v3-to-v4}

[Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) sürümünün
yayınlanmasıyla birlikte, projenin uzun vadede kullanımını ve bakımını
kolaylaştıracağına inandığımız bazı önemli değişiklikleri projeye dahil ettik.
Bu belge, Tuist 3'ten Tuist 4'e yükseltmek için projenizde yapmanız gereken
değişiklikleri özetlemektedir.

### `aracılığıyla bırakılan sürüm yönetimi tuistenv` {#dropped-version-management-through-tuistenv}

Tuist 4'ten önce, kurulum komut dosyası, kurulum sırasında `tuist` olarak
yeniden adlandırılan `tuistenv` adlı bir araç yüklerdi. Bu araç, Tuist
sürümlerinin kurulumunu ve etkinleştirilmesini sağlayarak ortamlar arasında
belirginliği garanti ederdi. Tuist'in özellik yüzeyini azaltmak amacıyla, aynı
işi yapan ancak daha esnek ve farklı araçlarda kullanılabilen
[Mise](https://mise.jdx.dev/) adlı aracı tercih ederek `tuistenv` 'yi kaldırmaya
karar verdik. `tuistenv` kullanıyorsanız, `curl -Ls https://uninstall.tuist.io |
bash` komutunu çalıştırarak Tuist'in mevcut sürümünü kaldırmanız ve ardından
tercih ettiğiniz yükleme yöntemini kullanarak yüklemeniz gerekir. Mise'nin,
ortamlar arasında deterministik olarak sürümleri yükleyip etkinleştirebildiği
için kullanımını şiddetle tavsiye ederiz.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: warning MISE IN CI ENVIRONMENTS AND XCODE PROJECTS
<!-- -->
Mise'nin genel olarak ortaya koyduğu determinizmi benimsemeye karar verirseniz,
Mise'yi [CI ortamlarında](https://mise.jdx.dev/continuous-integration.html) ve
[Xcode projelerinde](https://mise.jdx.dev/ide-integration.html#xcode) nasıl
kullanacağınız konusunda belgeleri incelemenizi öneririz.
<!-- -->
:::

::: info HOMEBREW IS SUPPORTED
<!-- -->
Tuist'i, macOS için popüler bir paket yöneticisi olan Homebrew kullanarak da
yükleyebileceğinizi unutmayın. Homebrew kullanarak Tuist'i yükleme talimatlarını
<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">kurulum
kılavuzunda</LocalizedLink> bulabilirsiniz.
<!-- -->
:::

### ` `init yapıcıları ProjectDescription modellerinden kaldırıldı.`` {#dropped-init-constructors-from-projectdescription-models}

API'lerin okunabilirliğini ve ifade gücünü artırmak amacıyla, tüm
`ProjectDescription` modellerinden `init` yapıcılarını kaldırmaya karar verdik.
Artık her model, modellerin örneklerini oluşturmak için kullanabileceğiniz
statik bir yapıcı sağlar. `init` yapıcılarını kullanıyorsanız, projenizi statik
yapıcıları kullanacak şekilde güncellemeniz gerekir.

::: tip NAMING CONVENTION
<!-- -->
İzlediğimiz adlandırma kuralı, statik yapıcı adı olarak modelin adını
kullanmaktır. Örneğin, `Target` modelinin statik yapıcı adı `Target.target`'dir.
<!-- -->
:::

### `--no-cache` adını `--no-binary-cache olarak değiştirdik.` {#renamed-nocache-to-nobinarycache}

`--no-cache` bayrağı belirsiz olduğu için, bunun ikili önbelleği ifade ettiğini
açıkça belirtmek amacıyla adını `--no-binary-cache` olarak değiştirmeye karar
verdik. `--no-cache` bayrağını kullanıyorsanız, projenizi `--no-binary-cache`
bayrağını kullanacak şekilde güncellemeniz gerekecektir.

### `tuist fetch` adını `tuist install olarak değiştirdi.` {#renamed-tuist-fetch-to-tuist-install}

`tuist fetch` komutunu, sektördeki genel uygulamaya uygun hale getirmek için
`tuist install` olarak yeniden adlandırdık. `tuist fetch` komutunu
kullanıyorsanız, projenizi `tuist install` komutunu kullanacak şekilde
güncellemeniz gerekecektir.

### [ `'yi bağımlılıklar için DSL olarak benimseyin. Package.swift` ](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4'ten önce, bağımlılıkları `Dependencies.swift` dosyasında
tanımlayabilirdiniz. Bu özel format, [Dependabot](https://github.com/dependabot)
veya [Renovatebot](https://github.com/renovatebot/renovate) gibi araçların
bağımlılıkları otomatik olarak güncelleme desteğini bozdu. Ayrıca, kullanıcılar
için gereksiz dolaylı işlemler getirdi. Bu nedenle, Tuist'te bağımlılıkları
tanımlamanın tek yolu olarak `Package.swift` kullanmaya karar verdik.
`Dependencies.swift` dosyasını kullanıyorsanız, içeriği
`Tuist/Dependencies.swift` kök dizinindeki `Package.swift` dosyasına taşıyın ve
entegrasyonu yapılandırmak için `#if TUIST` yönergesini kullanın. Swift paketi
bağımlılıklarını entegre etme hakkında daha fazla bilgiyi
<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">burada
bulabilirsiniz.</LocalizedLink>

### `tuist cache warm` adını `tuist cache olarak değiştirdi.` {#renamed-tuist-cache-warm-to-tuist-cache}

Kısalık için, `tuist cache warm` komutunu `tuist cache` olarak yeniden
adlandırmaya karar verdik. `tuist cache warm` komutunu kullanıyorsanız,
projenizi `tuist cache` komutunu kullanacak şekilde güncellemeniz gerekecektir.


### `tuist cache print-hashes` adını `tuist cache --print-hashes olarak değiştirdik.` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` komutunu, `tuist cache --print-hashes` olarak yeniden
adlandırmaya karar verdik. Böylece, bu komutun `tuist cache` komutunun bir
bayrağı olduğu açıkça anlaşılacaktır. `tuist cache print-hashes` komutunu
kullanıyorsanız, projenizi `tuist cache --print-hashes` bayrağını kullanacak
şekilde güncellemeniz gerekecektir.

### Önbellek profilleri kaldırıldı {#removed-caching-profiles}

Tuist 4'ten önce, önbellek için bir yapılandırma içeren `Tuist/Config.swift`
adresinde önbellek profilleri tanımlayabilirdiniz. Bu özelliği kaldırmaya karar
verdik, çünkü projeyi oluşturmak için kullanılan profilden farklı bir profil ile
oluşturma sürecinde kullanıldığında karışıklığa yol açabilirdi. Ayrıca,
kullanıcıların hata ayıklama profilini kullanarak uygulamanın sürümünü
oluşturmalarına yol açabilir ve bu da beklenmedik sonuçlara neden olabilir.
Bunun yerine, projeyi oluştururken kullanmak istediğiniz yapılandırmayı
belirtmek için kullanabileceğiniz `--configuration` seçeneğini ekledik. Önbellek
profilleri kullanıyorsanız, projenizi `--configuration` seçeneğini kullanacak
şekilde güncellemeniz gerekir.

### `--skip-cache` argümanları lehine kaldırıldı. {#removed-skipcache-in-favor-of-arguments}

`--skip-cache` bayrağını `generate` komutundan kaldırdık ve bunun yerine
argümanları kullanarak ikili önbelleğin hangi hedefler için atlanacağını kontrol
etmeyi tercih ettik. `--skip-cache` bayrağını kullanıyorsanız, projenizi
argümanları kullanacak şekilde güncellemeniz gerekecektir.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [İmza yetenekleri kaldırıldı](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

İmzalama işlemi, [Fastlane](https://fastlane.tools/) ve Xcode gibi topluluk
araçları tarafından zaten çözülmüştür ve bu araçlar bu işi çok daha iyi
yapmaktadır. İmzalama işleminin Tuist için zor bir hedef olduğunu ve projenin
temel özelliklerine odaklanmanın daha iyi olacağını düşündük. Depodaki
sertifikaları ve profilleri şifreleyip, oluşturma sırasında doğru yerlere
yükleyen Tuist imzalama özelliklerini kullanıyorsanız, bu mantığı proje
oluşturma öncesinde çalışan kendi komut dosyalarınızda da kullanmak
isteyebilirsiniz. Özellikle:
  - Dosya sisteminde veya bir ortam değişkeninde depolanan bir anahtar
    kullanarak sertifikaları ve profilleri şifresini çözen ve sertifikaları
    anahtar zincirine, provizyon profillerini ise
    `~/Library/MobileDevice/Provisioning\ Profiles` dizinine yükleyen bir komut
    dosyası.
  - Mevcut profilleri ve sertifikaları alıp şifreleyebilen bir komut dosyası.

::: tip SIGNING REQUIREMENTS
<!-- -->
İmzalama işlemi için anahtar zincirinde doğru sertifikaların ve
`~/Library/MobileDevice/Provisioning\ Profiles` dizininde provizyon
profillerinin bulunması gerekir. Anahtar zincirine sertifikaları yüklemek için
`security` komut satırı aracını, provizyon profillerini doğru dizine kopyalamak
için `cp` komutunu kullanabilirsiniz.
<!-- -->
:::

### `Dependencies.swift aracılığıyla Carthage entegrasyonu kaldırıldı.` {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4'ten önce, Carthage bağımlılıkları `Dependencies.swift` dosyasında
tanımlanabilirdi ve kullanıcılar `tuist fetch` komutunu çalıştırarak bu dosyayı
alabilirdi. Ayrıca, özellikle Swift paketi'nin bağımlılıkları yönetmek için
tercih edilen yöntem olacağı bir gelecek göz önüne alındığında, bunun Tuist için
zor bir hedef olduğunu düşündük. Carthage bağımlılıkları kullanıyorsanız,
`Carthage` adresini doğrudan kullanarak önceden derlenmiş çerçeveleri ve
XCFrameworks'ü Carthage'ın standart dizinine çekmeniz ve ardından
`TargetDependency.xcframework` ve `TargetDependency.framework` örneklerini
kullanarak hedeflerinizden bu ikili dosyalara referans vermeniz gerekir.

::: info CARTHAGE IS STILL SUPPORTED
<!-- -->
Bazı kullanıcılar Carthage desteğini bıraktığımızı sandılar. Öyle bir şey yok.
Tuist ve Carthage arasındaki sözleşme, sistemde depolanan çerçeveler ve
XCFrameworks ile ilgilidir. Değişen tek şey, bağımlılıkları getirme
sorumluluğunun kimde olduğu. Eskiden bu sorumluluk Carthage aracılığıyla Tuist'e
aitti, şimdi ise Carthage'a ait.
<!-- -->
:::

### `TargetDependency.packagePlugin` API kaldırıldı. {#dropped-the-targetdependencypackageplugin-api}

Tuist 4'ten önce, `TargetDependency.packagePlugin` durumunu kullanarak bir paket
eklenti bağımlılığını tanımlayabilirdiniz. Swift paketi'nin yeni paket türleri
tanıttığını gördükten sonra, API'yi daha esnek ve geleceğe dönük bir hale
getirmek için yenilemeye karar verdik. `TargetDependency.packagePlugin`
kullanıyorsanız, bunun yerine `TargetDependency.package` kullanmanız ve
kullanmak istediğiniz paket türünü argüman olarak geçirmeniz gerekecektir.

### [Kullanımdan kaldırılan API'lar](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Tuist 3'te kullanımdan kaldırılmış olarak işaretlenen API'leri kaldırdık.
Kullanımdan kaldırılmış API'lerden herhangi birini kullanıyorsanız, yeni
API'leri kullanmak için projenizi güncellemeniz gerekecektir.
