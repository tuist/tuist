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
Tuist QA şu anda erken önizleme aşamasındadır. Erişim için
[tuist.dev/qa](https://tuist.dev/qa) adresinden kaydolun.
<!-- -->
:::

Kaliteli mobil uygulama geliştirme kapsamlı testlere dayanır, ancak geleneksel
yaklaşımların sınırlamaları vardır. Birim testleri hızlı ve uygun maliyetlidir,
ancak gerçek dünyadaki kullanıcı senaryolarını gözden kaçırırlar. Kabul testi ve
manuel QA bu boşlukları yakalayabilir, ancak bunlar yoğun kaynak gerektirir ve
iyi ölçeklenemez.

Tuist'in QA aracı, gerçek kullanıcı davranışını simüle ederek bu zorluğu çözer.
Otonom olarak uygulamanızı araştırır, arayüz öğelerini tanır, gerçekçi
etkileşimler yürütür ve olası sorunları işaretler. Bu yaklaşım, hataları ve
kullanılabilirlik sorunlarını geliştirmenin erken aşamalarında belirlemenize
yardımcı olurken, geleneksel kabul ve KG testlerinin ek yükünden ve bakım
yükünden kaçınmanıza yardımcı olur.

## Ön Koşullar {#prerequisites}

Tuist QA'yı kullanmaya başlamak için yapmanız gerekenler:
- Temsilcinin daha sonra test için kullanabileceği PR CI iş akışınızdan
  <LocalizedLink href="/guides/features/previews">İncelemeler</LocalizedLink>
  yüklemeyi ayarlayın
- <LocalizedLink href="/guides/integrations/gitforge/github">GitHub ile entegre edin</LocalizedLink>, böylece aracıyı doğrudan PR'nizden tetikleyebilirsiniz

## Kullanım {#usage}

Tuist QA şu anda doğrudan bir PR'den tetiklenmektedir. PR'nizle ilişkili bir
önizlemeniz olduğunda, PR üzerinde `/qa test A özelliğini test etmek istiyorum`
şeklinde yorum yaparak QA aracısını tetikleyebilirsiniz:

![QA tetikleyici yorumu](/images/guides/features/qa/qa-trigger-comment.png)

Yorum, QA aracısının ilerlemesini ve bulduğu sorunları gerçek zamanlı olarak
görebileceğiniz canlı oturuma bir bağlantı içerir. Temsilci çalışmasını
tamamladığında, sonuçların bir özetini PR'a geri gönderecektir:

![QA test özeti](/images/guides/features/qa/qa-test-summary.png)

PR yorumunun bağlantı verdiği gösterge tablosundaki raporun bir parçası olarak,
sorunların bir listesini ve bir zaman çizelgesini alacaksınız, böylece sorunun
tam olarak nasıl gerçekleştiğini inceleyebilirsiniz:

![QA zaman çizelgesi](/images/guides/features/qa/qa-timeline.png)

iOS uygulamamız için yaptığımız tüm QA çalışmalarını genel
panomuzda görebilirsiniz: https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
QA aracısı otonom olarak çalışır ve bir kez başlatıldıktan sonra ek istemlerle
kesintiye uğratılamaz. Temsilcinin uygulamanızla nasıl etkileşime girdiğini
anlamanıza yardımcı olmak için yürütme boyunca ayrıntılı günlükler sağlıyoruz.
Bu günlükler, uygulama bağlamınız üzerinde yineleme yapmak ve aracının
davranışını daha iyi yönlendirmek için istemleri test etmek açısından
değerlidir. Temsilcinin uygulamanızla nasıl performans gösterdiği hakkında geri
bildiriminiz varsa, lütfen [GitHub
Sorunları](https://github.com/tuist/tuist/issues), [Slack
topluluğumuz](https://slack.tuist.dev) veya [topluluk
forumumuz](https://community.tuist.dev) aracılığıyla bize bildirin.
<!-- -->
:::

### Uygulama bağlamı {#app-context}

Temsilci, iyi bir şekilde gezinebilmek için uygulamanız hakkında daha fazla
içeriğe ihtiyaç duyabilir. Üç tür uygulama bağlamımız vardır:
- Uygulama açıklaması
- Kimlik Bilgileri
- Tartışma gruplarını başlatın

Bunların hepsi projenizin pano ayarlarında yapılandırılabilir (`Settings` >
`QA`).

#### Uygulama açıklaması {#app-description}

Uygulama açıklaması, uygulamanızın ne yaptığı ve nasıl çalıştığı hakkında ekstra
bağlam sağlamak içindir. Bu, müşteri temsilcisini başlatırken komut isteminin
bir parçası olarak aktarılan uzun biçimli bir metin alanıdır. Bir örnek şöyle
olabilir:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Kimlik Bilgileri {#credentials}

Temsilcinin bazı özellikleri test etmek için uygulamada oturum açması
gerekiyorsa, temsilcinin kullanması için kimlik bilgileri sağlayabilirsiniz.
Temsilci, oturum açması gerektiğini fark ederse bu kimlik bilgilerini
dolduracaktır.

#### Tartışma gruplarını başlatın {#launch-argument-groups}

Başlatma bağımsız değişken grupları, aracıyı çalıştırmadan önce test isteminize
göre seçilir. Örneğin, aracının tekrar tekrar oturum açmasını, jetonlarınızı ve
çalıştırıcı dakikalarınızı boşa harcamasını istemiyorsanız, bunun yerine kimlik
bilgilerinizi burada belirtebilirsiniz. Aracı oturumu oturum açmış olarak
başlatması gerektiğini fark ederse, uygulamayı başlatırken kimlik bilgileri
başlatma bağımsız değişken grubunu kullanacaktır.

![Argüman gruplarını
başlat](/images/guides/features/qa/launch-argument-groups.png)

Bu başlatma argümanları standart Xcode başlatma argümanlarıdır. İşte bunları
otomatik olarak oturum açmak için nasıl kullanacağınıza dair bir örnek:

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
