---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# Kayıt {#registry}

Bağımlılıkların sayısı arttıkça, bunları çözme süresi de artar.
CocoaPods](https://cocoapods.org/) veya [npm](https://www.npmjs.com/) gibi diğer
paket yöneticileri merkezileştirilmiş olsa da Swift paketi paket yöneticisi
merkezileştirilmemiştir. Bu nedenle, SwiftPM'nin her deponun derin bir klonunu
yaparak bağımlılıkları çözmesi gerekir, bu da zaman alıcı olabilir ve merkezi
bir yaklaşımdan daha fazla bellek kaplar. Bunu ele almak için Tuist, [Paket
Kayıt](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)
için bir uygulama sağlar, böylece yalnızca _gerçekten ihtiyacınız olan
taahhütleri indirebilirsiniz_. Kayıt defterindeki paketler [Swift Paket
İndeksi](https://swiftpackageindex.com/) temel alınarak oluşturulmuştur. - Eğer
orada bir paket bulabilirseniz, o paket Tuist Kayıt Defterinde de mevcuttur. Ek
olarak, paketler çözümlenirken minimum gecikme için bir uç depolama kullanılarak
dünya çapında dağıtılır.

## Kullanım {#usage}

Kayıt defterini ayarlamak için projenizin dizininde aşağıdaki komutu çalıştırın:

```bash
tuist registry setup
```

Bu komut, projeniz için kayıt defterini etkinleştiren bir kayıt defteri
yapılandırma dosyası oluşturur. Ekibinizin de kayıt defterinden yararlanabilmesi
için bu dosyanın işlendiğinden emin olun.

### Kimlik Doğrulama (isteğe bağlı) {#authentication}

Kimlik doğrulama **isteğe bağlıdır**. Kimlik doğrulama olmadan, kayıt defterini
IP adresi başına **dakikada 1.000 istek** hız sınırıyla kullanabilirsiniz. Daha
yüksek bir hız sınırı elde etmek için **dakikada 20.000 istek** çalıştırarak
kimlik doğrulaması yapabilirsiniz:

```bash
tuist registry login
```

::: info
<!-- -->
Kimlik doğrulama için
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve</LocalizedLink> projesi gerekir.
<!-- -->
:::

### Bağımlılıkları çözme {#resolving-dependencies}

Bağımlılıkları kaynak denetimi yerine kayıt defterinden çözmek için proje
kurulumunuza göre okumaya devam edin:
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode projesi</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Xcode paket entegrasyonu ile oluşturulmuş projele</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">XcodeProj tabanlı paket entegrasyonu ile oluşturulmuş projele</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift paketi</LocalizedLink>

CI'da kayıt defterini ayarlamak için bu kılavuzu izleyin:
<LocalizedLink href="/guides/features/registry/continuous-integration">Sürekli tümleştirme</LocalizedLink>.

### Paket kayıt tanımlayıcıları {#package-registry-identifiers}

Paket kayıt defteri tanımlayıcılarını bir `Package.swift` veya `Project.swift`
dosyasında kullandığınızda, paketin URL'sini kayıt defteri kuralına
dönüştürmeniz gerekir. Kayıt tanımlayıcısı her zaman
`{organizasyon}.{repository}` biçimindedir. Örneğin,
`https://github.com/pointfreeco/swift-composable-architecture` Swift paketi için
kayıt defterini kullanmak için, paket kayıt defteri tanımlayıcısı
`pointfreeco.swift-composable-architecture` şeklinde olacaktır.

::: info
<!-- -->
Tanımlayıcı birden fazla nokta içeremez. Depo adı bir nokta içeriyorsa, bu nokta
alt çizgi ile değiştirilir. Örneğin, `https://github.com/groue/GRDB.swift`
paketi `groue.GRDB_swift` kayıt defteri tanımlayıcısına sahip olacaktır.
<!-- -->
:::
