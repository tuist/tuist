---
{
  "title": "Sandboxlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sandboxları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makineleridir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Davet usulü**
>
> Tuist Sandboxları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetle erişilebilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack kanalında](https://slack.tuist.dev) bize yazın. Fiyatlandırma, Sandboxlar genel kullanıma sunulduğunda duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandboxına sahiptir; bu sandbox, oturum süresince checkout durumunu, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde işlem kaldığı yerden devam eder.

Sandboxlar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı altyapıda, ekibinizin <.localized_link href="/guides/features/cache">önbelleğinin</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandboxları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb’larını Tuist üzerinde çalıştırın veya <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile herhangi bir Amp thread’ine Xcode derlemeleri için bir Mac tahsis edin.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden veya API üzerinden kendi araçlarınızla sandboxlar oluşturun ve içinde komutlar çalıştırın.

## CLI ile başlayın {#cli}

Terminalinizden `tuist sandbox` kullanarak bir sandbox oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Sandboxları yönetmek için bir hesap yöneticisi gerekir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` belirtin ve daha büyük bir disk için `--workspace-gb` kullanın. Komut, sandbox çalışmaya başladığında döner ve kimliği dahil ayrıntıları yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` geçirin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; duraklatılmışsa önce yeniden başlatılır. `tuist`, ne kadar sürerse sürsün çıktısını akış olarak verir ve komutun durumuyla çıkar; Ctrl-C ile sandbox içinde iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) parametrelerini geçirin.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandboxları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya devam ettir | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Yerel Git çalışma ağacının dosyalarını içine yansıt | `tuist sandbox sync <id>` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Bunun yerine sandboxları koddan yönetmek isterseniz, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) üzerinden kullanın veya bir aracının bunları <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

Etkileşimli olarak giriş yapamayan araçlar, örneğin bir macOS sandboxında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> ile kimlik doğrulaması yapabilir. Bu jeton, bir hesap üyesi gibi sandboxlar oluşturabilir, içinde komutlar çalıştırabilir ve bunları duraklatabilir, devam ettirebilir veya silebilir. Amp veya Claude entegrasyonuna hizmet veren sandboxlar, analizler ve entegrasyon ayarları hesap yöneticilerinde kalır.

### Sandbox içinde Tuist {#tuist-in-sandbox}

Sandbox imajları Tuist CLI ile gelmez, bu nedenle projenizin sabitlenmiş sürümü çalışır. İlk `tuist sandbox sync` sonrasında, sandbox üzerindeki depo kökünde `mise install` çalıştırın (`mise` ve `brew` yüklüdür), ardından `tuist` komutunu mise üzerinden çalıştırın; örneğin `PATH` üzerinde `$HOME/.local/share/mise/shims` yoluyla.

`tuist sandbox exec` ile başlattığınız her komut, bir Tuist runner’ın aldığı şeyleri de alır; bu sayede sandbox’taki derlemeler, kimlik bilgilerini geçirmeden hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sandbox sunucusunun erişebildiği durumlarda, örneğin macOS’ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik jetonu. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komutta önce `tuist auth login` çalıştırın.

Jeton her komut için basılır ve yalnızca o komut çalışırken bir Tuist jetonuyla takas edilebilir; bu nedenle bir sandbox asla uzun ömürlü bir kimlik bilgisini tutmaz. Komutu başlatan kişinin veya jetonun önbellekle yapabileceğinden fazlasını asla sağlamaz: Yalnızca yazma yetkisi olan jetonlara sahip hesap üyeleri okuma erişimi alır ve sandbox’un önbelleği kullanabilmesi için bir hesap jetonunun `account:sandboxes:write` yanı sıra `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile geçtiğiniz değişkenler önceliklidir.

## Bir kodlama aracısından Mac üzerinde derleme yapın {#coding-agents}

Linux üzerinde çalışan bir kodlama aracısı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandboxında derleyebilir, test edebilir ve çalıştırabilir. Amp’te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer araçılar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac’i nasıl yöneteceğini söyler.
2. Tuist CLI’yı aracının çalıştığı yere yükleyin; örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM üzerinde `tuist-linux-aarch64`).
3. CLI’yı kimlik doğrulayın. MCP sunucusunun girişi buraya taşınmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonuna</.localized_link> ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` alanına izin verin. CLI, Mac’e dosya yüklemelerini bunun üzerinden yapar; başka bir etki alanına ihtiyaç duymaz.

Aracı, her görev için bir Mac oluşturur ve her komuttan önce `tuist sandbox sync` çalıştırır. Git’in görmezden gelmediği dosyaları, commit edilmiş olsun veya olmasın kopyalar; sonrasında yalnızca değişenleri kopyalar. İlk senkronizasyondan sonra Mac’teki depo kök dizininde `mise install` çalıştırır; böylece [projeye sabitlenmiş Tuist](#tuist-in-sandbox) orada olur ve hesabınızın önbelleğinde oturum açmış durumdadır. Aracı daha sonra `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev bittiğinde Mac’i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır; bu sayede sonraki komut anında başlar. `tuist sandbox pause` ile onu daha erken iade edebilirsiniz. Geride bırakılan bir Mac duraklatılır ve 14 gün duraklatıldıktan sonra silinir.

## Linux ve macOS {#platforms}

**Linux** sandboxları Ubuntu 24.04 üzerinde çalışır:

- 2 vCPU, 4 GiB RAM (varsayılan)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** sandboxları Apple silicon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandboxlar birbirleriyle veya CI işleriyle dosya sistemi, bellek ya da süreç paylaşmaz.
- Sandboxlar bir hesaba aittir ve yalnızca o hesabın yöneticileri bunları yönetebilir. Bir entegrasyondan gelen oturumlar yalnızca entegrasyonun bağlı olduğu hesabın sandboxlarına erişir.
- Bir entegrasyonu bağlamak için Tuist’e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı, şifrelenerek saklanır ve bir daha gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının sandbox üzerinden erişebileceği kaynaklara, bir CI işine yaklaşacağınız şekilde yaklaşın.
