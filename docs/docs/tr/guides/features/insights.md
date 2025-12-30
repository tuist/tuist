---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# İçgörüler {#insights}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve projesi</LocalizedLink>
<!-- -->
:::

Büyük projeler üzerinde çalışmak bir angarya gibi hissettirmemelidir. Aslında,
sadece iki hafta önce başladığınız bir proje üzerinde çalışmak kadar keyifli
olmalıdır. Bunun böyle olmamasının nedenlerinden biri, proje büyüdükçe
geliştirici deneyiminin zarar görmesidir. Derleme süreleri artar ve testler
yavaş ve aksak hale gelir. Dayanılmaz hale gelene kadar bu sorunları göz ardı
etmek genellikle kolaydır - ancak bu noktada, bunları ele almak zordur. Tuist
Insights, projenizin sağlığını izlemeniz ve projeniz ölçeklenirken verimli bir
geliştirici ortamını korumanız için size araçlar sağlar.

Başka bir deyişle, Tuist Insights aşağıdaki gibi soruları yanıtlamanıza yardımcı
olur:
- Yapım süresi son bir hafta içinde önemli ölçüde arttı mı?
- Testlerim yavaşladı mı? Hangileri yavaşladı?

::: info
<!-- -->
Tuist Insights erken geliştirme aşamasındadır.
<!-- -->
:::

## Yapılar {#builds}

Muhtemelen CI iş akışlarının performansı için bazı metriklere sahip olsanız da,
yerel geliştirme ortamı için aynı görünürlüğe sahip olmayabilirsiniz. Ancak
yerel derleme süreleri, geliştirici deneyimine katkıda bulunan en önemli
faktörlerden biridir.

Yerel derleme sürelerini izlemeye başlamak için `tuist inspect build` komutunu
şemanızın eylem sonrasına ekleyerek kullanabilirsiniz:

![Yapıları incelemek için eylem sonrası]
(/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
Tuist'in derleme yapılandırmasını izlemesini sağlamak için "Derleme ayarlarını
şuradan sağla" seçeneğini çalıştırılabilir dosyaya veya ana derleme hedefinize
ayarlamanızı öneririz.
<!-- -->
:::

::: info
<!-- -->
<LocalizedLink href="/guides/features/projects">oluşturulmuş projele</LocalizedLink> kullanmıyorsanız, derleme başarısız olursa şema sonrası
eylem yürütülmez.
<!-- -->
:::
> 
> Xcode'daki belgelenmemiş bir özellik, bu durumda bile çalıştırmanıza izin
> verir. İlgili `project.pbxproj` dosyasında şemanızın `BuildAction` içinde
> `runPostActionsOnFailure` niteliğini `YES` olarak ayarlayın:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

Mise](https://mise.jdx.dev/) kullanıyorsanız, senaryonuzun eylem sonrası ortamda
`tuist` adresini etkinleştirmesi gerekecektir:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip MISE & PROJECT PATHS
<!-- -->
Ortamınızın `PATH` ortam değişkeni scheme post eylemi tarafından miras alınmaz
ve bu nedenle Mise'ı nasıl kurduğunuza bağlı olarak Mise'ın mutlak yolunu
kullanmanız gerekir. Ayrıca, Mise'i $SRCROOT tarafından işaret edilen dizinden
çalıştırabilmeniz için derleme ayarlarını projenizdeki bir hedeften devralmayı
unutmayın.
<!-- -->
:::


Yerel derlemeleriniz artık Tuist hesabınıza giriş yaptığınız sürece takip
ediliyor. Artık derleme sürelerinize Tuist kontrol panelinden erişebilir ve
zaman içinde nasıl geliştiklerini görebilirsiniz:


::: tip
<!-- -->
Gösterge tablosuna hızlıca erişmek için CLI'dan `tuist project show --web`
komutunu çalıştırın.
<!-- -->
:::

![Yapı içgörüleri içeren gösterge
tablosu](/images/guides/features/insights/builds-dashboard.png)

## Testler {#tests}

Derlemeleri takip etmenin yanı sıra testlerinizi de izleyebilirsiniz. Test
içgörüleri, yavaş testleri belirlemenize veya başarısız CI çalıştırmalarını
hızlı bir şekilde anlamanıza yardımcı olur.

Testlerinizi izlemeye başlamak için `tuist inspect test` komutunu şemanızın test
sonrası eylemine ekleyerek kullanabilirsiniz:

![Testlerin incelenmesi için eylem sonrası]
(/images/guides/features/insights/inspect-test-scheme-post-action.png)

Mise](https://mise.jdx.dev/) kullanıyorsanız, senaryonuzun eylem sonrası ortamda
`tuist` adresini etkinleştirmesi gerekecektir:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
Ortamınızın `PATH` ortam değişkeni scheme post eylemi tarafından miras alınmaz
ve bu nedenle Mise'ı nasıl kurduğunuza bağlı olarak Mise'ın mutlak yolunu
kullanmanız gerekir. Ayrıca, Mise'i $SRCROOT tarafından işaret edilen dizinden
çalıştırabilmeniz için derleme ayarlarını projenizdeki bir hedeften devralmayı
unutmayın.
<!-- -->
:::

Test çalışmalarınız artık Tuist hesabınıza giriş yaptığınız sürece takip
ediliyor. Test içgörülerinize Tuist kontrol panelinden erişebilir ve zaman
içinde nasıl geliştiklerini görebilirsiniz:

![Test içgörüleri içeren gösterge
tablosu](/images/guides/features/insights/tests-dashboard.png)

Genel eğilimlerin yanı sıra, CI'daki hataları veya yavaş testleri ayıklarken
olduğu gibi, her bir testin derinliklerine de dalabilirsiniz:

![Test detayı](/images/guides/features/insights/test-detail.png)

## Oluşturulmuş projele {#generated-projects}

::: info
<!-- -->
Otomatik olarak oluşturulan şemalar otomatik olarak hem `tuist inspect build`
hem de `tuist inspect test` son eylemlerini içerir.
<!-- -->
:::
> 
> Otomatik oluşturulan şemalarınızdaki içgörüleri izlemekle ilgilenmiyorsanız,
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> ve
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>
> oluşturma seçeneklerini kullanarak bunları devre dışı bırakın.

Özel şemalarla oluşturulmuş projele kullanıyorsanız, hem derleme hem de test
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
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
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

Mise kullanmıyorsanız, komut dosyalarınız şu şekilde basitleştirilebilir:

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
),
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

CI'da derleme ve test içgörülerini izlemek için CI'nızın
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>
olduğundan emin olmanız gerekir.

Ek olarak, aşağıdakilerden birini yapmanız gerekecektir:
- `xcodebuild` eylemlerini çağırırken
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> komutunu kullanın.
- `xcodebuild` çağrınıza `-resultBundlePath` ekleyin.

`xcodebuild` projenizi `-resultBundlePath` olmadan derlediğinde veya test
ettiğinde, gerekli etkinlik günlüğü ve sonuç demeti dosyaları oluşturulmaz. Hem
`tuist inspect build` hem de `tuist inspect test` post-action'ları derleme ve
testlerinizi analiz etmek için bu dosyaları gerektirir.
