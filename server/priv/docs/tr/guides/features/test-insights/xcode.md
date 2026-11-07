---
{
  "title": "Xcode Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test İçgörüler ile yavaş ve kararsız testleri belirlemek için Xcode test analizlerini takip edin."
}
---
# Xcode test içgörüleri {#xcode-test-insights}

Tuist Test Insights, yavaş testleri tespit ederek veya başarısız CI çalıştırmalarını hızla anlayarak test paketinizin sağlığını izlemeniz için Xcode test analizleri sunar. Test paketiniz büyüdükçe, kademeli olarak yavaşlayan testler veya aralıklı hatalar gibi eğilimleri fark etmek giderek zorlaşır. Tuist Test Insights, hızlı ve güvenilir bir test paketini sürdürmek için ihtiyaç duyduğunuz görünürlüğü sağlar.

Test Insights ile şu gibi soruları yanıtlayabilirsiniz:
- Testlerim daha mı yavaşladı? Hangileri?
- Hangi testler kararsız ve dikkat gerektiriyor?
- CI çalışmam neden başarısız oldu?

## Kurulum {#setup}

Testlerinizi izlemeye başlamak için, şemanızın test son eylemine ekleyerek `tuist inspect test` komutundan yararlanabilirsiniz:

![Testleri inceleme için son eylem](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

Eğer [Mise](https://mise.jdx.dev/) kullanıyorsanız, betiğinizin son eylem ortamında `tuist` etkinleştirmesi gerekecektir:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise ve proje yolları**
>
> Ortamınızın `PATH` ortam değişkeni şema son eylemi tarafından devralınmaz, bu nedenle Mise'in nasıl kurulduğuna bağlı olan mutlak yolunu kullanmanız gerekir. Ayrıca, $SRCROOT tarafından işaret edilen dizinden Mise'i çalıştırabilmeniz için projenizdeki bir hedeften derleme ayarlarını devralmayı unutmayın.

Tuist hesabınıza giriş yaptığınız sürece test çalıştırmalarınız artık izlenmektedir. Test içgörülerinize Tuist panosundan erişebilir ve zaman içindeki gelişimini görebilirsiniz:

![Test içgörülü pano](/images/guides/features/build-insights/tests-dashboard.png)

Genel eğilimlerin yanı sıra, CI üzerindeki hataları veya yavaş testleri hata ayıklarken olduğu gibi her bir teste derinlemesine de inebilirsiniz:

![Test detayı](/images/guides/features/build-insights/test-detail.png)

## Oluşturulan projeler {#generated-projects}

> [!NOTE]
> Otomatik oluşturulan şemalar, `tuist inspect test` son eylemini otomatik olarak içerir.
>
> Otomatik oluşturulan şemalarınızda test içgörülerini izlemekle ilgilenmiyorsanız, bunları [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) oluşturma seçeneğini kullanarak devre dışı bırakın.

Özel şemalı oluşturulmuş projeler kullanıyorsanız, test içgörüler için son eylemleri kurabilirsiniz:

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

Mise kullanmıyorsanız, betikleriniz şu şekilde basitleştirilebilir:

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

CI üzerinde test içgörülerini izlemek için, CI'nizin <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulaması yapılmış</.localized_link> olduğundan emin olmanız gerekecektir.

Ayrıca, şunlardan birini yapmanız gerekecektir:
- `xcodebuild` eylemlerini çağırırken <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> komutunu kullanın.
- `xcodebuild` çağrınıza `-resultBundlePath` ekleyin.

`xcodebuild`, projenizi `-resultBundlePath` olmadan test ettiğinde gerekli sonuç paketi dosyaları oluşturulmaz. `tuist inspect test` son eylemi, testlerinizi analiz etmek için bu dosyaları gerektirir.

### Git geçmişi {#git-history}

CI üzerinde, Tuist ayrıca checkout'un commit geçmişini yükler: commit SHA'ları, üstleri, commit tarihleri ve çalışmanın ile pull request'in temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu, Tuist'e hangi commit'lerin varsayılan dalınıza geldiğini söyler; örneğin bir birleştirme kuyruğunun test ettiği commit'ler. Tuist, checkout'un zaten sahip olduğu geçmişi okur ve checkout temel dala sahip olmadığında, uzaktan en son commit'ini ister (`git ls-remote`). Kod kapsamı dışında geçmiş getirmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Uzak sunucuyla iletişim kurmadan yalnızca checkout'u okur. |
