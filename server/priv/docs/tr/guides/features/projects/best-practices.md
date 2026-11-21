---
{
  "title": "En iyi uygulamalar",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile oluşturulan projelerde çalışırken uygulanması gereken en iyi uygulamaları öğrenin."
}
---
# En iyi uygulamalar {#best-practices}

Farklı ekipler ve projelerle yıllar içinde çalışırken, Tuist ve Xcode projeleriyle çalışırken takip etmenizi önerdiğimiz bir dizi en iyi uygulama belirledik. Bu uygulamalar zorunlu değildir, ancak projelerinizi bakımını ve ölçeklendirmesini kolaylaştıracak şekilde yapılandırmanıza yardımcı olabilir.

## Xcode {#xcode}

### Önerilmeyen kalıplar {#discouraged-patterns}

#### Uzak ortamları modellemek için yapılandırmalar {#configurations-to-model-remote-environments}

Birçok kuruluş, farklı uzak ortamları modellemek için derleme yapılandırmalarını kullanır (örneğin, `Debug-Production` veya `Release-Canary`), ancak bu yaklaşımın bazı dezavantajları vardır:

- **Tutarsızlıklar:** Grafik boyunca yapılandırma tutarsızlıkları varsa, derleme sistemi bazı hedefler için yanlış yapılandırmayı kullanabilir.
- **Karmaşıklık:** Projeler, anlaşılması ve bakımı zor olan uzun bir yerel yapılandırma ve uzak ortam listesine sahip olabilir.

Derleme yapılandırmaları, farklı derleme ayarlarını somutlaştırmak üzere tasarlanmıştır ve projelerin nadiren `Debug` ve `Release` dışında daha fazlasına ihtiyacı olur. Farklı ortamları modelleme ihtiyacı farklı şekillerde karşılanabilir:

- **Hata Ayıklama derlemelerinde:** Geliştirme sırasında uygulamada erişilebilir olması gereken tüm yapılandırmaları (ör. uç noktalar) dahil edebilir ve bunları çalışma zamanında değiştirebilirsiniz. Değiştirme işlemi, şema başlatma ortam değişkenleri kullanılarak veya uygulama içindeki bir kullanıcı arayüzü ile gerçekleştirilebilir.
- **Sürüm derlemelerinde:** Sürüm durumunda, yalnızca sürüm derlemesine bağlı olan yapılandırmayı dahil edebilir ve derleyici yönergelerini kullanarak yapılandırmaları değiştirme mantığını çalışma zamanında dahil etmeyebilirsiniz.

> [!NOTE]
> **Standart olmayan yapılandırmalar**
>
> Tuist standart olmayan yapılandırmaları destekler ve bunları saf Xcode projelerine kıyasla yönetmeyi kolaylaştırır, ancak yapılandırmalar bağımlılık grafiği boyunca tutarlı değilse uyarılar alırsınız. Bu, derleme güvenilirliğini sağlamaya ve yapılandırma kaynaklı sorunları önlemeye yardımcı olur.


## Oluşturulan projeler

### Derlenebilir klasörler

Tuist 4.62.0, birleştirme çakışmalarını azaltmak amacıyla Xcode 16'da tanıtılan bir özellik olan **derlenebilir klasörler** (Xcode'un senkronize grupları) desteğini ekledi.

Tuist'in joker karakter desenleri (örneğin, `Sources/**/*.swift`) oluşturulan projelerde birleştirme çakışmalarını zaten ortadan kaldırırsa da, derlenebilir klasörler ek avantajlar sunar:

- **Otomatik senkronizasyon**: Proje yapınız dosya sistemiyle senkronize kalır; dosya eklerken veya kaldırırken yeniden oluşturmaya gerek kalmaz
- **Yapay zeka dostu iş akışları**: Kodlama asistanları ve ajanlar, proje yeniden oluşturmayı tetiklemeden kod tabanınızı değiştirebilir
- **Daha basit yapılandırma**: Açık dosya listelerini yönetmek yerine klasör yollarını tanımlayın

Daha akıcı bir geliştirme deneyimi için geleneksel `Target.sources` ve `Target.resources` öznitelikleri yerine derlenebilir klasörlerin benimsenmesini öneririz.

::: code-group

