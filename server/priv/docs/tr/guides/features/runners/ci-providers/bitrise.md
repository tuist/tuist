---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Bitrise derlemelerinizi Tuist Çalıştırıcılarında çalıştırın: çalışma alanınızı bağlayın, barındırılan bir çalıştırıcı havuzunu bir Tuist profiliyle eşleştirin ve iş akışınızda bu havuzu seçin."
}
---
# Bitrise {#bitrise}

<!-- @snippet: ./_invite-only -->

> [!WARNING]
> **Yalnızca özel depolar**
>
> Tuist, her Bitrise derlemesine güvenir: Derlemeler hesabınızın önbelleğini paylaşır ve ona yazabilir. Genel bir deponun fork'larından gelen pull request'leri derleyen iş akışlarına sahip bir havuzu eşleştirmeyin.

Tuist, Bitrise çalışma alanınızdaki kendi kendine barındırılan runner havuzlarını sunar. Bu havuzlardan birini seçen bir derleme, havuzla eşleştirdiğiniz <.localized_link href="/guides/features/runners/profiles">profil</.localized_link>deki bir Tuist makinesinde çalışır. İş akışlarınız, tetikleyicileriniz ve günlükleriniz Bitrise'te kalır; yalnızca makineler değişir.

1. **Çalışma alanınızı bağlayın.** Bitrise'te **Workspace settings → Security → Workspace API tokens** bölümünü açın ve tüm projeler için Bitrise CI'a **Viewer** çalışma alanı rolü ve **Tester/QA** erişimi olan bir token oluşturun. Tuist panonuzda **Settings → Integrations** bölümüne gidin, Bitrise kartındaki **Connect** seçeneğini belirleyin ve token'ı yapıştırın. Tuist, çalışma alanını token'dan okur, token'ı şifrelenmiş olarak saklar ve bir daha göstermez.
2. **Bir runner havuzu oluşturun.** Bitrise'te **Workspace settings → Infrastructure** bölümünü açın, **Add Runner pool** seçeneğini belirleyin ve temsil ettiği makineye göre adlandırın, örneğin `tuist-macos`. Havuz token'ını kopyalayın: Bitrise bunu yalnızca bir kez gösterir.
3. **Havuzu bir Tuist profiliyle eşleştirin.** Tuist'teki Bitrise kartında, **Runner pools** altında havuzu, derlemelerinin çalışması gereken Tuist profilini seçin, havuz token'ını yapıştırın ve **Add pool** seçeneğini belirleyin. Etkinleştirilen her hesap `tuist-linux` ve `tuist-macos` olmak üzere iki profille başlar. Kullanmak istediğiniz her profil için bir havuz ekleyin.
4. **İş akışınızda havuzu seçin.** Bitrise'in Workflow Editor'ünde **Stacks & Machines** bölümünü açın ve **Self-Hosted Runner: tuist-macos** seçeneğini belirleyin. `bitrise.yml` içinde, Tuist'in havuz adının altında gösterdiği havuz yığınını ayarlayın:

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **Bir derleme çalıştırın.** Birkaç saniye içinde bir Tuist makinesi havuza bağlanır, derlemeyi alır ve tamamlandığında bağlantıyı keser. Derleme, Tuist panonuzun **Runners** bölümünde makine metrikleri ve günlüklerinin kaldığı Bitrise'e geri dönüş bağlantısıyla birlikte görünür.

## Özel havuzlar {#dedicated-pools}

Tuist ile eşleştirdiğiniz havuzları yalnızca Tuist için kullanın. Kendi makinelerinizden biri de eşleştirilmiş bir havuza bağlanırsa, o havuzun derlemeleri için Tuist ile rekabet eder.

## Runner limiti {#runner-limit}

Her Tuist makinesi, bir derleme çalıştırırken bir Bitrise runner olarak sayılır ve bağlantıyı kestiğinde sayılmayı durdurur. Bu nedenle Bitrise planınızın runner limiti, Tuist eşzamanlılık limitinizin yanı sıra aynı anda Tuist üzerinde çalışan derleme sayınızı da sınırlar.

## Bağlantıyı kesme {#disconnecting}

Bir havuzu Bitrise kartından kaldırmak, Tuist'in o havuzun derlemelerini almasını durdurur. Zaten çalışan derlemeler etkilenmez.

Bitrise kartında **Disconnect** seçeneğini belirlemek çalışma alanını ve tüm havuzlarını kaldırır.
