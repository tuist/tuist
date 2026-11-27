---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "İlk Buildkite işinizi Tuist Çalıştırıcılarında çalıştırın: kümenizi bağlayın, bir kuyruğu Tuist profilinden sonra adlandırın ve bir adımdan hedefleyin."
}
---
# Buildkite {#buildkite}

Tuist, Buildkite kümenizdeki kendi kendine barındırılan kuyrukları izler ve bulduğu işleri filoda çalıştırır. Boru hatlarınız Buildkite üzerinde çalışmaya devam eder; yalnızca hesaplama kaynağı değişir. Bir işi filoda çalıştırmak üç değişiklik gerektirir: kümenizi bağlayın, bir kuyruğa bir Tuist <.localized_link href="/guides/features/runners/profiles">profil</.localized_link> adını verin ve bunu bir adımdan hedefleyin.

1. **Kümenizi bağlayın.** Buildkite'ta kümenizi açın, **Agent Tokens** bölümüne gidin ve bir jeton oluşturun; jeton `bkct_` ile başlar. Tuist kontrol panelinizde **Ayarlar → Entegrasyonlar** bölümüne gidin, Buildkite kartındaki **Bağlan** seçeneğini belirleyin ve kuruluşunuzun slug bilgisini ve jetonu girin. Jeton şifrelenerek saklanır ve bir daha gösterilmez. Kuruluşu değiştirmek veya jetonu ileride yenilemek için karttaki alanları düzenleyin ve **Değişiklikleri kaydet** seçeneğini belirleyin. Tuist, bir dakika içinde kümeyi izlemeye başlar.
2. **Bir kuyruğa bir Tuist profili adını verin.** Her etkin hesap, kullanıma hazır iki <.localized_link href="/guides/features/runners/profiles">profiller</.localized_link> ile başlar: `linux` ve `macos`. Bir iş, kuyruk anahtarı bir profilin etiketiyle eşleştiğinde alınır. Kümenizde `tuist-linux` ve `tuist-macos` anahtarlı kendi kendine barındırılan kuyruklar oluşturun, ardından bir adımdan birini hedefleyin:

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **Gönderin ve izleyin.** İş kuyruğa alınır, bir runner tarafından sahiplenilir ve Tuist panonuzun **Runner'lar** bölümüne geri aktarılır; burada günlüklerini, adımlarını ve makine metriklerini takip edebilirsiniz. Runner, günlüğü işin içinden o işe özel bir kimlik bilgisiyle gönderir, bu nedenle Buildkite API token'ına gerek yoktur.

## Duraklatma ve bağlantıyı kesme {#pausing-and-disconnecting}

Bir Buildkite kuyruğunda dağıtımı duraklatmak, Tuist'in ondan yeni iş almasını engeller. Zaten çalışan işler etkilenmez.

**Ayarlar → Entegrasyonlar** altındaki Buildkite kartında kümenin bağlantısını kesmek, Tuist'in onu tamamen izlemesini durdurur.

## Önbellek birimleri {#cache-volumes}

Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleri</.localized_link> ile koruyun. Bunları checkout işleminden sonra ve bunları kullanan komutlardan önce ekleyin.
