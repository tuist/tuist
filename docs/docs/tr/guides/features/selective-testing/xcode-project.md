---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Xcode projesi {#xcode-project}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve projesi</LocalizedLink>
<!-- -->
:::

Xcode projelerinizin testlerini komut satırı üzerinden seçerek
çalıştırabilirsiniz. Bunun için `xcodebuild` komutunuzun başına `tuist`
ekleyebilirsiniz - örneğin, `tuist xcodebuild test -scheme App`. Komut,
projenizi hashler ve başarılı olduğunda, gelecekteki çalıştırmalarda nelerin
değiştiğini belirlemek için hashleri kalıcı hale getirir.

Gelecekteki çalıştırmalarda `tuist xcodebuild test`, son başarılı test
çalıştırmasından bu yana yalnızca değişmiş olanları çalıştırmak üzere testleri
filtrelemek için hash'leri şeffaf bir şekilde kullanır.

Örneğin, aşağıdaki bağımlılık grafiğini varsayalım:

- `FeatureA` testlere sahiptir `FeatureATests`, ve `Core'a bağlıdır`
- `FeatureB` testlere sahiptir `FeatureBTests`, ve `Core'a bağlıdır`
- `Core` testlere sahiptir `CoreTests`

`tuist xcodebuild test` bu şekilde davranacaktır:

| Eylem                           | Açıklama                                                                     | Dahili durum                                                                                     |
| ------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `tuist xcodebuild test` çağırma | `CoreTests`, `FeatureATests` ve `FeatureBTests içindeki testleri çalıştırır` | `FeatureATests`, `FeatureBTests` ve `CoreTests` hash'leri kalıcı hale getirilir                  |
| `ÖzellikA` güncellendi          | Geliştirici bir hedefin kodunu değiştirir                                    | Öncekiyle aynı                                                                                   |
| `tuist xcodebuild test` çağırma | Hash değiştiği için `FeatureATests` adresindeki testleri çalıştırır          | `FeatureATests` adresinin yeni hash'i kalıcı hale getirilir                                      |
| `Core` güncellendi              | Geliştirici bir hedefin kodunu değiştirir                                    | Öncekiyle aynı                                                                                   |
| `tuist xcodebuild test` çağırma | `CoreTests`, `FeatureATests` ve `FeatureBTests içindeki testleri çalıştırır` | `FeatureATests` `FeatureBTests` ve `CoreTests` adreslerinin yeni hash'leri kalıcı hale getirilir |

CI'nızda `tuist xcodebuild test` kullanmak için
<LocalizedLink href="/guides/integrations/continuous-integration">Sürekli entegrasyon kılavuzundaki</LocalizedLink> talimatları izleyin.

Seçmeli testi çalışırken görmek için aşağıdaki videoya göz atın:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
