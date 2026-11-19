---
{
  "title": "v3'ten v4'e",
  "titleTemplate": ":title · Geçişler · Referanslar · Tuist",
  "description": "Bu sayfa, Tuist CLI'ın sürüm 3'ten sürüm 4'e nasıl geçileceğini belgeler."
}
---
# Tuist v3'ten v4'e {#from-tuist-v3-to-v4}

[Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) sürümüyle birlikte, projeye uzun vadede kullanımını ve bakımını kolaylaştıracağına inandığımız bazı kırıcı değişiklikler getirme fırsatını değerlendirdik. Bu belge, Tuist 3'ten Tuist 4'e yükseltmek için projenizde yapmanız gereken değişiklikleri özetlemektedir.

## `tuistenv` aracılığıyla sürüm yönetimi kaldırıldı {#dropped-version-management-through-tuistenv}

Tuist 4 öncesinde, kurulum betiği `tuistenv` adlı bir araç kurar ve bu araç kurulum sırasında `tuist` olarak yeniden adlandırılırdı. Araç, ortamlar arasında determinizm sağlayarak Tuist sürümlerinin kurulması ve etkinleştirilmesini üstlenirdi. Tuist'in özellik yüzeyini azaltma amacıyla, aynı işi yapan ancak daha esnek olan ve farklı araçlar arasında kullanılabilen [Mise](https://mise.jdx.dev/) lehine `tuistenv` özelliğini kaldırmaya karar verdik. `tuistenv` kullanıyorsanız, `curl -Ls https://uninstall.tuist.io | bash` komutunu çalıştırarak mevcut Tuist sürümünü kaldırmanız ve ardından tercih ettiğiniz kurulum yöntemini kullanarak Tuist'i yeniden kurmanız gerekir. Ortamlar arasında sürümleri deterministik şekilde kurup etkinleştirebildiği için Mise kullanımını şiddetle tavsiye ediyoruz.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **CI ortamlarında ve Xcode projelerinde Mise**
>
> Mise'in sağladığı determinizmi benimsemeye karar verirseniz, Mise'i [CI ortamlarında](https://mise.jdx.dev/continuous-integration.html) ve [Xcode projelerinde](https://mise.jdx.dev/ide-integration.html#xcode) nasıl kullanacağınıza ilişkin belgelere göz atmanızı öneririz.


> [!NOTE]
> **Homebrew desteklenmektedir**
>
> macOS için popüler bir paket yöneticisi olan Homebrew kullanarak Tuist'i kurmaya devam edebileceğinizi unutmayın. Homebrew kullanarak Tuist'i nasıl kuracağınıza ilişkin talimatları <.localized_link href="/guides/install-tuist#recommended-homebrew">kurulum kılavuzunda</.localized_link> bulabilirsiniz.


## `init` modellerinden `ProjectDescription` yapıcıları kaldırıldı {#dropped-init-constructors-from-projectdescription-models}

API'lerin okunabilirliğini ve ifade gücünü artırmak amacıyla, tüm `ProjectDescription` modellerinden `init` yapıcılarını kaldırmaya karar verdik. Her model artık modellerin örneklerini oluşturmak için kullanabileceğiniz statik bir yapıcı sağlar. `init` yapıcılarını kullanıyorsanız, projenizi statik yapıcıları kullanacak şekilde güncellemeniz gerekecektir.

> [!TIP]
> **Adlandırma kuralı**
>
> Uyguladığımız adlandırma kuralı, statik yapıcının adı olarak modelin adını kullanmaktır. Örneğin, `Target` modeli için statik yapıcı `Target.target` şeklindedir.


## `--no-cache`, `--no-binary-cache` olarak yeniden adlandırıldı {#renamed-nocache-to-nobinarycache}

`--no-cache` bayrağı belirsiz olduğu için, ikili önbelleği referans aldığını netleştirmek amacıyla bunu `--no-binary-cache` olarak yeniden adlandırmaya karar verdik. `--no-cache` bayrağını kullanıyorsanız, projenizi bunun yerine `--no-binary-cache` bayrağını kullanacak şekilde güncellemeniz gerekecektir.

## `tuist fetch`, `tuist install` olarak yeniden adlandırıldı {#renamed-tuist-fetch-to-tuist-install}

Sektör standartlarıyla uyum sağlamak için `tuist fetch` komutunu `tuist install` olarak yeniden adlandırdık. `tuist fetch` komutunu kullanıyorsanız, projenizi bunun yerine `tuist install` komutunu kullanacak şekilde güncellemeniz gerekecektir.

## [Bağımlılıklar için DSL olarak `Package.swift` benimsenmesi](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4 öncesinde, bağımlılıkları bir `Dependencies.swift` dosyasında tanımlayabiliyordunuz. Bu özel format, [Dependabot](https://github.com/dependabot) veya [Renovatebot](https://github.com/renovatebot/renovate) gibi araçlarda bağımlılıkları otomatik olarak güncelleme desteğini bozuyordu. Ayrıca, kullanıcılar için gereksiz dolaylılıklar getiriyordu. Bu nedenle, Tuist'te bağımlılıkları tanımlamanın tek yolu olarak `Package.swift` benimsenmesine karar verdik. `Dependencies.swift` dosyasını kullanıyorsanız, içeriği `Tuist/Dependencies.swift` konumundan kök dizindeki bir `Package.swift` dosyasına taşımanız ve entegrasyonu yapılandırmak için `#if TUIST` yönergesini kullanmanız gerekecektir. Swift Package bağımlılıklarının nasıl entegre edileceği hakkında daha fazla bilgiyi <.localized_link href="/guides/features/projects/dependencies#swift-packages">buradan</.localized_link> okuyabilirsiniz.

## `tuist cache warm`, `tuist cache` olarak yeniden adlandırıldı {#renamed-tuist-cache-warm-to-tuist-cache}

Kısalık amacıyla, `tuist cache warm` komutunu `tuist cache` olarak yeniden adlandırmaya karar verdik. `tuist cache warm` komutunu kullanıyorsanız, projenizi bunun yerine `tuist cache` komutunu kullanacak şekilde güncellemeniz gerekecektir.


## `tuist cache print-hashes`, `tuist cache --print-hashes` olarak yeniden adlandırıldı {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` komutunu `tuist cache --print-hashes` olarak yeniden adlandırmaya karar verdik; böylece bunun bir `tuist cache` komutu bayrağı olduğu netleşti. `tuist cache print-hashes` komutunu kullanıyorsanız, projenizi bunun yerine `tuist cache --print-hashes` bayrağını kullanacak şekilde güncellemeniz gerekecektir.

## Önbellekleme profilleri kaldırıldı {#removed-caching-profiles}

Tuist 4 öncesinde, önbellek için bir yapılandırma içeren `Tuist/Config.swift` içinde önbellekleme profilleri tanımlayabiliyordunuz. Projeyi oluştururken kullanılan profil dışındaki bir profili oluşturma sürecinde kullanmanın kafa karışıklığına yol açabilmesi nedeniyle bu özelliği kaldırmaya karar verdik. Ayrıca, uygulamanın release sürümünü oluşturmak için debug profilinin kullanılması gibi beklenmeyen sonuçlara yol açabilirdi. Bunun yerine, projeyi oluştururken kullanmak istediğiniz yapılandırmayı belirtmenize olanak tanıyan `--configuration` seçeneğini sunduk. Önbellekleme profillerini kullanıyorsanız, projenizi bunun yerine `--configuration` seçeneğini kullanacak şekilde güncellemeniz gerekecektir.

## Argümanlar lehine `--skip-cache` kaldırıldı {#removed-skipcache-in-favor-of-arguments}

Hangi hedefler için ikili önbelleğin atlanacağını argümanlar kullanarak kontrol etmek amacıyla, `--skip-cache` bayrağını `generate` komutundan kaldırdık. `--skip-cache` bayrağını kullanıyorsanız, projenizi bunun yerine argümanları kullanacak şekilde güncellemeniz gerekecektir.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

## [İmzalama yetenekleri kaldırıldı](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

İmzalama, [Fastlane](https://fastlane.tools/) ve Xcode gibi topluluk araçları tarafından zaten çözülmüş durumda ve bu araçlar bu konuda çok daha iyi iş çıkarıyor. İmzalamanın Tuist için aşırı bir hedef olduğunu ve projenin temel özelliklerine odaklanmanın daha iyi olacağını düşündük. Depodaki sertifikaları ve profilleri şifreleyip oluşturma zamanında bunları doğru yerlere yüklemekten oluşan Tuist imzalama yeteneklerini kullanıyorsanız, bu mantığı proje oluşturmaktan önce çalışan kendi betiklerinizde yeniden uygulamak isteyebilirsiniz. Özellikle:
  - Dosya sisteminde veya bir ortam değişkeninde saklanan bir anahtar kullanarak sertifikaların ve profillerin şifresini çözen, sertifikaları anahtar zincirine ve sağlama profillerini `~/Library/MobileDevice/Provisioning\ Profiles` dizinine yükleyen bir betik.
  - Mevcut profilleri ve sertifikaları alıp şifreleyebilen bir betik.

> [!TIP]
> **İmzalama gereksinimleri**
>
> İmzalama için doğru sertifikaların anahtar zincirinde ve sağlama profillerinin `~/Library/MobileDevice/Provisioning\ Profiles` dizininde bulunması gerekir. Sertifikaları anahtar zincirine yüklemek için `security` komut satırı aracını ve sağlama profillerini doğru dizine kopyalamak için `cp` komutunu kullanabilirsiniz.


## `Dependencies.swift` aracılığıyla Carthage entegrasyonu kaldırıldı {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4 öncesinde, Carthage bağımlılıkları bir `Dependencies.swift` dosyasında tanımlanabiliyordu ve kullanıcılar bunları `tuist fetch` komutunu çalıştırarak indirebiliyordu. Ayrıca bunun Tuist için aşırı bir hedef olduğunu düşündük; özellikle Swift Package Manager'ın bağımlılık yönetimi için tercih edilen yöntem olacağı bir geleceği göz önüne aldığımızda. Carthage bağımlılıklarını kullanıyorsanız, önceden derlenmiş framework'leri ve XCFramework'leri Carthage'in standart dizinine çekmek için doğrudan `Carthage` kullanmanız ve ardından bu ikili dosyalara hedeflerinizden `TargetDependency.xcframework` ve `TargetDependency.framework` seçeneklerini kullanarak başvurmanız gerekecektir.

> [!NOTE]
> **Carthage hâlâ destekleniyor**
>
> Bazı kullanıcılar Carthage desteğini kaldırdığımızı sandı. Öyle değil. Tuist ile Carthage çıktısı arasındaki sözleşme, sistemde depolanan framework'lere ve XCFramework'lere yöneliktir. Değişen tek şey, bağımlılıkları indirmekten kimin sorumlu olduğu. Eskiden bu işi Carthage aracılığıyla Tuist yapıyordu, şimdi Carthage yapıyor.


## `TargetDependency.packagePlugin` API'si kaldırıldı {#dropped-the-targetdependencypackageplugin-api}

Tuist 4 öncesinde, bir paket eklentisi bağımlılığını `TargetDependency.packagePlugin` seçeneğini kullanarak tanımlayabilirdiniz. Swift Package Manager'ın yeni paket türlerini sunduğunu gördükten sonra, API'yi daha esnek ve geleceğe dönük hale getirmek üzere yinelemeye karar verdik. `TargetDependency.packagePlugin` kullanıyorsanız, bunun yerine `TargetDependency.package` kullanmanız ve kullanmak istediğiniz paket türünü bir argüman olarak iletmeniz gerekecektir.

## [Kullanımdan kaldırılmış API'ler kaldırıldı](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Tuist 3'te kullanımdan kaldırılmış olarak işaretlenen API'leri kaldırdık. Kullanımdan kaldırılmış API'lerden herhangi birini kullanıyorsanız, projenizi yeni API'leri kullanacak şekilde güncellemeniz gerekecektir.
