---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# İçgörüler Oluşturun {#build-insights}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
  projesi</LocalizedLink>
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

Diğer bir deyişle, Tuist Insights aşağıdaki gibi soruları yanıtlamanıza yardımcı
olur:
- Geçen hafta derleme süresi önemli ölçüde arttı mı?
- CI'da derlemelerim yerel geliştirmeye kıyasla daha mı yavaş?

Muhtemelen CI iş akışlarının performansı için bazı metriklere sahip olsanız da,
yerel geliştirme ortamı için aynı görünürlüğe sahip olmayabilirsiniz. Ancak
yerel derleme süreleri, geliştirici deneyimine katkıda bulunan en önemli
faktörlerden biridir.

Yerel derleme sürelerini izlemeye başlamak için, şemanızın post-action kısmına
`tuist inspect build` komutunu ekleyerek bu komuttan yararlanabilirsiniz:

![Derlemeleri incelemek için eylem
sonrası](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
Tuist'in yapılandırmayı izleyebilmesi için "Yapı ayarlarını şuradan sağla"
seçeneğini yürütülebilir dosyaya veya ana yapı hedefine ayarlamanızı öneririz.
<!-- -->
:::

::: info
<!-- -->
1}oluşturulmuş projeleri</LocalizedLink> kullanmıyorsanız, derleme başarısız
olursa şema sonrası eylem yürütülmez.
<!-- -->
:::
> 
> Xcode'daki belgelenmemiş bir özellik, bu durumda bile bunu gerçekleştirmenize
> olanak tanır. İlgili `project.pbxproj` dosyasında, şemanızın `BuildAction`
> içindeki `runPostActionsOnFailure` özniteliğini `YES` olarak ayarlayın:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/) kullanıyorsanız, komut dosyanızın `tuist` komutunu
post-action ortamında etkinleştirmesi gerekir:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
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


Tuist hesabınıza giriş yaptığınız sürece yerel derlemeleriniz artık izlenir.
Artık Tuist kontrol panelinden derleme sürelerinize erişebilir ve zaman içinde
nasıl geliştiğini görebilirsiniz:


::: tip
<!-- -->
Kontrol paneline hızlı bir şekilde erişmek için CLI'dan `tuist project show
--web` komutunu çalıştırın.
<!-- -->
:::

![Derleme bilgilerini içeren gösterge
paneli](/images/guides/features/insights/builds-dashboard.png)

## Oluşturulmuş projele {#generated-projects}

::: info
<!-- -->
Otomatik olarak oluşturulan şemalar, `tuist inspect build` post-action komutunu
otomatik olarak içerir.
<!-- -->
:::
> 
> Otomatik olarak oluşturulan şemalarınızda içgörüleri izlemek istemiyorsanız,
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
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
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Mise kullanmıyorsanız, komut dosyalarınızı şu şekilde basitleştirebilirsiniz:

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
)
```

## Sürekli entegrasyon {#continuous-integration}

CI'da derleme bilgilerini izlemek için CI'nızın
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">kimlik
doğrulamasının yapıldığından</LocalizedLink> emin olmanız gerekir.

Ayrıca, şunlardan birini yapmanız gerekecektir:
- `xcodebuild` eylemlerini çağırırken
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> komutunu kullanın.
- `-resultBundlePath` ekleyin. `xcodebuild` çağrısına.

`xcodebuild` komutları, `-resultBundlePath` olmadan projenizi derlediğinde,
gerekli etkinlik günlüğü ve sonuç paketi dosyaları oluşturulmaz. `tuist inspect
build` post-action, derlemelerinizi analiz etmek için bu dosyalara ihtiyaç
duyar.
