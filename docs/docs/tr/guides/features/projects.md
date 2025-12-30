---
{
  "title": "Projects",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn about Tuist's DSL for defining Xcode projects."
}
---
# Oluşturulmuş projele {#generated-projects}

Generated, karmaşıklığı ve maliyetleri kabul edilebilir bir seviyede tutarken bu
zorlukların üstesinden gelmeye yardımcı olan uygulanabilir bir alternatiftir.
Xcode projelerini temel bir unsur olarak ele alır, gelecekteki Xcode
güncellemelerine karşı esneklik sağlar ve ekiplere modülerleştirme odaklı
bildirimsel bir API sağlamak için Xcode proje üretiminden yararlanır. Tuist,
modülerleştirmenin** karmaşıklıklarını basitleştirmek, çeşitli ortamlarda
derleme veya test gibi iş akışlarını optimize etmek ve Xcode projelerinin
gelişimini kolaylaştırmak ve demokratikleştirmek için proje bildirimini
kullanır.

## Nasıl çalışıyor? {#how-does-it-work}

Oluşturulmuş projele kullanmaya başlamak için tek yapmanız gereken **Tuist'in
Alana Özgü Dilini (DSL)** kullanarak projenizi tanımlamaktır. Bu,
`Workspace.swift` veya `Project.swift` gibi manifesto dosyalarının
kullanılmasını gerektirir. Daha önce Swift paketi Paket Yöneticisi ile
çalıştıysanız, yaklaşım çok benzerdir.

Projenizi tanımladıktan sonra Tuist, onu yönetmek ve onunla etkileşim kurmak
için çeşitli iş akışları sunar:

- **Üretme:** Bu temel bir iş akışıdır. Xcode ile uyumlu bir Xcode projesi
  oluşturmak için kullanın.
- **<LocalizedLink href="/guides/features/build">Build</LocalizedLink>:** Bu iş
  akışı sadece Xcode projesini oluşturmakla kalmaz, aynı zamanda onu derlemek
  için `xcodebuild` adresini kullanır.
- **<LocalizedLink href="/guides/features/test">Test</LocalizedLink>:** Derleme
  iş akışına çok benzer şekilde çalışan bu iş akışı sadece Xcode projesini
  oluşturmakla kalmaz, aynı zamanda test etmek için `xcodebuild` adresini
  kullanır.

## Xcode projeleriyle ilgili zorluklar {#challenges-with-xcode-projects}

Xcode projeleri büyüdükçe, **kuruluşları güvenilir olmayan artımlı derlemeler,
sorunlarla karşılaşan geliştiriciler tarafından Xcode'un global önbelleğinin sık
sık temizlenmesi ve kırılgan proje yapılandırmaları gibi çeşitli faktörler
nedeniyle üretkenlikte bir düşüşle** karşılaşabilir. Hızlı özellik geliştirmeyi
sürdürmek için kuruluşlar genellikle çeşitli stratejiler araştırır.

Bazı kuruluşlar, [React Native](https://reactnative.dev/) gibi JavaScript
tabanlı dinamik çalışma zamanlarını kullanarak platformu soyutlayarak
derleyiciyi atlamayı tercih etmektedir. Bu yaklaşım etkili olsa da [platformun
yerel özelliklerine erişimi
zorlaştırmaktadır](https://shopify.engineering/building-app-clip-react-native).
Diğer kuruluşlar **kod tabanını modüler hale getirmeyi tercih ediyor**, bu da
net sınırlar oluşturmaya yardımcı olarak kod tabanıyla çalışmayı kolaylaştırıyor
ve derleme sürelerinin güvenilirliğini artırıyor. Bununla birlikte, Xcode proje
formatı modülerlik için tasarlanmamıştır ve çok az kişinin anladığı örtük
yapılandırmalara ve sık sık çakışmalara neden olur. Bu durum kötü bir veri yolu
faktörüne yol açar ve artımlı derlemeler iyileşebilse de geliştiriciler
derlemeler başarısız olduğunda Xcode'un derleme önbelleğini (yani türetilmiş
verileri) sık sık temizleyebilir. Bunu ele almak için bazı kuruluşlar **Xcode'un
derleme sistemini** terk etmeyi ve [Buck](https://buck.build/) veya
[Bazel](https://bazel.build/) gibi alternatifleri benimsemeyi tercih etmektedir.
Ancak, bu [yüksek karmaşıklık ve bakım yükü](https://bazel.build/migrate/xcode)
ile birlikte gelir.


## Alternatifler {#alternatives}

### Swift paketi Yöneticisi {#swift-package-manager}

Swift paketi Yöneticisi (SPM) öncelikle bağımlılıklara odaklanırken, Tuist
farklı bir yaklaşım sunar. Tuist ile sadece SPM entegrasyonu için paketler
tanımlamazsınız; projeler, çalışma alanları, hedefler ve şemalar gibi tanıdık
kavramları kullanarak projelerinizi şekillendirirsiniz.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen), işbirliğine dayalı Xcode
projelerindeki çakışmaları azaltmak ve Xcode'un iç işleyişindeki bazı
karmaşıklıkları basitleştirmek için tasarlanmış özel bir proje üreticisidir.
Ancak projeler [YAML](https://yaml.org/) gibi serileştirilebilir formatlar
kullanılarak tanımlanır. Swift'in aksine bu, geliştiricilerin ek araçlar
kullanmadan soyutlamalar veya kontroller üzerine inşa etmelerine izin vermez.
XcodeGen, bağımlılıkları doğrulama ve optimizasyon için dahili bir temsille
eşleştirmenin bir yolunu sunsa da, geliştiricileri hala Xcode'un nüanslarına
maruz bırakıyor. Bu, Bazel topluluğunda görüldüğü gibi XcodeGen'i [araç
oluşturma](https://github.com/MobileNativeFoundation/rules_xcodeproj) için uygun
bir temel haline getirebilir, ancak sağlıklı ve üretken bir ortamı sürdürmeyi
amaçlayan kapsayıcı proje evrimi için uygun değildir.

### Bazel {#bazel}

[Bazel](https://bazel.build) uzaktan önbelleğe alma özellikleriyle tanınan
gelişmiş bir derleme sistemidir ve Swift topluluğu içinde öncelikle bu özelliği
nedeniyle popülerlik kazanmıştır. Bununla birlikte, Xcode'un ve derleme
sisteminin sınırlı genişletilebilirliği göz önüne alındığında, Bazel'in sistemi
ile değiştirmek önemli çaba ve bakım gerektirir. Bazel'i Xcode ile entegre etmek
için büyük yatırımlar yapan firmaların seçkin listesinden de anlaşılacağı üzere,
yalnızca bol kaynaklara sahip birkaç şirket bu yükü taşıyabilir. İlginç bir
şekilde, topluluk bir Xcode projesi oluşturmak için Bazel'in XcodeGen'ini
kullanan bir [araç](https://github.com/MobileNativeFoundation/rules_xcodeproj)
oluşturdu. Bu da Bazel dosyalarından XcodeGen YAML'ye ve son olarak Xcode
Projelerine kadar karmaşık bir dönüşüm zinciriyle sonuçlanıyor. Bu tür katmanlı
dolaylamalar genellikle sorun gidermeyi zorlaştırır, sorunları teşhis etmeyi ve
çözmeyi daha zor hale getirir.
