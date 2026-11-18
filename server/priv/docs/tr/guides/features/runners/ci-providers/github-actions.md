---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "İlk GitHub Actions işinizi Tuist Çalıştırıcılarında çalıştırın: GitHub'ı bağlayın, runs-on hedefini bir Tuist profiline yönlendirin ve panelden izleyin."
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

Fleet üzerinde bir iş çalıştırmak üç değişiklik gerektirir: GitHub'ı bağlayın, `runs-on` değerini bir Tuist <.localized_link href="/guides/features/runners/profiles">profili</.localized_link>ne yönlendirin ve kodu gönderin.

1. **GitHub'ı bağlayın.** Projenizin <.localized_link href="/guides/integrations/gitforge/github">GitHub kuruluşunuza bağlı</.localized_link> olduğundan emin olun. Tuist, bu kuruluş için `workflow_job` olaylarını alır ve eşleşen işleri filoya iletir. Bu bağlantı olmadan hiçbir iş çalıştırıcılarınıza ulaşmaz.
2. **`runs-on` değerini bir Tuist profiline yönlendirin.** Etkinleştirilen her hesap, kullanıma hazır iki <.localized_link href="/guides/features/runners/profiles">profil</.localized_link> ile başlar: `linux` ve `macos`. Bunlara `tuist-` ön ekiyle başvurun:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **Çalıştırıcı profiliyle Xcode'u seçin**
   >
   > Bir macOS çalıştırıcı imajı tek bir Xcode sürümü içerir; Tuist, profile göre iş başlamadan önce bu sürümü seçer. GitHub tarafından barındırılan çalıştırıcılardan geçiş yapıyorsanız, Xcode sürümlerini değiştirmek için `xcode-select --switch` (veya `xcode-select -s`) kullanan adımları ve diğer araçları veya eylemleri kaldırın. Bu adımlar genellikle GitHub tarafından barındırılan imajlara özgü Xcode kurulumlarına başvurur ve Tuist Çalıştırıcılarında başarısız olabilir.
   >
   > Başka bir Xcode sürümü kullanmak için, o sürüme sahip bir profil <.localized_link href="/guides/features/runners/profiles#creating-a-profile">oluşturun veya seçin</.localized_link> ve `runs-on` değerini güncelleyin, örneğin `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` ve `swift` ardından iş akışında ek kurulum yapmadan profilin seçtiği Xcode'u kullanır.

3. **Kodu gönderin ve izleyin.** İş sıraya alınır, bir çalıştırıcı tarafından üstlenilir ve Tuist panonuzun **Çalıştırıcılar** bölümüne geri aktarılır; burada günlüklerini, adımlarını ve makine metriklerini takip edebilirsiniz.

## Önbellek birimleri {#cache-volumes}

Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleri</.localized_link> ile koruyun. Bunları checkout işleminden sonra ve bunları kullanan komutlardan önce ekleyin.

İşe `id-token: write` iznini verin, böylece önbellek birimleri ve önbelleğe alınmış checkout işlemi başladığı anda bağlanır. Bu izin olmadan, çalıştırıcı GitHub'ın hangi işi çalıştırdığını bildirmesini bekler ve GitHub'ın geç bildirdiği bir iş boş önbelleklerle başlar. OpenID Connect ile Tuist'te oturum açan bir iş akışı bunu zaten sağlar.

```yaml
permissions:
  contents: read
  id-token: write
```
