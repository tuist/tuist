---
{
  "title": "Sandboxlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sandboxları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında makine duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Yalnızca davetle**
>
> Tuist Sandboxları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetle erişilebilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın. Sandboxlar genel kullanıma sunulduğunda fiyatlandırma duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandboxını alır; bu sandbox, oturum süresince checkout durumunu, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde sandbox kaldığı yerden devam eder.

Sandboxlar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı altyapıda ve ekibinizin <.localized_link href="/guides/features/cache">önbelleğinin</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandboxları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb'larını Tuist üzerinde çalıştırın veya <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile herhangi bir Amp sohbetine Xcode derlemeleri için bir Mac kazandırın.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden sandbox oluşturun ve içinde komutlar çalıştırın veya kendi araçlarınızdan API aracılığıyla bunu yapın.

## CLI ile başlayın {#cli}

`tuist sandbox` kullanarak terminalinizden bir sandbox oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Hesabın herhangi bir üyesi sandboxlarını oluşturabilir ve yönetebilir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için `--xcode` seçeneğini `--xcode 26.1.1` gibi bir sürümle birlikte iletin; bu seçenek `--platform macos` anlamına gelir. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` iletin ve daha büyük bir disk için `--workspace-gb` iletin. Komut, sandbox çalışmaya başladığında döner ve kimliği dahil ayrıntıları yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` iletin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; sandbox duraklatılmışsa önce onu sürdürür. `tuist`, ne kadar uzun çalışırsa çalışsın çıktısını aktarır ve komutun durumuyla çıkar; Ctrl-C ile sandbox içindeki işlemi iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) iletin.

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

Etkileşimli olarak giriş yapamayan araçlar, örneğin bir macOS sandboxında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> ile kimlik doğrulaması yapabilir. Bu token, hesabın bir üyesinin yapabileceği her şeyi yapabilir: sandbox oluşturmak, içlerinde komut çalıştırmak ve onları duraklatmak, sürdürmek, arşivlemek ve silmek. Entegrasyon ayarları hesap yöneticilerinde kalır.

### Sandbox içinde Tuist {#tuist-in-sandbox}

Sandbox imajları Tuist CLI ile gelmez, bu nedenle projenizin sabitlenmiş sürümü çalışır. İlk `tuist sandbox sync` sonrası, sandbox üzerindeki depo kökünde `mise install` çalıştırın (`mise` ve `brew` yüklüdür). `tuist sandbox exec` ile başlattığınız her komutta mise'nin shim'leri (`$HOME/.local/share/mise/shims`) `PATH` yolunun başında yer alır; böylece `tuist` ve diğer mise araçları komutlarınızda ve Xcode derleme aşamalarında, örneğin bir şemanın post-action'larında çalışır.

`tuist sandbox exec` ile başlattığınız her komut ayrıca bir Tuist runner'ın aldığı ortam değişkenlerine de sahip olur; bu sayede sandbox içindeki derlemeler, kimlik bilgilerini iletmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sandbox ana bilgisayarının buna erişebildiği durumlarda, örneğin macOS'ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik token'ıdır. Tuist CLI 4.218.0 ve sonraki sürümler bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komut içinde önce `tuist auth login` çalıştırın.

Token her komut için basılır ve yalnızca o komut çalışırken bir Tuist token'ı ile değiştirilebilir; bu nedenle sandbox asla uzun ömürlü bir kimlik bilgisi tutmaz. Token, komutu başlatan kişinin veya token'ın önbellekle yapabileceğinden fazlasını asla vermez: Yalnızca token tabanlı önbellek yazma izni olan hesap üyeleri okuma erişimi alır ve sandboxın önbelleği kullanabilmesi için bir hesap token'ının `account:sandboxes:write` yanında `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile ilettiğiniz değişkenler önceliklidir.

## Kodlama aracısından Mac üzerinde derleme yapın {#coding-agents}

Linux üzerinde çalışan bir kodlama aracısı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandboxında derleyebilir, test edebilir ve çalıştırabilir. Amp'te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer aracılar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac'i nasıl yöneteceğini bildirir.
2. Tuist CLI'yı aracının çalıştığı yere yükleyin, örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM'de `tuist-linux-aarch64`).
3. CLI'yı kimlik doğrulayın. MCP sunucusundaki giriş bu ortama taşınmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> olarak ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` adresine izin verin. CLI dosyaları Mac'e bu adres üzerinden yükler, bu nedenle başka bir alan adına ihtiyaç duymaz.

Aracı, görev başına bir Mac oluşturur ve projenin sabitlediği [Xcode](#xcode) sürümünü kullanır: `create_sandbox`, seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitlemesini (örneğin `.xcode-version`) okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git'in yoksaymadığı dosyaları, commit edilmiş olsun veya olmasın kopyalar; sonrasında ise yalnızca değişenleri kopyalar. İlk senkronizasyondan sonra Mac üzerindeki depo kök dizininde `mise install` çalıştırır; böylece [projenin sabitlediği Tuist](#tuist-in-sandbox) orada hazır bulunur ve hesabınızın önbelleğinde oturum açmış olur. Aracı daha sonra `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev tamamlandığında Mac'i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır, böylece sonraki komut hemen başlayabilir; `tuist sandbox pause` onu daha erken serbest bırakır. Geride bırakılan bir Mac duraklatılır ve 14 gün duraklatıldıktan sonra silinir.

## Linux ve macOS {#platforms}

**Linux** sandboxları Ubuntu 24.04 üzerinde çalışır:

- 2 vCPU, 4 GiB RAM (varsayılan)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** sandboxları Apple silicon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Bir Xcode seçin {#xcode}

Her macOS sandboxı, oluşturulurken sizin seçtiğiniz tek bir Xcode sürümüyle çalışır. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı önyükler, böylece aracı CI ortamınızla aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev üzerinde macOS sandboxları şu anda şunları sunar:

- `26.6` (varsayılan)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Runner profillerinin yaptığı gibi, tam sürümü kullanarak `xcode_version` (CLI'da `--xcode`) ile birini seçin:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API ve MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp için Tuist Mac eklentisi | `xcode` ile `tuist_mac_start` |
| Amp orb'ları | Orb türü `macos-xcode-26-1-1` (bkz. <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code ve Claude Yönetilen Aracılar | Ortamda veya Yönetilen Aracı oturumu başına `xcode_version` (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılan sürümü alır.
- **Tuist'in sunmadığı bir sürüm reddedilir** ve hata mesajı seçebileceğiniz sürümleri listeler, böylece şu anda nelerin mevcut olduğunu bilirsiniz.
- **Tuist, deponuzdaki `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac'i talep eden aracı seçer. MCP aracı ve Tuist Mac eklentisi, aracılara projenin sabitlediği sürümle eşleşmelerini söyler.
- **Bir sandbox, Xcode'unu ömrü boyunca korur.** Başka bir Xcode ile derleme yapmak için yeni bir sandbox oluşturun. `xcodebuild -version`, bir Mac'in hangi Xcode'u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandboxlar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandboxlar bir hesaba aittir ve hesabın herhangi bir üyesi, entegrasyonlara hizmet veren sandboxlar dahil olmak üzere bunları kullanabilir ve yönetebilir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlar, yalnızca entegrasyonun bağlı olduğu hesabın sandboxlarına erişebilir.
- Bir entegrasyonu bağlamak için Tuist'e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı token'ı veya bir Claude ortam anahtarı, şifrelenerek saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının sandbox üzerinden erişebileceği kaynakları, bir CI işi için uygulayacağınız güvenlik yaklaşımıyla değerlendirin.
