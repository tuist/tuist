---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Bitrise derlemelerinizi Tuist Çalıştırıcılar üzerinde çalıştırın: çalışma alanınızı bağlayın, kendi barındırdığınız bir çalıştırıcı havuzunu bir Tuist profiliyle eşleştirin ve iş akışınızda bu havuzu seçin."
}
---
# Bitrise {#bitrise}

<!-- @snippet: ./_invite-only -->

> [!WARNING]
> **Yalnızca özel depolar**
>
> Tuist, her Bitrise derlemesine güvenir: Derlemeler hesabınızın önbelleğini paylaşır ve ona yazabilir. Genel bir deponun fork’larından gelen pull request’leri derleyen iş akışlarına sahip bir havuzu eşleştirmeyin.

Tuist, Bitrise çalışma alanınızdaki kendi barındırdığınız runner havuzlarını sunar. Bu havuzlardan birini seçen bir derleme, havuzla eşleştirdiğiniz <.localized_link href="/guides/features/runners/profiles">profil</.localized_link>deki bir Tuist makinesinde çalışır. İş akışlarınız, tetikleyicileriniz ve günlükleriniz Bitrise’ta kalır; yalnızca makineler değişir.

1. **Çalışma alanınızı bağlayın.** Bitrise’ta **Workspace settings → Security → Workspace API tokens** yolunu izleyin ve tüm projeler için Bitrise CI’a **Viewer** çalışma alanı rolü ile **Tester/QA** erişimine sahip bir token oluşturun. Tuist kontrol panelinizde **Settings → Integrations** bölümüne gidin, Bitrise kartındaki **Connect** seçeneğini belirleyin ve token’ı yapıştırın. Tuist, çalışma alanını token’dan okur, token’ı şifrelenmiş olarak saklar ve bir daha göstermez.
2. **Bir runner havuzu oluşturun.** Bitrise’ta **Workspace settings → Infrastructure** yolunu izleyin, **Add Runner pool** seçeneğini belirleyin ve temsil ettiği makineye göre adlandırın, örneğin `tuist-macos`. Havuz token’ını kopyalayın: Bitrise bunu yalnızca bir kez gösterir.
3. **Havuzu bir Tuist profiliyle eşleştirin.** Tuist’teki Bitrise kartında, **Runner pools** altında havuzu, derlemelerinin çalışması gereken Tuist profilini seçin, havuz token’ını yapıştırın ve **Add pool** seçeneğini belirleyin. Etkinleştirilen her hesap `tuist-linux` ve `tuist-macos` olmak üzere iki profille başlar. Kullanmak istediğiniz her profil için bir havuz ekleyin.
4. **İş akışınızda havuzu seçin.** Bitrise’ın Workflow Editor’ünde **Stacks & Machines** bölümünü açın ve **Self-Hosted Runner: tuist-macos** seçeneğini belirleyin. `bitrise.yml` içinde, Tuist’in havuz adının altında gösterdiği havuz yığınını ayarlayın:

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **Bir derleme çalıştırın.** Birkaç saniye içinde bir Tuist makinesi havuza bağlanır, derlemeyi alır ve tamamlandığında bağlantıyı keser. Derleme, Tuist kontrol panelinizin **Runners** bölümünde makine metrikleri ve günlüklerinin bulunduğu Bitrise’a geri dönüş bağlantısıyla birlikte görünür.

## Özel havuzlar {#dedicated-pools}

Tuist ile eşleştirdiğiniz havuzları yalnızca Tuist için kullanın. Kendi makinelerinizden biri de eşleştirilmiş bir havuza bağlanırsa, o havuzun derlemeleri için Tuist ile rekabet eder.

## Runner sınırı {#runner-limit}

Her Tuist makinesi, bir derleme çalıştırırken bir Bitrise runner olarak sayılır ve bağlantıyı kestiğinde sayılmayı durdurur. Bu nedenle Bitrise planınızın runner sınırı, Tuist eşzamanlılık sınırınıza ek olarak aynı anda kaç derlemenizin Tuist üzerinde çalışabileceğini sınırlar.

## Bağlantıyı kesme {#disconnecting}

Bir havuzu Bitrise kartından kaldırmak, Tuist’in o havuzun derlemelerini almasını durdurur. Zaten çalışan derlemeler etkilenmez.

Bitrise kartında **Disconnect** seçeneğini belirlemek, çalışma alanını ve tüm havuzlarını kaldırır.
