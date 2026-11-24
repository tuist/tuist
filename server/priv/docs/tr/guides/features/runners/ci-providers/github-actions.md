---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "İlk GitHub Actions işinizi Tuist Çalıştırıcılarında çalıştırın: GitHub'ı bağlayın, runs-on ayarını bir Tuist profiline yönlendirin ve panelden izleyin."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **Yalnızca GitHub organizasyonları**
>
> Tuist Runners yalnızca bir GitHub kişisel hesabı değil, bir GitHub organizasyonuna ait depolardaki işleri çalıştırır.

Fleet üzerinde bir iş çalıştırmak üç değişiklik gerektirir: GitHub’ı bağlayın, `runs-on` değerini bir Tuist <.localized_link href="/guides/features/runners/profiles">profiline</.localized_link> yönlendirin ve kodu gönderin.

1. **GitHub’ı bağlayın.** Projenizin <.localized_link href="/guides/integrations/gitforge/github">GitHub organizasyonunuza bağlı</.localized_link> olduğundan emin olun. Tuist, bu organizasyon için `workflow_job` olaylarını alır ve eşleşen işleri fleet’e dağıtır. Bu bağlantı olmadan hiçbir iş runner’larınıza ulaşmaz.
2. **`runs-on` değerini bir Tuist profiline yönlendirin.** Her etkin hesap, kullanıma hazır iki <.localized_link href="/guides/features/runners/profiles">profille</.localized_link> başlar: `linux` ve `macos`. Bunlara `tuist-` ön ekiyle başvurun:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **Xcode’u runner profiliyle seçin**
   >
   > Bir macOS runner imajı tek bir Xcode sürümü içerir; Tuist, iş başlamadan önce profile göre bu sürümü seçer. GitHub tarafından barındırılan runner’lardan geçiş yapıyorsanız, Xcode sürümlerini değiştirmek için `xcode-select --switch` (veya `xcode-select -s`) kullanan adımları ve diğer araçları ile eylemleri kaldırın. Bu adımlar genellikle GitHub tarafından barındırılan imajlara özgü Xcode kurulumlarına başvurur ve Tuist Runners üzerinde başarısız olabilir.
   >
   > Başka bir Xcode sürümü kullanmak için, o sürüme sahip bir <.localized_link href="/guides/features/runners/profiles#creating-a-profile">profil oluşturun veya seçin</.localized_link> ve `runs-on` değerini güncelleyin; örneğin `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` ve `swift` ardından iş akışında ek kurulum gerekmeden profilin seçtiği Xcode’u kullanır.

3. **Kodu gönderin ve izleyin.** İş kuyruğa alınır, bir runner tarafından üstlenilir ve Tuist panonuzun **Runners** bölümüne geri aktarılır; burada günlüklerini, adımlarını ve makine metriklerini takip edebilirsiniz.

## Önbellek birimleri {#cache-volumes}

İşler arasında Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleriyle</.localized_link> koruyun. Bunları checkout’tan sonra ve onları kullanan komutlardan önce ekleyin.

İşe `id-token: write` iznini verin ki önbellek birimleri ve önbelleğe alınmış checkout işlem başladığında hemen bağlansın. Bu izin olmadan runner, GitHub’ın hangi işi çalıştırdığını bildirmesini bekler ve GitHub’ın geç bildirdiği bir iş boş önbelleklerle başlar. OpenID Connect ile Tuist’e oturum açan bir iş akışı bu izni zaten verir.

```yaml
permissions:
  contents: read
  id-token: write
```
