---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# Test Öngörüleri {#test-insights}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
  projesi</LocalizedLink>
<!-- -->
:::

Test içgörüleri, yavaş testleri belirleyerek veya başarısız CI çalıştırmalarını
hızlı bir şekilde anlayarak test paketinizin durumunu izlemenize yardımcı olur.
Test paketiniz büyüdükçe, testlerin giderek yavaşlaması veya aralıklı arızalar
gibi eğilimleri tespit etmek giderek zorlaşır. Tuist Test Insights, hızlı ve
güvenilir bir test paketi sürdürmek için ihtiyacınız olan görünürlüğü sağlar.

Test Insights ile şu gibi soruları yanıtlayabilirsiniz:
- Testlerim yavaşladı mı? Hangileri?
- Hangi testler güvenilmez ve dikkat gerektiriyor?
- CI çalışmam neden başarısız oldu?

## Kurulum {#setup}

Testlerinizi izlemeye başlamak için, şemanızın test sonrası eylemine `tuist
inspect test` komutunu ekleyerek bu komuttan yararlanabilirsiniz:

![Testleri incelemek için sonradan yapılacak
işlemler](/images/guides/features/insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/) kullanıyorsanız, komut dosyanızın `tuist` komutunu
post-action ortamında etkinleştirmesi gerekir:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
Ortamınızın `PATH` ortam değişkeni, şema sonrası eylemi tarafından devralınmaz
ve bu nedenle, Mise'yi nasıl yüklediğinize bağlı olarak Mise'nin mutlak yolunu
kullanmanız gerekir. Ayrıca, Mise'yi $SRCROOT tarafından gösterilen dizinden
çalıştırabilmeniz için, projenizdeki bir hedeften derleme ayarlarını devralmayı
unutmayın.
<!-- -->
:::

Tuist hesabınıza giriş yaptığınız sürece testleriniz takip edilir. Tuist kontrol
panelinden testlerinize ilişkin bilgilere erişebilir ve zaman içinde nasıl
geliştiğini görebilirsiniz:

![Test bilgilerini içeren gösterge
paneli](/images/guides/features/insights/tests-dashboard.png)

Genel eğilimlerin yanı sıra, CI'da hata ayıklama veya yavaş testler gibi her bir
testi ayrı ayrı derinlemesine inceleyebilirsiniz:

![Test detayı](/images/guides/features/insights/test-detail.png)

## Oluşturulmuş projele {#generated-projects}

::: info
<!-- -->
Otomatik olarak oluşturulan şemalar, `tuist inspect test` post-action'ı otomatik
olarak içerir.
<!-- -->
:::
> 
> Otomatik olarak oluşturulan şemalarda test bilgilerini izlemek istemiyorsanız,
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>
> oluşturma seçeneğini kullanarak bunları devre dışı bırakın.

Özel şemalarla oluşturulmuş projeler kullanıyorsanız, hem derleme hem de test
içgörüleri için son eylemler ayarlayabilirsiniz:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Mise kullanmıyorsanız, komut dosyalarınızı şu şekilde basitleştirebilirsiniz:

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## Sürekli entegrasyon {#continuous-integration}

CI'daki test bilgilerini takip etmek için, CI'nızın
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">doğrulanmış</LocalizedLink>
olduğundan emin olmanız gerekir.

Ayrıca, şunlardan birini yapmanız gerekecektir:
- `xcodebuild` eylemlerini çağırırken
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> komutunu kullanın.
- `-resultBundlePath` ekleyin. `xcodebuild` çağrısına.

`xcodebuild` komutları, `-resultBundlePath` olmadan projenizi test ettiğinde,
gerekli sonuç paketi dosyaları oluşturulmaz. `tuist inspect test` post-action,
testlerinizi analiz etmek için bu dosyalara ihtiyaç duyar.
