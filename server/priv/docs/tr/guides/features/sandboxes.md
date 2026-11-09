---
{
  "title": "Korumalı Alanlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Korumalı Alanları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesini alır; ajan boşta kaldığında makine duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Davet usulü**
>
> Tuist Sandboxlar, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda davet usulüyle erişime açıktır. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın. Sandboxlar genel kullanıma sunulduğunda fiyatlandırma duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandbox'ına sahiptir; bu sandbox, oturum süresince checkout'ını, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde sandbox kaldığı yerden devam eder.

Sandboxlar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı altyapıda, ekibinizin <.localized_link href="/guides/features/cache">önbelleği</.localized_link>nin yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleklenmiş yapıtları kullanabilir.

Sandboxları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb'larını Tuist üzerinde çalıştırın.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden sandbox oluşturun ve bunlarda komut çalıştırın veya API aracılığıyla kendi araçlarınızdan yönetin.

## CLI ile başlayın {#cli}

`tuist sandbox` kullanarak terminalinizden bir sandbox oluşturun ve içinde komut çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Sandboxları yönetmek için bir hesap yöneticisi gerekir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` belirtin ve daha büyük bir disk için `--workspace-gb` ekleyin. Komut, sandbox çalışmaya başladığında döner ve kimliği dahil olmak üzere ayrıntıları yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` geçirin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -lc` ile çalıştırılır; sandbox duraklatılmışsa önce devam ettirilir ve `tuist` komutun çıkış durumuyla sonlanır.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandboxları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya devam ettir | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Sandboxları kod üzerinden yönetmek isterseniz, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) aracılığıyla kullanın veya bir aracının bunları <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

## Linux ve macOS {#platforms}

**Linux** sandboxları Ubuntu 24.04 üzerinde çalışır:

- 2 vCPU, 4 GiB RAM (varsayılan)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** sandboxları Apple silikon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandboxlar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandboxlar bir hesaba aittir ve yalnızca o hesabın yöneticileri bunları yönetebilir. Bir entegrasyondan gelen oturumlar yalnızca entegrasyonun bağlı olduğu hesabın sandboxlarına erişir.
- Bir entegrasyonu bağlamak için Tuist'e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı, şifrelenerek saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının sandbox üzerinden erişebileceği kaynaklara, bir CI işine对待 ettiğiniz gibi对待 edin.
