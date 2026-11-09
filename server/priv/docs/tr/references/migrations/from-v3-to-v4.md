---
{
  "title": "v3'ten v4'e",
  "titleTemplate": ":title · Geçişler · Referanslar · Tuist",
  "description": "Bu sayfa, Tuist CLI'nin 3. sürümden 4. sürüme nasıl geçileceğini belgeler."
}
---
# Tuist v3'ten v4'e {#from-tuist-v3-to-v4}

[Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) sürümünün yayınlanmasıyla, projeyi uzun vadede daha kolay kullanılabilir ve bakımı yapılabilir hale getireceğine inandığımız bazı kırıcı değişiklikler yapma fırsatını değerlendirdik. Bu belge, Tuist 3'ten Tuist 4'e yükseltmek için projenizde yapmanız gereken değişiklikleri özetlemektedir.

## `tuistenv` aracılığıyla sürüm yönetimi kaldırıldı {#dropped-version-management-through-tuistenv}

Tuist 4 öncesinde, kurulum betiği `tuistenv` adlı bir aracı kurar ve bu araç kurulum sırasında `tuist` olarak yeniden adlandırılırdı. Bu araç, Tuist sürümlerini kurup etkinleştirerek ortamlar arasında determinizm sağlardı. Tuist'in özellik yüzeyini küçültme amacıyla, `tuistenv` kullanımını bırakıp aynı işi yapan ancak daha esnek olan ve farklı araçlarla kullanılabilen [Mise](https://mise.jdx.dev/) aracını tercih ettik. `tuistenv` kullanıyorsanız, `curl -Ls https://uninstall.tuist.io | bash` komutunu çalıştırarak mevcut Tuist sürümünü kaldırmalı ve ardından tercih ettiğiniz kurulum yöntemiyle yeniden kurmalısınız. Ortamlar arasında sürümleri deterministik olarak kurup etkinleştirebildiği için Mise kullanımını şiddetle öneriyoruz.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **CI ortamlarında ve Xcode projelerinde Mise**
>
> Mise'in sunduğu determinizmi benimsemeye karar verirseniz, Mise'i [CI ortamlarında](https://mise.jdx.dev/continuous-integration.html) ve [Xcode projelerinde](https://mise.jdx.dev/ide-integration.html#xcode) nasıl kullanacağınıza ilişkin belgelere göz atmanızı öneririz.


> [!NOTE]
> **Homebrew desteklenmektedir**
>
> Tuist'i, macOS için popüler bir paket yöneticisi olan Homebrew kullanarak kurmaya devam edebileceğinizi unutmayın. Homebrew kullanarak Tuist'i nasıl kuracağınıza ilişkin talimatları <.localized_link href="/guides/install-tuist#recommended-homebrew">kurulum kılavuzunda</.localized_link> bulabilirsiniz.


## `init` oluşturucuları `ProjectDescription` modellerinden kaldırıldı {#dropped-init-constructors-from-projectdescription-models}

API'lerin okunabilirliğini ve ifade gücünü artırmak amacıyla, tüm `ProjectDescription` modellerinden `init` oluşturucularını kaldırmaya karar verdik. Her model artık modellerin örneklerini oluşturmak için kullanabileceğiniz statik bir oluşturucu sunar. `init` oluşturucularını kullanıyorsanız, projenizi bunun yerine statik oluşturucuları kullanacak şekilde güncellemeniz gerekecektir.

> [!TIP]
> **Adlandırma kuralı**
>
> Uyguladığımız adlandırma kuralı, statik oluşturucunun adı olarak modelin adını kullanmaktır. Örneğin, `Target` modeli için statik oluşturucu `Target.target` şeklindedir.


## `--no-cache`, `--no-binary-cache` olarak yeniden adlandırıldı {#renamed-nocache-to-nobinarycache}

`--no-cache` bayrağı belirsiz olduğu için, ikili önbelleği kastettiğini netleştirmek adına bunu `--no-binary-cache` olarak yeniden adlandırmaya karar verdik. `--no-cache` bayrağını kullanıyorsanız, projenizi bunun yerine `--no-binary-cache` bayrağını kullanacak şekilde güncellemeniz gerekecektir.

## `tuist fetch`, `tuist install` olarak yeniden adlandırıldı {#renamed-tuist-fetch-to-tuist-install}

Sektör standardıyla uyum sağlamak için `tuist fetch` komutunu `tuist install` olarak yeniden adlandırdık. `tuist fetch` komutunu kullanıyorsanız, projenizi bunun yerine `tuist install` komutunu kullanacak şekilde güncellemeniz gerekecektir.

## [Bağımlılıklar için DSL olarak `Package.swift` kabul edin](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4 öncesinde, bağımlılıkları bir `Dependencies.swift` dosyasında tanımlayabiliyordunuz. Bu tescilli format, bağımlılıkları otomatik olarak güncellemek için [Dependabot](https://github.com/dependabot) veya [Renovatebot](https://github.com/renovatebot/renovate) gibi araçlardaki desteği bozuyordu. Ayrıca, kullanıcılar için gereksiz dolaylılıklar getiriyordu. Bu nedenle, Tuist'te bağımlılıkları tanımlamanın tek yolu olarak `Package.swift` kullanımını benimsedik. `Dependencies.swift` dosyasını kullanıyorsanız, içeriğinizi `Tuist/Dependencies.swift` konumundan kök dizindeki bir `Package.swift` dosyasına taşımalı ve entegrasyonu yapılandırmak için `#if TUIST` yönergesini kullanmalısınız. Swift Package bağımlılıklarını nasıl entegre edeceğiniz hakkında daha fazla bilgiyi <.localized_link href="/guides/features/projects/dependencies#swift-packages">buradan</.localized_link> okuyabilirsiniz.

## `tuist cache warm`, `tuist cache` olarak yeniden adlandırıldı {#renamed-tuist-cache-warm-to-tuist-cache}

Kısalık amacıyla, `tuist cache warm` komutunu `tuist cache` olarak yeniden adlandırmaya karar verdik. `tuist cache warm` komutunu kullanıyorsanız, projenizi bunun yerine `tuist cache` komutunu kullanacak şekilde güncellemeniz gerekecektir.


## `tuist cache print-hashes`, `tuist cache --print-hashes` olarak yeniden adlandırıldı {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` komutunu `tuist cache --print-hashes` olarak yeniden adlandırmaya karar verdik; böylece bunun bir `tuist cache` komutu bayrağı olduğu netleşti. `tuist cache print-hashes` komutunu kullanıyorsanız, projenizi bunun yerine `tuist cache --print-hashes` bayrağını kullanacak şekilde güncellemeniz gerekecektir.

## Önbellekleme profilleri kaldırıldı {#removed-caching-profiles}

Tuist 4 öncesinde, önbellek yapılandırması içeren önbellekleme profillerini `Tuist/Config.swift` içinde tanımlayabiliyordunuz. Projeyi oluşturmak için kullanılan profil dışındaki bir profili oluşturma sürecinde kullanmanın kafa karışıklığına yol açabileceği gerekçesiyle bu özelliği kaldırmaya karar verdik. Ayrıca, bu durum kullanıcıların uygulamanın release sürümünü oluşturmak için debug profili kullanmasına ve beklenmeyen sonuçlara yol açmasına neden olabiliyordu. Bunun yerine, projeyi oluştururken kullanmak istediğiniz yapılandırmayı belirtmenize olanak tanıyan `--configuration` seçeneğini ekledik. Önbellekleme profillerini kullanıyorsanız, projenizi bunun yerine `--configuration` seçeneğini kullanacak şekilde güncellemeniz gerekecektir.

## Argümanlar lehine `--skip-cache` kaldırıldı {#removed-skipcache-in-favor-of-arguments}

İkili önbelleğin hangi hedefler için atlanacağını argümanlar kullanarak kontrol etmek amacıyla `--skip-cache` bayrağını `generate` komutundan kaldırdık. `--skip-cache` bayrağını kullanıyorsanız, projenizi bunun yerine argümanları kullanacak şekilde güncellemeniz gerekecektir.

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

İmzalama işlemi, bu konuda çok daha iyi iş çıkaran [Fastlane](https://fastlane.tools/) gibi topluluk araçları ve Xcode'un kendisi tarafından zaten çözülmüştür. İmzalamanın Tuist için zorlayıcı bir hedef olduğunu ve projenin çekirdek özelliklerine odaklanmanın daha iyi olacağını düşündük. Depodaki sertifikaları ve profilleri şifreleyip oluşturma zamanında doğru konumlara yüklemekten oluşan Tuist imzalama yeteneklerini kullanıyorsanız, bu mantığı proje oluşturmaktan önce çalışan kendi betiklerinizde çoğaltmak isteyebilirsiniz. Özellikle:
  - Dosya sisteminde veya bir ortam değişkeninde saklanan bir anahtar kullanarak sertifikaların ve profillerin şifresini çözen, sertifikaları anahtar zincirine ve sağlama profillerini `~/Library/MobileDevice/Provisioning\ Profiles` dizinine yükleyen bir betik.
  - Mevcut profilleri ve sertifikaları alıp bunları şifreleyebilen bir betik.

> [!TIP]
> **İmzalama gereksinimleri**
>
> İmzalama işlemi için doğru sertifikaların anahtar zincirinde ve sağlama profillerinin `~/Library/MobileDevice/Provisioning\ Profiles` dizininde bulunması gerekir. Sertifikaları anahtar zincirine yüklemek için `security` komut satırı aracını ve sağlama profillerini doğru dizine kopyalamak için `cp` komutunu kullanabilirsiniz.


## `Dependencies.swift` aracılığıyla Carthage entegrasyonu kaldırıldı {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4 öncesinde, Carthage bağımlılıkları bir `Dependencies.swift` dosyasında tanımlanabiliyordu ve kullanıcılar bunları `tuist fetch` komutunu çalıştırarak indirebiliyordu. Ayrıca bunun Tuist için zorlayıcı bir hedef olduğunu düşündük; özellikle Swift Package Manager'ın bağımlılık yönetimi için tercih edilen yöntem olacağı bir geleceği göz önünde bulundurduğumuzda. Carthage bağımlılıklarını kullanıyorsanız, önceden derlenmiş framework'leri ve XCFramework'leri Carthage'in standart dizinine çekmek için doğrudan `Carthage` kullanmanız ve ardından bu ikili dosyalara hedeflerinizden `TargetDependency.xcframework` ve `TargetDependency.framework` seçeneklerini kullanarak başvurmanız gerekecektir.

> [!NOTE]
> **Carthage hâlâ destekleniyor**
>
> Bazı kullanıcılar Carthage desteğini kaldırdığımızı düşündü. Böyle bir şey yapmadık. Tuist ile Carthage çıktısı arasındaki sözleşme, sistemde depolanan framework'lere ve XCFramework'lere yöneliktir. Değişen tek şey, bağımlılıkları indirmekten kimin sorumlu olduğu. Eskiden bu sorumluluk Carthage aracılığıyla Tuist'e aitti, şimdi ise Carthage'e ait.


## `TargetDependency.packagePlugin` API'si kaldırıldı {#dropped-the-targetdependencypackageplugin-api}

Tuist 4 öncesinde, bir paket eklentisi bağımlılığını `TargetDependency.packagePlugin` seçeneğini kullanarak tanımlayabiliyordunuz. Swift Package Manager'ın yeni paket türlerini sunduğunu gördükten sonra, API'yi daha esnek ve geleceğe hazır hale getirmek üzere yineledik. `TargetDependency.packagePlugin` kullanıyorsanız, bunun yerine `TargetDependency.package` kullanmanız ve kullanmak istediğiniz paket türünü bir argüman olarak iletmeniz gerekecektir.

## [Kullanımdan kaldırılmış API'ler kaldırıldı](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Tuist 3'te kullanımdan kaldırılmış olarak işaretlenen API'leri kaldırdık. Kullanımdan kaldırılmış API'lerden herhangi birini kullanıyorsanız, projenizi yeni API'leri kullanacak şekilde güncellemeniz gerekecektir.
