---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# Kayıt {#registry}

Bağımlılıkların sayısı arttıkça, bunları çözme süresi de artar.
[CocoaPods](https://cocoapods.org/) veya [npm](https://www.npmjs.com/) gibi
diğer paket yöneticileri merkeziyken, Swift Package Manager merkezi değildir. Bu
nedenle SwiftPM, her bir deponun derin bir klonunu yaparak bağımlılıkları
çözmelidir, bu da zaman alıcı olabilir ve merkezi bir yaklaşıma göre daha fazla
bellek kaplar. Bu sorunu çözmek için Tuist, [Package
Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)
uygulamasını sunar, böylece yalnızca gerçekten ihtiyacınız olan commit'leri
indirebilirsiniz __ . Kayıt defterindeki paketler [Swift paketi
Index](https://swiftpackageindex.com/) temel alınarak oluşturulmuştur. Bu
indeksde bir paket bulabilirseniz, o paket Tuist Registry'de de mevcuttur.
Ayrıca, paketler, çözülürken gecikmeyi en aza indirmek için bir kenar depolama
alanı kullanılarak dünya çapında dağıtılır.

## Kullanım {#usage}

Kayıt defterini ayarlamak için, projenizin dizininde aşağıdaki komutu
çalıştırın:

```bash
tuist registry setup
```

Bu komut, projeniz için kayıt defterini etkinleştiren bir kayıt yapılandırma
dosyası oluşturur. Ekibinizin de kayıt defterinden yararlanabilmesi için bu
dosyanın kaydedildiğinden emin olun.

### Kimlik doğrulama (isteğe bağlı) {#authentication}

Kimlik doğrulama isteğe bağlıdır **** . Kimlik doğrulama olmadan, Kayıt'ı IP
adresi başına dakikada 1.000 istek **** hız sınırıyla kullanabilirsiniz.
Dakikada 20.000 istek **** daha yüksek bir hız sınırı elde etmek için aşağıdaki
komutu çalıştırarak kimlik doğrulama yapabilirsiniz:

```bash
tuist registry login
```

::: info
<!-- -->
Kimlik doğrulama için
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
proje</LocalizedLink> gereklidir.
<!-- -->
:::

### Bağımlılıkları çözme {#resolving-dependencies}

Kaynak kontrolünden değil, Kayıt'tan bağımlılıkları çözmek için, projenizin
yapılandırmasına göre okumaya devam edin:
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode
  projesi</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Xcode paketi
  entegrasyonu ile oluşturulmuş projele</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">XcodeProj
  tabanlı paket entegrasyonu ile oluşturulmuş projele</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift
  paketi</LocalizedLink>

CI'da kayıt defterini ayarlamak için şu kılavuzu izleyin:
<LocalizedLink href="/guides/features/registry/continuous-integration">Sürekli
entegrasyon</LocalizedLink>.

### Paket kayıt tanımlayıcıları {#package-registry-identifiers}

`, Package.swift,` veya `, Project.swift,` dosyalarında paket kayıt defteri
tanımlayıcıları kullandığınızda, paketin URL'sini kayıt defteri kuralına göre
dönüştürmeniz gerekir. Kayıt defteri tanımlayıcısı her zaman
`{organization}.{repository}` biçimindedir. Örneğin,
`https://github.com/pointfreeco/swift-composable-architecture` paketinin kayıt
defterini kullanmak için paket kayıt defteri tanımlayıcısı
`pointfreeco.swift-composable-architecture` olacaktır.

::: info
<!-- -->
Tanımlayıcı birden fazla nokta içermemelidir. Depo adı nokta içeriyorsa, nokta
alt çizgi ile değiştirilir. Örneğin, `https://github.com/groue/GRDB.swift`
paketi, `groue.GRDB_swift` Kayıt tanımlayıcısına sahip olacaktır.
<!-- -->
:::
