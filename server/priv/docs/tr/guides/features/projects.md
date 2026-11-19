---
{
  "title": "Projeler",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode projelerini Swift ile tanımlayın ve Tuist ile tutarlı bir şekilde oluşturun. Birleştirme çakışmalarını ortadan kaldırın, bağımlılıkları bir graf olarak modelleyin ve modül önbelleğinin kilidini açın."
}
---
# Oluşturulan projeler {#generated-projects}

Tuist Oluşturulan Projeler, karmaşıklığı ve maliyetleri kabul edilebilir düzeyde tutarken bu zorlukların üstesinden gelmeye yardımcı olan uygulanabilir bir alternatiftir. Xcode projelerini temel bir unsur olarak ele alır, gelecekteki Xcode güncellemelerine karşı dayanıklılığı sağlar ve ekiplere modülerleştirme odaklı bildirimsel bir API sunmak için Xcode proje oluşturma özelliğinden yararlanır. Tuist, proje tanımını kullanarak modülerleştirmenin karmaşıklıklarını basitleştirir, çeşitli ortamlarda derleme veya test gibi iş akışlarını optimize eder ve Xcode projelerinin evrimini kolaylaştırıp yaygınlaştırır.

## Nasıl çalışır? {#how-does-it-work}

Oluşturulan projelerle başlamak için tek ihtiyacınız olan, projenizi **Tuist'in Alana Özgü Dili (DSL)** kullanarak tanımlamaktır. Bu, `Workspace.swift` veya `Project.swift` gibi manifest dosyalarının kullanılmasını gerektirir. Daha önce Swift Package Manager ile çalıştıysanız yaklaşım oldukça benzerdir.

Projenizi tanımladıktan sonra Tuist, onu yönetmek ve etkileşimde bulunmak için çeşitli iş akışları sunar:

- **Oluştur:** Bu temel bir iş akışıdır. Xcode ile uyumlu bir Xcode projesi oluşturmak için kullanın.
- **<.localized_link href="/cli/build">Derle</.localized_link>:** Bu iş akışı yalnızca Xcode projesini oluşturmaz, aynı zamanda onu derlemek için `xcodebuild` kullanır.
- **<.localized_link href="/cli/test">Test Et</.localized_link>:** Derleme iş akışına çok benzer şekilde çalışan bu akış, yalnızca Xcode projesini oluşturmaz, aynı zamanda onu test etmek için `xcodebuild` kullanır.

## Xcode projeleriyle ilgili zorluklar {#challenges-with-xcode-projects}

Xcode projeleri büyüdükçe, güvenilir olmayan artımlı derlemeler, sorunlarla karşılaşan geliştiriciler tarafından Xcode'un genel önbelleğinin sıkça temizlenmesi ve kırılgan proje yapılandırmaları gibi çeşitli faktörler nedeniyle **kuruluşlarda verimlilik düşüşü yaşanabilir**. Hızlı özellik geliştirmeyi sürdürmek için kuruluşlar genellikle çeşitli stratejileri araştırır.

Bazı kuruluşlar, [React Native](https://reactnative.dev/) gibi JavaScript tabanlı dinamik çalışma zamanları kullanarak platformu soyutlayıp derleyiciyi atlamayı tercih eder. Bu yaklaşım etkili olabilir ancak [platformun yerel özelliklerine erişimi karmaşıklaştırır](https://shopify.engineering/building-app-clip-react-native). Diğer kuruluşlar **kod tabanını modülerleştirmeyi** tercih eder; bu, net sınırlar belirlemeye yardımcı olur, kod tabanı üzerinde çalışmayı kolaylaştırır ve derleme sürelerinin güvenilirliğini artırır. Ancak Xcode proje formatı modülerlik için tasarlanmamıştır ve az kişinin anladığı örtük yapılandırmalar ile sık çatışmalarla sonuçlanır. Bu durum düşük bus factor'a yol açar ve artımlı derlemeler iyileşse bile geliştiriciler derlemeler başarısız olduğunda Xcode'un derleme önbelleğini (yani türetilmiş verileri) sıkça temizlemeye devam edebilir. Bunu çözmek için bazı kuruluşlar **Xcode'un derleme sistemini terk etmeyi** ve [Buck](https://buck.build/) veya [Bazel](https://bazel.build/) gibi alternatifleri benimsemeyi seçer. Ancak bu, [yüksek karmaşıklık ve bakım yükü](https://bazel.build/migrate/xcode) getirir.


## Alternatifler {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager (SPM) öncelikli olarak bağımlılıklara odaklanırken Tuist farklı bir yaklaşım sunar. Tuist ile yalnızca SPM entegrasyonu için paketler tanımlamazsınız; projeler, çalışma alanları, hedefler ve şemalar gibi tanıdık kavramları kullanarak projelerinizi şekillendirirsiniz.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen), iş birlikçi Xcode projelerindeki çatışmaları azaltmak ve Xcode'un iç işleyişindeki bazı karmaşıklıkları basitleştirmek amacıyla tasarlanmış özel bir proje oluşturucudur. Ancak projeler [YAML](https://yaml.org/) gibi serileştirilebilir formatlar kullanılarak tanımlanır. Swift'in aksine bu, geliştiricilerin ek araçlar eklemeden soyutlamalar veya kontroller üzerine inşa etmesine olanak tanımaz. XcodeGen, bağımlılıkları doğrulama ve optimizasyon için dahili bir temsile eşlemenin bir yolunu sunsa da geliştiricileri yine de Xcode'un inceliklerine maruz bırakır. Bu durum, Bazel topluluğunda görüldüğü gibi XcodeGen'i [araçlar oluşturmak](https://github.com/MobileNativeFoundation/rules_xcodeproj) için uygun bir temel yapabilir ancak sağlıklı ve üretken bir ortamı sürdürmeyi amaçlayan kapsayıcı proje evrimi için optimal değildir. Bugün XcodeGen kullanıyorsanız [XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen), mevcut XcodeGen projenizle hangi Tuist özelliklerinin çalıştığını açıklar; Tuist oluşturulan projelere geçmek için <.localized_link href="/guides/features/projects/adoption/migrate/xcodegen-project">migrasyon kılavuzuna</.localized_link> bakın.

### Bazel {#bazel}

[Bazel](https://bazel.build), uzak önbelleğe alma özellikleriyle tanınan gelişmiş bir derleme sistemidir ve Swift topluluğunda öncelikle bu yeteneği sayesinde popülerlik kazanmıştır. Ancak Xcode'un ve derleme sisteminin sınırlı genişletilebilirliği göz önüne alındığında, bunu Bazel'in sistemiyle değiştirmek önemli çaba ve bakım gerektirir. Yalnızca bol kaynaklara sahip birkaç şirket bu ek yükü karşılayabilir; bunu Bazel'i Xcode ile entegre etmek için yoğun yatırım yapan seçili şirket listesinden görmek mümkündür. İlginç bir şekilde topluluk, bir Xcode projesi oluşturmak için Bazel'in XcodeGen'ini kullanan bir [araç](https://github.com/MobileNativeFoundation/rules_xcodeproj) geliştirdi. Bu, Bazel dosyalarından XcodeGen YAML'e ve nihayetinde Xcode Projelerine uzanan karmaşık bir dönüşüm zinciriyle sonuçlanır. Böyle katmanlı dolaylılık genellikle sorun gidermeyi karmaşıklaştırarak sorunların teşhis edilmesini ve çözülmesini daha zor hale getirir.
