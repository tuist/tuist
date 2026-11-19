---
{
  "title": "Xcode Test Analizleri",
  "titleTemplate": ":title · Test Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Analizleri ile yavaş ve kararsız testleri belirlemek için Xcode test analizlerini takip edin."
}
---
# Xcode test içgörüleri {#xcode-test-insights}

Tuist Test Insights, yavaş testleri tespit ederek veya başarısız CI çalıştırmalarını hızla anlayarak test paketinizin sağlığını izlemeniz için Xcode test analizleri sunar. Test paketiniz büyüdükçe, giderek yavaşlayan testler veya aralıklı hatalar gibi eğilimleri fark etmek giderek zorlaşır. Tuist Test Insights, hızlı ve güvenilir bir test paketini korumak için ihtiyaç duyduğunuz görünürlüğü sağlar.

Test Insights ile şu gibi soruları yanıtlayabilirsiniz:
- Testlerim yavaşladı mı? Hangileri?
- Hangi testler kararsız ve dikkat gerektiriyor?
- CI çalıştırmam neden başarısız oldu?

## Kurulum {#setup}

Testlerinizi izlemeye başlamak için, şemanızın test sonrası eylemine ekleyerek `tuist inspect test` komutundan yararlanabilirsiniz:

![Testleri incelemek için sonrası eylem](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/) kullanıyorsanız, betiğinizin sonrası eylem ortamında `tuist` etkinleştirmesi gerekir:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise ve proje yolları**
>
> Ortamınızın `PATH` ortam değişkeni şema sonrası eylemi tarafından devralınmaz, bu nedenle Mise'nin mutlak yolunu kullanmanız gerekir; bu yol, Mise'yi nasıl yüklediğinize bağlı olacaktır. Ayrıca, $SRCROOT tarafından işaret edilen dizinden Mise'yi çalıştırabilmeniz için projenizdeki bir hedeften derleme ayarlarını devralmayı unutmayın.

Tuist hesabınıza giriş yaptığınız sürece test çalıştırmalarınız artık izlenir. Test içgörülerinize Tuist panosundan erişebilir ve zaman içinde nasıl değiştiklerini görebilirsiniz:

![Test içgörülü pano](/images/guides/features/build-insights/tests-dashboard.png)

Genel eğilimlerin yanı sıra, her bir teste derinlemesine inebilirsiniz; örneğin CI üzerinde hataları veya yavaş testleri hata ayıklarken:

![Test detayı](/images/guides/features/build-insights/test-detail.png)

## Oluşturulan projeler {#generated-projects}

> [!NOTE]
> Otomatik oluşturulan şemalar, `tuist inspect test` sonrası eylemini otomatik olarak içerir.
>
> Otomatik oluşturulan şemalarınızda test içgörülerini izlemekle ilgilenmiyorsanız, bunları [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) oluşturma seçeneğini kullanarak devre dışı bırakın.

Özel şemalara sahip oluşturulmuş projeler kullanıyorsanız, test içgörüler için sonrası eylemleri ayarlayabilirsiniz:

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

Mise kullanmıyorsanız, betiklerinizi aşağıdaki şekilde basitleştirebilirsiniz:

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

CI üzerinde test içgörülerini izlemek için, CI'nizin <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulaması yapılmış</.localized_link> olduğundan emin olmanız gerekir.

Ayrıca, şunlardan birini yapmanız gerekecektir:
- `xcodebuild` eylemlerini çağırırken <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> komutunu kullanın.
- `xcodebuild` çağrınıza `-resultBundlePath` ekleyin.

`xcodebuild`, projenizi `-resultBundlePath` olmadan test ettiğinde gerekli sonuç paketi dosyaları oluşturulmaz. `tuist inspect test` sonrası eylemi, testlerinizi analiz etmek için bu dosyaları gerektirir.

### Git geçmişi {#git-history}

CI üzerinde, Tuist ayrıca checkout'un commit geçmişini yükler: commit SHA'ları, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request'in temel dalının bulunduğu dal. Hiçbir dosya içeriği, commit mesajı veya yazar yüklenmez. Bu, Tuist'e hangi commit'lerin varsayılan dalınıza geldiğini söyler; örneğin bir birleştirme kuyruğunun test ettiği commit'ler. Tuist, checkout'un zaten sahip olduğu geçmişi okur ve checkout temel dala sahip olmadığında, en son commit'i için uzaktan ister (`git ls-remote`). Kod kapsamı dışında geçmiş getirmez. Kod kapsamı ile birlikte, sığ bir checkout, dosya içeriği olmadan derinleştirilir; böylece bir pull request'in nerede dallandığı bulunur ve Tuist'in zaten sahip olduğu commit'lere ulaşılır, dolayısıyla bir commit aslında üzerinde durduğu ebeveyni olmadan yüklenmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Yalnızca checkout'u okur, uzak sunucuyla iletişime geçmez. |