```swift [With buildable folders]
let target: Target = .target(
  name: "App",
  destinations: .iOS,
  product: .app,
  bundleId: "dev.tuist.App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target: Target = .target(
  name: "App",
  destinations: .iOS,
  product: .app,
  bundleId: "dev.tuist.App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### Bağımlılıklar

#### CI üzerinde çözümlenmiş sürümleri zorla

Swift Package Manager bağımlılıklarını CI üzerinde kurarken, deterministik derlemeler sağlamak için `--force-resolved-versions` bayrağını kullanmanızı öneririz:

```bash
tuist install --force-resolved-versions
```

Bu bayrak, bağımlılıkların `Package.resolved` içinde sabitlenmiş tam sürümler kullanılarak çözümlenmesini sağlayarak bağımlılık çözümlemesindeki belirsizlikten kaynaklanan sorunları ortadan kaldırır. Bu, tekrarlanabilir derlemelerin kritik olduğu CI ortamlarında özellikle önemlidir.

#### GitHub Actions üzerinde önbelleğe alınmış bağımlılık kurulumu {#dependency-cache-volumes}

Oluşturulan projeler için, `Package.resolved` içinde sabitlenmiş bağımlılıkları kurmak ve çalıştırmalar arasında önbelleğe almak üzere [tuist/install](https://github.com/tuist/install) kullanın. Tuist Çalıştırıcılarında otomatik olarak <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleri</.localized_link> ve diğer çalıştırıcılarda GitHub'ın önbelleğini kullanır.

```yaml
name: Generate project
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  generate:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

Alt dizindeki bir proje için, yolunu checkout'a göreli olarak iletin:

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

