---
{
  "title": "Projeler",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode projelerini Swift ile tanımlayın ve Tuist ile tutarlı bir şekilde oluşturun. Birleştirme çakışmalarını ortadan kaldırın, bağımlılıkları bir graf olarak modelleyin ve modül önbelleğinin kilidini açın."
}
---
# Oluşturulan projeler {#generated-projects}

Tuist Oluşturulan Projeler, karmaşıklığı ve maliyetleri kabul edilebilir düzeyde tutarken bu zorlukların üstesinden gelmenize yardımcı olan uygulanabilir bir alternatiftir. Xcode projelerini temel bir unsur olarak ele alır, gelecekteki Xcode güncellemelerine karşı dayanıklılığı sağlar ve ekiplere modülerleştirme odaklı bildirimsel bir API sunmak için Xcode proje oluşturma özelliğinden yararlanır. Tuist, proje tanımını kullanarak modülerleştirmenin karmaşıklıklarını basitleştirir, çeşitli ortamlarda derleme veya test gibi iş akışlarını optimize eder ve Xcode projelerinin evrimini kolaylaştırıp yaygınlaştırır.

## Nasıl çalışır? {#how-does-it-work}

Oluşturulan projelerle başlamak için tek ihtiyacınız olan, projenizi **Tuist'e Özel Alan Dili (DSL)** kullanarak tanımlamaktır. Bu, `Workspace.swift` veya `Project.swift` gibi manifest dosyalarının kullanılmasını gerektirir. Daha önce Swift Package Manager ile çalıştıysanız yaklaşım oldukça benzerdir.

Projenizi tanımladıktan sonra Tuist, onu yönetmek ve etkileşime girmek için çeşitli iş akışları sunar:

- **Oluştur:** Bu temel bir iş akışıdır. Xcode ile uyumlu bir Xcode projesi oluşturmak için kullanın.
- **<.localized_link href="/cli/build">Derle</.localized_link>:** Bu iş akışı yalnızca Xcode projesini oluşturmaz, aynı zamanda derlemek için `xcodebuild` kullanır.
- **<.localized_link href="/cli/test">Test Et</.localized_link>:** Derleme iş akışına benzer şekilde çalışan bu akış, yalnızca Xcode projesini oluşturmaz, aynı zamanda test etmek için `xcodebuild` kullanır.

## Xcode projeleriyle ilgili zorluklar {#challenges-with-xcode-projects}

Xcode projeleri büyüdükçe, güvenilir olmayan artımlı derlemeler, sorunlarla karşılaşan geliştiriciler tarafından Xcode'un genel önbelleğinin sık sık temizlenmesi ve kırılgan proje yapılandırmaları gibi faktörlerden dolayı **kurumlarda verimlilik düşüşü yaşanabilir**. Hızlı özellik geliştirmeyi sürdürmek için kurumlar genellikle çeşitli stratejiler keşfeder.

Bazı kurumlar, [React Native](https://reactnative.dev/) gibi JavaScript tabanlı dinamik çalışma zamanları kullanarak platformu soyutlayıp derleyiciyi atlamayı tercih eder. Bu yaklaşım etkili olabilir ancak [platformun yerel özelliklerine erişimi karmaşıklaştırır](https://shopify.engineering/building-app-clip-react-native). Diğer kurumlar ise **kod tabanını modülerleştirmeyi** seçer; bu, net sınırlar belirlemeye yardımcı olur, kod tabanı üzerinde çalışmayı kolaylaştırır ve derleme sürelerinin güvenilirliğini artırır. Ancak Xcode proje formatı modülerlik için tasarlanmamıştır ve az kişinin anladığı örtük yapılandırmalarla sık çakışmalara yol açar. Bu durum düşük "bus factor" riskine neden olur ve artımlı derlemeler iyileşse bile geliştiriciler derlemeler başarısız olduğunda Xcode'un derleme önbelleğini (yani derived data) sık sık temizlemek zorunda kalabilir. Bunu aşmak için bazı kurumlar **Xcode'un derleme sistemini terk etmeyi** ve [Buck](https://buck.build/) veya [Bazel](https://bazel.build/) gibi alternatifleri benimsemeyi seçer. Ancak bu, [yüksek karmaşıklık ve bakım yükü](https://bazel.build/migrate/xcode) getirir.


## Alternatifler {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager (SPM) öncelikli olarak bağımlılıklara odaklanırken Tuist farklı bir yaklaşım sunar. Tuist ile yalnızca SPM entegrasyonu için paketler tanımlamazsınız; projeler, çalışma alanları, hedefler ve şemalar gibi tanıdık kavramları kullanarak projelerinizi şekillendirirsiniz.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen), ortak Xcode projelerindeki çakışmaları azaltmak ve Xcode'un iç işleyişindeki bazı karmaşıklıkları basitleştirmek için tasarlanmış özel bir proje oluşturucudur. Ancak projeler [YAML](https://yaml.org/) gibi serileştirilebilir formatlar kullanılarak tanımlanır. Swift'in aksine bu yaklaşım, ek araçlar eklemeden soyutlamalar veya kontroller üzerine inşa etmeye olanak tanımaz. XcodeGen, bağımlılıkları doğrulama ve optimizasyon amacıyla dahili bir temsile eşlemek için bir yol sunsa da geliştiricileri Xcode'un inceliklerine maruz bırakmaya devam eder. Bu durum, Bazel topluluğunda görüldüğü üzere XcodeGen'i [araç geliştirmek](https://github.com/MobileNativeFoundation/rules_xcodeproj) için uygun bir temel haline getirebilir ancak sağlıklı ve üretken bir ortamı korumayı amaçlayan kapsayıcı proje evrimi için optimal değildir. Bugün XcodeGen kullanıyorsanız [XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen), mevcut XcodeGen projenizle hangi Tuist yeteneklerinin çalıştığını açıklar; Tuist oluşturulan projelere geçiş yapmak için <.localized_link href="/guides/features/projects/adoption/migrate/xcodegen-project">geçiş kılavuzuna</.localized_link> bakın.

### Bazel {#bazel}

[Bazel](https://bazel.build), uzak önbellekleme özellikleriyle tanınan gelişmiş bir derleme sistemidir ve Swift topluluğunda öncelikle bu yeteneği sayesinde popülerlik kazanmıştır. Ancak Xcode ve derleme sisteminin sınırlı genişletilebilirliği göz önüne alındığında, bunu Bazel'in sistemiyle değiştirmek önemli çaba ve bakım gerektirir. Bazel'i Xcode ile entegre etmek için yoğun yatırım yapan seçili şirket listesinden de anlaşılacağı üzere, bu yükü yalnızca bol kaynaklara sahip birkaç şirket karşılayabilir. İlginç bir şekilde, topluluk bir Xcode projesi oluşturmak için Bazel'in XcodeGen'ini kullanan bir [araç](https://github.com/MobileNativeFoundation/rules_xcodeproj) geliştirdi. Bu durum, Bazel dosyalarından XcodeGen YAML'ye ve nihayetinde Xcode Projelerine uzanan karmaşık bir dönüşüm zinciriyle sonuçlanır. Bu katmanlı dolaylılık genellikle sorun gidermeyi karmaşıklaştırarak sorunların teşhis edilmesini ve çözülmesini daha zor hale getirir.
