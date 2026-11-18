---
{
  "title": "Korumalı Alanlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Korumalı Alanları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Yalnızca davetle**
>
> Tuist Sandboxlar, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetle erişilebilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın. Sandboxlar genel kullanıma sunulduğunda fiyatlandırma duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandbox’ını alır; bu sandbox, oturum süresince checkout’ını, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde kaldığı yerden devam eder.

Sandboxlar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı filoda, ekibinizin <.localized_link href="/guides/features/cache">önbelleğinin</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandboxları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb’larını Tuist üzerinde çalıştırın veya <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile herhangi bir Amp thread’ine Xcode derlemeleri için bir Mac tahsis edin.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden sandbox oluşturun ve içinde komutlar çalıştırın veya API aracılığıyla kendi araçlarınızdan yönetin.

## CLI ile başlayın {#cli}

Terminalinizden `tuist sandbox` kullanarak bir sandbox oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Hesabın herhangi bir üyesi sandboxlarını oluşturabilir ve yönetebilir:

```bash
tuist auth login
```

### 2. Sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için, örneğin `--xcode 26.1.1` gibi bir sürümle birlikte `--xcode` parametresini iletin; bu, `--platform macos` anlamına gelir. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` ve daha büyük bir disk için `--workspace-gb` parametrelerini iletin. Komut, sandbox çalışmaya başladığında döner ve kimliği dahil ayrıntıları yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` parametresini iletin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; duraklatılmışsa önce onu sürdürür. `tuist`, ne kadar uzun sürerse sürsün çıktısını akış olarak verir ve komutun durumuyla çıkar; Ctrl-C ile sandbox içindeki işlemi iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) parametrelerini iletin.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandboxları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya sürdür | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Yerel Git çalışma ağacının dosyalarını yansıt | `tuist sandbox sync <id>` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Sandboxları kod üzerinden yönetmek isterseniz, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) aracılığıyla kullanın veya bir aracının bunları <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

Etkileşimli olarak giriş yapamayan araçlar, örneğin bir macOS sandbox’ında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> ile kimlik doğrulaması yapabilir. Bu jeton, hesabın bir üyesinin yapabileceği her şeyi yapabilir: sandbox oluşturmak, içinde komut çalıştırmak, duraklatmak, sürdürmek, arşivlemek ve silmek. Entegrasyon ayarları hesap yöneticilerinde kalır.

### Sandbox içinde Tuist {#tuist-in-sandbox}

Sandbox imajları Tuist CLI ile birlikte gelmez, bu nedenle projenizin sabitlenmiş sürümü çalışır. İlk `tuist sandbox sync` sonrasında, sandbox üzerindeki depo kökünde `mise install` komutunu çalıştırın (`mise` ve `brew` yüklüdür). `tuist sandbox exec` ile başlattığınız her komutta mise’nin shim’leri (`$HOME/.local/share/mise/shims`) `PATH` yolunda ilk sırada yer alır; böylece `tuist` ve diğer mise araçları komutlarınızda ve Xcode derleme aşamalarında, örneğin bir şemanın post-action’larında çalışır.

`tuist sandbox exec` ile başlattığınız her komut ayrıca bir Tuist runner’ın sahip olduğu özelliklere de sahiptir; bu sayede sandbox’taki derlemeler, kimlik bilgilerini iletmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sandbox ana bilgisayarının buna erişebildiği durumlarda, örneğin macOS’ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik jetonu. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komut içinde önce `tuist auth login` çalıştırın.

Jeton her komut için basılır ve yalnızca o komut çalışırken bir Tuist jetonuyla değiştirilebilir; bu nedenle sandbox asla uzun ömürlü bir kimlik bilgisini tutmaz. Hiçbir zaman, komutu başlatan kişinin veya jetonun önbellekle yapabileceğinden fazlasını sağlamaz: Yalnızca jetonlarla önbelleğe yazma izni olan hesap üyeleri okuma erişimi alır ve sandbox’ın önbelleği kullanabilmesi için bir hesap jetonunun `account:sandboxes:write` yanı sıra `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile ilettiğiniz değişkenler önceliklidir.

## Bir kodlama aracısından Mac üzerinde derleme yapın {#coding-agents}

Linux üzerinde çalışan bir kodlama aracısı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandbox’ında derleyebilir, test edebilir ve çalıştırabilir. Amp’te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer araclar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac’i nasıl yöneteceğini bildirir.
2. Tuist CLI’yı aracının çalıştığı yere yükleyin, örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM üzerinde `tuist-linux-aarch64`).
3. CLI’yı kimlik doğrulamasından geçirin. MCP sunucusundaki giriş bu ortama taşınmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` komutunu çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonuna</.localized_link> ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` alanına izin verin. CLI dosyaları Mac’e bu alan üzerinden yükler, bu nedenle başka bir alana gerek duymaz.

Aracı, proje tarafından sabitlenen [Xcode](#xcode) sürümüyle görev başına bir Mac oluşturur: `create_sandbox` seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitlemesini, örneğin `.xcode-version` dosyasını okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git’in yoksaymadığı dosyaları, taahhüt edilmiş olsun veya olmasın kopyalar; sonrasında yalnızca değişenleri kopyalar. İlk senkronizasyondan sonra Mac üzerindeki depo kök dizininde `mise install` çalıştırır; böylece [projenin sabitlediği Tuist](#tuist-in-sandbox) orada bulunur ve hesabınızın önbelleğinde oturum açmış olur. Aracı ardından `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş bir uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev tamamlandığında Mac’i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır, böylece sonraki komut hemen başlar; `tuist sandbox pause` onu daha erken serbest bırakır. Geride bırakılan bir Mac duraklatılır ve 14 gün duraklatıldıktan sonra silinir.

## Linux ve macOS {#platforms}

**Linux** sandbox’ları Ubuntu 24.04 üzerinde çalışır:

- 2 vCPU, 4 GiB RAM (varsayılan)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** sandbox’ları Apple silicon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Bir Xcode seçin {#xcode}

Her macOS sandbox’ı, oluşturulurken seçtiğiniz tek bir Xcode sürümüyle çalışır. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı önyükler, böylece aracı CI’nızla aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev üzerinde macOS sandbox’ları şu anda şunları sunar:

- `26.6` (varsayılan)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Runner profillerinin yaptığı gibi, tam sürümü kullanarak `xcode_version` ile (CLI’da `--xcode`) birini seçin:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API ve MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp için Tuist Mac eklentisi | `xcode` ile `tuist_mac_start` |
| Amp orb’ları | Orb türü `macos-xcode-26-1-1` (bkz. <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code ve Claude Yönetilen Araclar | Ortamda `xcode_version` veya Yönetilen Araclar oturumu başına (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılan sürümü alır.
- **Tuist’in sunmadığı bir sürüm reddedilir** ve hata mesajı seçebileceğiniz sürümleri listeler, böylece şu anda nelerin mevcut olduğunu bilirsiniz.
- **Tuist deponuzdaki `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac’i talep eden aracı seçer. MCP aracı ve Tuist Mac eklentisi, aracları projenin sabitlediği sürümle eşleşmeleri konusunda yönlendirir.
- **Bir sandbox, Xcode’unu ömrü boyunca korur.** Başka bir Xcode ile derleme yapmak için yeni bir sandbox oluşturun. `xcodebuild -version` bir Mac’in hangi Xcode’u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandbox’lar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandbox’lar bir hesaba aittir ve entegrasyonlara hizmet edenler dahil olmak üzere hesabın herhangi bir üyesi bunları kullanabilir ve yönetebilir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlar yalnızca entegrasyonun bağlı olduğu hesabın sandbox’larına erişir.
- Bir entegrasyonu bağlamak için Tuist’e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı, şifrelenerek saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının ondan erişebileceği şeylere, bir CI işine对待 ettiğiniz şekilde对待 edin.