Ek seçenekler için [eylem referansına](https://github.com/tuist/install#usage) bakın.

### Ajan tabanlı kodlama ve worktree'ler {#agentic-coding-and-worktrees}

Kodlama ajanları ve insan katkıda bulunanlar giderek daha fazla paralel çalışıyor: Bir geliştirici, incelemekte olduğu özellik için bir worktree açık tutarken, bir veya daha fazla ajan kendi dallarında kardeş worktree'lerde yineleme yapıyor. Birkaç proje seçimi bunu çok daha sorunsuz hale getirir.

#### Ajan tarafından yapılan düzenlemeler için derlenebilir klasörleri kullanın {#worktrees-buildable-folders}

Bir ajan dosya eklediğinde veya kaldırdığında, `Project.swift` içindeki bir dosya listesine bağlı olan her şey, proje yeniden derlenmeden önce `tuist generate` gerektirir. [Derlenebilir klasörler](#buildable-folders) bu sorumluluğu Xcode'un senkronize gruplarına devreder, böylece dosya ağacı düzenlemeleri artık yeniden oluşturmayı tetiklemez.

Bunu, ajanlara bir Tuist projesinin günlük iş akışını öğreten `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">yetenekli</.localized_link> ile eşleştirin.

#### Önbelleği worktree başına izole etmeyin {#worktrees-shared-cache}

Tuist, <.localized_link href="/cli/directories">XDG Temel Dizin Spesifikasyonu</.localized_link>'nu takip eder, bu nedenle varsayılan olarak aynı makinedeki her worktree `~/.cache/tuist` ve `~/.local/state/tuist` paylaşır. İstediğiniz de budur: Bir worktree'de derlenen yardımcılar, başka birinde indirilen eklentiler ve üçüncüsünde çekilen modül önbelleği ikili dosyalarının tümü yeniden kullanılabilir.

Worktree'ler arasındaki eşzamanlı `tuist` çağrıları paralel olarak çalıştırmak güvenlidir. Özellikle izolasyona ihtiyaç duymadığınız sürece `TUIST_XDG_CACHE_HOME` değerini worktree yerel bir yola işaret etmekten kaçının; aksi takdirde her worktree yardımcıları, eklentileri ve ikili dosyaları yeniden ısıtmak zorunda kalır.

#### SwiftPM geçici alanını worktree başına tutun {#worktrees-swiftpm-scratch}

Swift Package Manager kendi yol kontrollerine sahiptir. `--scratch-path` değiştirilebilir çalışma durumudur ve varsayılan olarak `.build` değerine ayarlanır, `--cache-path` ise paylaşılan önbellek dizinidir. Birden fazla worktree etkin olduğunda bu iki yola aynı şekilde davranılmamalıdır.

Tuist'in varsayılan `tuist install` davranışı, SwiftPM geçici alanını paket dizini altında tutar, böylece her worktree kendi `.build` alanına sahip olur. Bu izolasyonu koruyun. Tek bir paylaşılan SwiftPM geçici dizini, ilgisiz dallardan gelen checkout'ları, derleme ara dosyalarını, eklentileri, makroları ve kilit dosyalarını karıştırabilir.

SwiftPM argümanlarını `tuist install -- ...` aracılığıyla veya `Tuist.swift` içindeki `installOptions` üzerinden iletirken, daha hızlı bağımlılık çekmek istiyorsanız `--cache-path` paylaşın, ancak `--scratch-path` değerini ayarlamayın veya onu worktree yerel bir dizine işaret edin:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--cache-path",
                "/Users/Shared/swiftpm/cache/xcode-16-macos",
            ]
        )
    )
)
```

Önbellek yolunun Xcode, Swift araç zinciri veya platforma göre değişmesi gerekiyorsa, bunun için bir sarmalayıcı veya CI ortam değişkeni kullanın. Paylaşılan bir `--scratch-path` değerini depoya göndermekten kaçının.

Bağımlılık durumu yalnızca bir worktree'de bozuk görünüyorsa, o worktree'nin `.build` dizinini silin ve `tuist install` komutunu tekrar çalıştırın. Paylaşılan SwiftPM önbelleği worktree'ler arasında şüpheli görünüyorsa, bağımlılıkları yeniden yüklemeden önce `swift package purge-cache` komutunu kullanın.

#### Modül önbelleğine güvenin {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">Modül önbelleği</.localized_link>, paralel worktree'lerin yönetilebilir olmasını sağlayan şeydir. Tuist her hedef için deterministik bir <.localized_link href="/guides/features/projects/hashing">karma</.localized_link> hesapladığından, geçmişlerinin çoğunu paylaşan dallara işaret eden iki worktree aynı ikili dosyalara isabet edecektir. CI'dan `main` üzerindeki her commit için `tuist cache` çalıştırın; yerel olarak, her worktree'deki `tuist generate` önbellekten alabildiğini çeker ve yalnızca dalınızın gerçekten değiştirdiği kısımları derler.

Bir worktree, önbellek isabeti beklerken kaynak derlemelerine geri düşerse, <.localized_link href="/guides/features/projects/hashing#debugging">karma hata ayıklama adımlarını</.localized_link> izleyin; deterministik olmayan karmalar (genellikle projedeki mutlak yollardan kaynaklanır) en yaygın nedendir ve iki worktree karşılaştırıldığında belirgin şekilde ortaya çıkar.

#### Kayıt defteri ile Swift Package çözümlemesini hızlandırın {#worktrees-registry}

Her worktree Swift paketlerini bağımsız olarak çözümler. Büyük bir bağımlılık grafiğine sahip bir projede bu durum hızla birikir. <.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link>'ye geçmek, git geçmişlerinin yeniden klonlanmasını önler ve çözümleme süresini dakikalardan saniyelere düşürür.

#### Ajanlara proje içgörülerine erişim sağlayın {#worktrees-mcp}

Derlemeler ve testler birçok worktree'de çalışmaya başladığında, bir ajanın yapabileceği en yararlı şey, bu çalışmalardan *hangilerinin* gerilediğini, hangi testlerin kararsız olduğunu veya paket boyutunun nasıl değiştiğini analiz etmektir. Tuist bu verileri <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusu</.localized_link> ve <.localized_link href="/guides/features/agentic-coding/skills">Yetenekler</.localized_link> paketi aracılığıyla sunar. İş akışı başına birini seçin ve ona bağlı kalın; aynı görev için ikisini karıştırmak genellikle tutarsız ajan davranışına neden olur.

## İlgili {#related}

Büyük ölçekli oluşturulmuş projeleri uygulayan bir ekibin deneyimi için [Monzo'nun büyüyen modüler projesini Tuist ile nasıl tutarlı tuttuğunu](https://tuist.dev/customers/monzo) okuyun.
