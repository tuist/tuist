---
{
  "title": "Projeler",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode projelerini Swift ile tanımlayın ve Tuist ile tutarlı bir şekilde oluşturun. Birleştirme çakışmalarını ortadan kaldırın, bağımlılıkları bir graf olarak modelleyin ve modül önbelleğinin kilidini açın."
}
---
# Oluşturulan projeler {#generated-projects}

Tuist Oluşturulan Projeler, karmaşıklığı ve maliyetleri kabul edilebilir düzeyde tutarken bu zorlukların aşılmasına yardımcı olan uygulanabilir bir alternatiftir. Xcode projelerini temel bir unsur olarak ele alır, gelecekteki Xcode güncellemelerine karşı dayanıklılığı sağlar ve ekiplere modülerleştirme odaklı deklaratif bir API sunmak için Xcode proje oluşturma özelliğinden yararlanır. Tuist, proje tanımını kullanarak modülerleştirmenin karmaşıklıklarını basitleştirir, çeşitli ortamlarda derleme veya test gibi iş akışlarını optimize eder ve Xcode projelerinin evrimini kolaylaştırıp demokratikleştirir.

## Nasıl çalışır? {#how-does-it-work}

Oluşturulan projelerle başlamak için tek ihtiyacınız olan, projenizi **Tuist'in Alana Özgü Dilini (DSL)** kullanarak tanımlamaktır. Bu, `Workspace.swift` veya `Project.swift` gibi manifest dosyalarının kullanılmasını gerektirir. Daha önce Swift Package Manager ile çalıştıysanız, yaklaşım oldukça benzerdir.

Projenizi tanımladıktan sonra Tuist, onu yönetmek ve etkileşimde bulunmak için çeşitli iş akışları sunar:

- **Oluştur:** Bu temel bir iş akışıdır. Xcode ile uyumlu bir Xcode projesi oluşturmak için kullanın.
- **<.localized_link href="/cli/build">Derle</.localized_link>:** Bu iş akışı yalnızca Xcode projesini oluşturmaz, aynı zamanda onu derlemek için `xcodebuild` kullanır.
- **<.localized_link href="/cli/test">Test Et</.localized_link>:** Derleme iş akışına benzer şekilde çalışan bu süreç, yalnızca Xcode projesini oluşturmaz, aynı zamanda onu test etmek için `xcodebuild` kullanır.

## Xcode projeleriyle ilgili zorluklar {#challenges-with-xcode-projects}

Xcode projeleri büyüdükçe, **organizasyonlar verimlilikte düşüş yaşayabilir;** bunun nedenleri arasında güvenilmez artımlı derlemeler, sorunlarla karşılaşan geliştiriciler tarafından Xcode'un genel önbelleğinin sıkça temizlenmesi ve kırılgan proje yapılandırmaları yer alır. Hızlı özellik geliştirmeyi sürdürmek için organizasyonlar genellikle çeşitli stratejileri değerlendirir.

Bazı organizasyonlar, platformu [React Native](https://reactnative.dev/) gibi JavaScript tabanlı dinamik çalışma zamanları kullanarak soyutlayarak derleyiciyi atlamayı tercih eder. Bu yaklaşım etkili olabilir ancak [platformun yerel özelliklerine erişimi karmaşıklaştırır](https://shopify.engineering/building-app-clip-react-native). Diğer organizasyonlar **kod tabanını modülerleştirmeyi** seçer; bu, net sınırlar belirlemeye yardımcı olur, kod tabanı üzerinde çalışmayı kolaylaştırır ve derleme sürelerinin güvenilirliğini artırır. Ancak Xcode proje formatı modülerlik için tasarlanmamıştır ve az kişinin anladığı örtük yapılandırmalarla sık çatışmalara yol açar. Bu durum düşük bus factor'a neden olur ve artımlı derlemeler iyileşse bile geliştiriciler derlemeler başarısız olduğunda Xcode'un derleme önbelleğini (yani derived data) sıkça temizlemeye devam edebilir. Bunu çözmek için bazı organizasyonlar **Xcode'un derleme sistemini terk etmeyi** ve [Buck](https://buck.build/) ya da [Bazel](https://bazel.build/) gibi alternatifleri benimsemeyi seçer. Ancak bu, [yüksek karmaşıklık ve bakım yükü](https://bazel.build/migrate/xcode) getirir.


## Alternatifler {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager (SPM) öncelikle bağımlılıklara odaklanırken Tuist farklı bir yaklaşım sunar. Tuist ile yalnızca SPM entegrasyonu için paketler tanımlamazsınız; projeler, çalışma alanları, hedefler ve şemalar gibi tanıdık kavramları kullanarak projelerinizi şekillendirirsiniz.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen), iş birliğine dayalı Xcode projelerindeki çatışmaları azaltmak ve Xcode'un iç işleyişindeki bazı karmaşıklıkları basitleştirmek amacıyla tasarlanmış özel bir proje oluşturucudur. Ancak projeler, [YAML](https://yaml.org/) gibi serileştirilebilir formatlar kullanılarak tanımlanır. Swift'in aksine bu yaklaşım, ek araçlar eklemeden soyutlamalar veya kontroller üzerine inşa edilmesine olanak tanımaz. XcodeGen, bağımlılıkları doğrulama ve optimizasyon amacıyla dahili bir temsille eşleştirmenin bir yolunu sunsa da geliştiricileri yine de Xcode'un inceliklerine maruz bırakır. Bu durum, Bazel topluluğunda görüldüğü gibi XcodeGen'i [araç geliştirmek](https://github.com/MobileNativeFoundation/rules_xcodeproj) için uygun bir temel yapabilir ancak sağlıklı ve üretken bir ortamı sürdürmeyi amaçlayan kapsayıcı proje evrimi için optimal değildir. Günümüzde XcodeGen kullanıyorsanız [XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen), mevcut XcodeGen projenizle hangi Tuist yeteneklerinin çalıştığını açıklar; Tuist oluşturulan projelere geçiş yapmak için <.localized_link href="/guides/features/projects/adoption/migrate/xcodegen-project">geçiş kılavuzuna</.localized_link> bakın.

### Bazel {#bazel}

[Bazel](https://bazel.build), uzak önbellek özellikleriyle tanınan ileri düzey bir derleme sistemidir ve Swift topluluğunda öncelikle bu yeteneği sayesinde popülerlik kazanmıştır. Ancak Xcode'un ve derleme sisteminin sınırlı genişletilebilirliği göz önüne alındığında, bunu Bazel'in sistemiyle değiştirmek önemli çaba ve bakım gerektirir. Bu ek yükü yalnızca bol kaynaklara sahip birkaç şirket karşılayabilir; bunu Bazel'i Xcode ile entegre etmek için yoğun yatırım yapan seçili şirket listesinden görmek mümkündür. İlginç bir şekilde topluluk, bir Xcode projesi oluşturmak için Bazel'in XcodeGen'ini kullanan bir [araç](https://github.com/MobileNativeFoundation/rules_xcodeproj) geliştirdi. Bu durum, Bazel dosyalarından XcodeGen YAML'e ve nihayetinde Xcode Projelerine uzanan karmaşık bir dönüşüm zinciriyle sonuçlanır. Böyle katmanlı dolaylılık genellikle sorun gidermeyi karmaşıklaştırarak sorunların teşhis edilmesini ve çözülmesini daha zor hale getirir.
