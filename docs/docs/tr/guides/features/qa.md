---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA {#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA şu anda erken önizleme aşamasındadır. Erişmek için
[tuist.dev/qa](https://tuist.dev/qa) adresinden kaydolun.
<!-- -->
:::

Kaliteli mobil uygulama geliştirme, kapsamlı testlere dayanır, ancak geleneksel
yaklaşımların sınırları vardır. Birim testleri hızlı ve uygun maliyetlidir,
ancak gerçek dünyadaki kullanıcı senaryolarını gözden kaçırırlar. Kabul testleri
ve manuel kalite güvencesi bu boşlukları doldurabilir, ancak kaynak yoğun olup
ölçeklendirilmesi zordur.

Tuist'in QA ajanı, gerçek kullanıcı davranışını simüle ederek bu sorunu çözer.
Uygulamanızı bağımsız olarak keşfeder, arayüz öğelerini tanır, gerçekçi
etkileşimler gerçekleştirir ve olası sorunları işaretler. Bu yaklaşım,
geleneksel kabul ve QA testlerinin getirdiği ek yük ve bakım yükünden
kaçınırken, geliştirme sürecinin erken aşamalarında hataları ve
kullanılabilirlik sorunlarını tespit etmenize yardımcı olur.

## Ön Koşullar {#prerequisites}

Tuist QA'yı kullanmaya başlamak için şunları yapmanız gerekir:
- PR CI iş akışınızdan
  <LocalizedLink href="/guides/features/previews">Önizlemeler</LocalizedLink>
  yüklemeyi ayarlayın; böylece ajan bunları test için kullanabilir
- <LocalizedLink href="/guides/integrations/gitforge/github"></LocalizedLink>'i
  GitHub ile entegre edin, böylece ajanı doğrudan PR'nizden tetikleyebilirsiniz

## Kullanım {#usage}

Tuist QA şu anda doğrudan bir PR'den tetiklenmektedir. PR'nizle ilişkili bir
önizleme elde ettiğinizde, PR'ye `/qa test I want to test feature A` yorumunu
ekleyerek QA ajanı tetikleyebilirsiniz:

![QA tetikleyici yorumu](/images/guides/features/qa/qa-trigger-comment.png)

Yorumda, QA ajanın ilerlemesini ve tespit ettiği sorunları gerçek zamanlı olarak
görebileceğiniz canlı oturuma bir bağlantı bulunmaktadır. Ajan çalışmasını
tamamladığında, sonuçların bir özetini PR'ye geri gönderecektir:

![QA test özeti](/images/guides/features/qa/qa-test-summary.png)

PR yorumunun bağlantı verdiği gösterge tablosundaki raporun bir parçası olarak,
sorunların bir listesini ve zaman çizelgesini göreceksiniz, böylece sorunun tam
olarak nasıl oluştuğunu inceleyebilirsiniz:

![QA zaman çizelgesi](/images/guides/features/qa/qa-timeline.png)

<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS
uygulamamız</LocalizedLink> için yaptığımız tüm QA çalıştırmalarını genel
panomuzda görebilirsiniz: https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
QA ajanı bağımsız olarak çalışır ve başlatıldıktan sonra ek komutlarla kesintiye
uğratılamaz. Aracının uygulamanızla nasıl etkileşime girdiğini anlamanıza
yardımcı olmak için yürütme süresince ayrıntılı günlükler sağlıyoruz. Bu
günlükler, uygulamanızın bağlamını yinelemek ve aracının davranışını daha iyi
yönlendirmek için komutları test etmek açısından değerlidir. Aracının
uygulamanızla nasıl çalıştığına dair geri bildiriminiz varsa, lütfen [GitHub
Issues](https://github.com/tuist/tuist/issues), [Slack
topluluğumuz](https://slack.tuist.dev) veya [topluluk
forumumuz](https://community.tuist.dev) aracılığıyla bize bildirin.
<!-- -->
:::

### Uygulama bağlamı {#app-context}

Temsilci, uygulamanızı iyi bir şekilde inceleyebilmek için daha fazla bağlam
bilgisine ihtiyaç duyabilir. Üç tür uygulama bağlamı bulunmaktadır:
- Uygulama açıklaması
- Kimlik Bilgileri
- Argüman gruplarını başlat

Bunların tümü, projenizin kontrol paneli ayarlarından yapılandırılabilir
(`Settings` > `QA`).

#### Uygulama açıklaması {#app-description}

Uygulama açıklaması, uygulamanızın ne yaptığı ve nasıl çalıştığı hakkında ek
bilgi sağlamak içindir. Bu, ajanı başlatırken komut isteminin bir parçası olarak
geçirilen uzun bir metin alanıdır. Bir örnek şöyle olabilir:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Kimlik Bilgileri {#credentials}

Temsilcinin bazı özellikleri test etmek için uygulamaya giriş yapması
gerekiyorsa, temsilcinin kullanması için kimlik bilgilerini sağlayabilirsiniz.
Temsilci, giriş yapması gerektiğini fark ederse bu kimlik bilgilerini
girecektir.

#### Argüman gruplarını başlat {#launch-argument-groups}

Başlatma argüman grupları, ajanı çalıştırmadan önce test komutunuz temel
alınarak seçilir. Örneğin, ajanın tekrar tekrar oturum açmasını ve bu şekilde
jetonlarınızı ve çalıştırıcı dakikalarınızı boşa harcamasını istemiyorsanız,
bunun yerine kimlik bilgilerinizi burada belirtebilirsiniz. Ajan, oturum açılmış
olarak başlaması gerektiğini algılarsa, uygulamayı başlatırken kimlik bilgileri
başlatma argüman grubunu kullanır.

![Argüman gruplarını
başlat](/images/guides/features/qa/launch-argument-groups.png)

Bu başlatma argümanları, standart Xcode başlatma argümanlarınızdır. Otomatik
olarak oturum açmak için bunları nasıl kullanacağınızla ilgili bir örnek aşağıda
verilmiştir:

```swift
import ArgumentParser
import SwiftUI

@main
struct TuistApp: App {
    var body: some Scene {
        ContentView()
        #if DEBUG
            .task {
                await checkForAutomaticLogin()
            }
        #endif
    }
    /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
    /// automatically log in
    private func checkForAutomaticLogin() async {
        struct LaunchArguments: ParsableArguments {
            @Option var email: String?
            @Option var password: String?
        }

        do {
            let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

            guard let email = parsedArguments.email,
                  let password = parsedArguments.password
            else {
                return
            }

            try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
        } catch {
            // Skipping automatic log in
        }
    }
}
```
