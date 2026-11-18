---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "İlk Buildkite işinizi Tuist Çalıştırıcılarında çalıştırın: kümenizi bağlayın, bir kuyruğa Tuist profili adını verin ve bir adımdan bu kuyruğu hedefleyin."
}
---
# Buildkite {#buildkite}

<!-- @snippet: ./_invite-only -->

Tuist, Buildkite kümenizdeki kendi barındırdığınız kuyrukları izler ve bulduğu işleri filo üzerinde çalıştırır. Pipeline’larınız Buildkite üzerinde çalışmaya devam eder; yalnızca hesaplama kaynağı değişir. Bir işi filoda çalıştırmak üç değişiklik gerektirir: kümenizi bağlayın, bir kuyruğu bir Tuist <.localized_link href="/guides/features/runners/profiles">profilinin</.localized_link> adıyla eşleştirin ve bunu bir adımdan hedefleyin.

1. **Kümenizi bağlayın.** Buildkite’ta kümenizi açın, **Agent Tokens** bölümüne gidin ve bir token oluşturun; bu token `bkct_` ile başlar. Tuist kontrol panelinizde **Ayarlar → Entegrasyonlar** bölümüne gidin, Buildkite kartındaki **Bağlan** seçeneğini belirleyin ve kuruluş slug’unuz ile token’ı girin. Token şifrelenmiş olarak saklanır ve bir daha gösterilmez. Kuruluşu değiştirmek veya token’ı daha sonra yenilemek için karttaki alanları düzenleyin ve **Değişiklikleri kaydet** seçeneğini belirleyin. Tuist, bir dakika içinde kümeyi izlemeye başlar.
2. **Bir kuyruğu bir Tuist profilinin adıyla eşleştirin.** Her etkin hesap, kullanıma hazır iki <.localized_link href="/guides/features/runners/profiles">profille</.localized_link> başlar: `linux` ve `macos`. Bir işin kuyruk anahtarı bir profilin etiketiyle eşleştiğinde iş alınır. Kümenizde `tuist-linux` ve `tuist-macos` anahtarlı kendi barındırdığınız kuyruklar oluşturun, ardından bir adımdan birini hedefleyin:

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **Gönderin ve izleyin.** İş kuyruğa alınır, bir runner tarafından kapılır ve Tuist kontrol panelinizin **Runner’lar** bölümüne geri aktarılır; burada günlüklerini, adımlarını ve makine metriklerini takip edebilirsiniz. Runner, günlüğü yalnızca o işe özel bir kimlik bilgisiyle işin içinden gönderir, bu nedenle bir Buildkite API token’ına gerek yoktur.

## Durdurma ve bağlantıyı kesme {#pausing-and-disconnecting}

Bir Buildkite kuyruğunda dağıtımı duraklatmak, Tuist’in ondan yeni iş almasını engeller. Zaten çalışan işler etkilenmez.

**Ayarlar → Entegrasyonlar** altındaki Buildkite kartında kümenin bağlantısını kesmek, Tuist’in onu tamamen izlemesini durdurur.

## Önbellek birimleri {#cache-volumes}

Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleriyle</.localized_link> koruyun. Bunları checkout işleminden sonra ve bunları kullanan komutlardan önce ekleyin.
