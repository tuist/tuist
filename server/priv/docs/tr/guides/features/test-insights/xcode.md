---
{
  "title": "Xcode Test İçgörileri",
  "titleTemplate": ":title · Test İçgörileri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test İçgörileri ile yavaş ve kararsız testleri belirlemek için Xcode test analizlerini takip edin."
}
---
# Xcode test içgörüleri {#xcode-test-insights}

Tuist Test Insights, yavaş testleri tespit ederek veya başarısız CI çalıştırmalarını hızla anlayarak test paketinizin sağlığını izlemeniz için Xcode test analitiği sunar. Test paketiniz büyüdükçe, kademeli olarak yavaşlayan testler veya aralıklı hatalar gibi eğilimleri fark etmek giderek zorlaşır. Tuist Test Insights, hızlı ve güvenilir bir test paketini sürdürmeniz için gereken görünürlüğü sağlar.

Test Insights ile şu gibi soruları yanıtlayabilirsiniz:
- Testlerim daha mı yavaşladı? Hangileri?
- Hangi testler kararsız ve dikkat gerektiriyor?
- CI çalıştırmam neden başarısız oldu?

## Kurulum {#setup}

Testlerinizi izlemeye başlamak için, şemanızın test son eylemine ekleyerek `tuist inspect test` komutundan yararlanabilirsiniz:

![Testleri denetlemek için son eylem](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/) kullanıyorsanız, betiğinizin son eylem ortamında `tuist` etkinleştirmesi gerekir:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise ve proje yolları**
>
> Ortamınızın `PATH` ortam değişkeni şema son eylemi tarafından devralınmaz; bu nedenle Mise'nin kurulum yöntemine bağlı olan mutlak yolunu kullanmanız gerekir. Ayrıca, $SRCROOT tarafından işaret edilen dizinden Mise'yi çalıştırabilmeniz için projenizdeki bir hedeften derleme ayarlarını devralmayı unutmayın.

Tuist hesabınıza giriş yaptığınız sürece test çalıştırmalarınız artık izlenir. Tuist kontrol panelinde test içgörülerinize erişebilir ve zaman içinde nasıl değiştiklerini görebilirsiniz:

![Test içgörülerini içeren kontrol paneli](/images/guides/features/build-insights/tests-dashboard.png)

Genel eğilimlere ek olarak, CI üzerinde hataları veya yavaş testleri hata ayıklarken olduğu gibi her bir teste derinlemesine inebilirsiniz:

![Test detayı](/images/guides/features/build-insights/test-detail.png)

## Oluşturulan projeler {#generated-projects}

> [!NOTE]
> Otomatik oluşturulan şemalar, `tuist inspect test` son eylemini otomatik olarak içerir.
>
> Otomatik oluşturulan şemalarınızda test içgörülerini izlemekle ilgilenmiyorsanız, bunları [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) oluşturma seçeneğini kullanarak devre dışı bırakın.

Özel şemalara sahip oluşturulmuş projeler kullanıyorsanız, test içgörüleri için son eylemleri yapılandırabilirsiniz:

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

Mise kullanmıyorsanız, betiklerinizi şu şekilde basitleştirebilirsiniz:

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

CI üzerinde test içgörülerini izlemek için, CI sisteminizin <.localized_link href="/guides/server/authentication#continuous-integration">kimliğin doğrulanmış</.localized_link> olduğundan emin olmanız gerekir.

Ayrıca şunlardan birini yapmanız gerekir:
- `xcodebuild` eylemlerini çağırırken <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> komutunu kullanın.
- `xcodebuild` çağrınıza `-resultBundlePath` ekleyin.

`xcodebuild`, projenizi `-resultBundlePath` olmadan test ettiğinde gerekli sonuç paketi dosyaları oluşturulmaz. `tuist inspect test` son eylemi, testlerinizi analiz etmek için bu dosyaları gerektirir.

### Git geçmişi {#git-history}

CI üzerinde Tuist, checkout'un commit geçmişini de yükler: commit SHA'ları, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request'in temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgiler, Tuist'e hangi commit'lerin varsayılan dalınıza geldiğini söyler; örneğin birleştirme kuyruğunun test ettiği commit'ler. Tuist, checkout'un zaten sahip olduğu geçmişi okur ve checkout temel dala sahip olmadığında, uzaktan en son commit'i ister (`git ls-remote`). Kod kapsamı dışında geçmiş getirilmez. Kod kapsamı ile birlikte, sığ bir checkout, dosya içerikleri olmadan, bir pull request'in nerede dallandığını bulmak ve Tuist'in zaten sahip olduğu commit'lere ulaşmak için derinleştirilir; böylece bir commit, üzerinde durduğu ebeveyni olmadan asla yüklenmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Yalnızca checkout'u okur, uzak sunucuya bağlanmaz. |
| `TUIST_GIT_BRANCH=<branch>` | Çalıştırmanın dalını adlandırır; CI sağlayıcısının ve checkout'un tanımlamasından önce gelir. Tuist'in tanımadığı ve bir dal yerine bir commit checkout eden CI sistemlerinde ayarlayın; aksi takdirde bu çalıştırmaların dalı olmaz. |
