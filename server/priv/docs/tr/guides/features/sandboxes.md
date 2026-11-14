---
{
  "title": "Sandboxlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sandboxları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makineleridir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Yalnızca davetle**
>
> Tuist Sandbox'ları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetle erişilebilir. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack'inde](https://slack.tuist.dev) bize mesaj atın. Fiyatlandırma, Sandbox'lar genel kullanıma sunulduğunda duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandbox'ına sahiptir; bu sandbox, oturum süresince checkout'ını, derleme ürünlerini ve yüklü araçlarını saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj onu kaldığı yerden devam ettirir.

Sandbox'lar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı altyapıda ve ekibinizin <.localized_link href="/guides/features/cache">önbelleğinin</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandbox'ları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb'larını Tuist üzerinde çalıştırın veya herhangi bir Amp thread'ine Xcode derlemeleri için Mac sağlamak amacıyla <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> kullanın.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden veya API üzerinden kendi araçlarınızdan sandbox'lar oluşturun ve içinde komutlar çalıştırın.

## CLI ile başlayın {#cli}

`tuist sandbox` kullanarak terminalinizden bir sandbox oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Sandbox'ları yönetmek için bir hesap yöneticisi gerekir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` parametresini, daha büyük bir disk için ise `--workspace-gb` parametresini iletin. Komut, sandbox çalışmaya başladığında döner ve kimliği dahil ayrıntılarını yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` parametresini iletin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox'ta `bash -l` ile çalışır; duraklatılmışsa önce onu devam ettirir. `tuist`, ne kadar uzun sürerse sürsün çıktısını akış olarak verir ve komutun durumuyla çıkar; Ctrl-C ile sandbox'ta iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) parametrelerini iletin.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandbox'ları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya devam ettir | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Yerel Git çalışma ağacının dosyalarını içine yansıt | `tuist sandbox sync <id>` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Bunun yerine sandbox'ları koddan yönetmek isterseniz, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) üzerinden kullanın veya bir aracının bunları <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

Etkileşimli olarak oturum açamayan araçlar, örneğin bir macOS sandbox'ında derleme yapan bir agent eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> ile kimlik doğrulaması yapabilir. Hesabın bir üyesi gibi sandbox'lar oluşturabilir, bunlarda komutları çalıştırabilir ve duraklatabilir, devam ettirebilir ya da silebilir. Amp veya Claude entegrasyonuna hizmet veren sandbox'lar, analitikler ve entegrasyon ayarları hesap yöneticilerinde kalır.

## Bir kodlama aracısından Mac üzerinde derleme yapın {#coding-agents}

Linux üzerinde çalışan bir kodlama aracısı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandbox'ında derleyebilir, test edebilir ve çalıştırabilir. Amp'te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer aracılar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac'i nasıl yöneteceğini söyler.
2. Aracının çalıştığı yere Tuist CLI'yı yükleyin, örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM'de `tuist-linux-aarch64`).
3. CLI'yı kimlik doğrulayın. MCP sunucusundaki oturum açma işlemi buraya taşınmaz, bu nedenle ya bir hesap üyesi olarak `tuist auth login` komutunu çalıştırın ya da `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> için `TUIST_TOKEN` değerini ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` adresine izin verin. CLI, dosyaları Mac'e bunun üzerinden yükler, bu nedenle başka bir alan adına ihtiyaç duymaz.

Aracı, her görev için bir Mac oluşturur ve her komuttan önce `tuist sandbox sync` komutunu çalıştırır. Git'in yoksaymadığı dosyaları, taahhüt edilmiş olsun veya olmasın kopyalar ve sonrasında yalnızca değişenleri kopyalar. Aracı ardından `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş bir uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev bittiğinde Mac'i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır, böylece sonraki komut hemen başlar; `tuist sandbox pause` ile onu daha erken geri verebilirsiniz. Geride bırakılan bir Mac ardından duraklatılır ve 14 gün duraklatıldıktan sonra silinir.

## Linux ve macOS {#platforms}

**Linux** sandbox'ları Ubuntu 24.04 çalıştırır:

- 2 vCPU, 4 GiB RAM (varsayılan)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** sandbox'ları Apple silikon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandbox'lar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandbox'lar bir hesaba aittir ve yalnızca hesabın yöneticileri bunları yönetebilir. Bir entegrasyondan gelen oturumlar yalnızca entegrasyonun bağlı olduğu hesabın sandbox'larına erişebilir.
- Bir entegrasyonu bağlamak için Tuist'e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı, şifrelenerek saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının buradan erişebileceği şeyleri, bir CI işine对待 ettiğiniz gibi对待 edin.
