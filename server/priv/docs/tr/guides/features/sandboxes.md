---
{
  "title": "Sandboxlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sandboxlar, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Sadece davetle**
>
> Tuist Sandbox'ları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetle erişilebilir. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev)'inde bize mesaj atın. Sandbox'lar genel kullanıma sunulduğunda fiyatlandırma duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandbox'ına sahiptir; bu sandbox, oturum süresince checkout'unu, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde kaldığı yerden devam eder.

Sandbox'lar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı altyapıda ve ekibinizin <.localized_link href="/guides/features/cache">önbelleği</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandbox'ları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb'larını Tuist üzerinde çalıştırın veya <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile herhangi bir Amp thread'ine Xcode derlemeleri için bir Mac sağlayın.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden veya API üzerinden kendi araçlarınızdan sandbox'lar oluşturun ve içinde komutlar çalıştırın.

## CLI ile başlayın {#cli}

Terminalinizden `tuist sandbox` kullanarak bir sandbox oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Hesabın herhangi bir üyesi sandbox'larını oluşturup yönetebilir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` parametresini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için, örneğin `--xcode 26.1.1` gibi bir sürümle birlikte `--xcode` parametresini iletin; bu, `--platform macos` anlamına gelir. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` parametresini, daha büyük bir disk için ise `--workspace-gb` parametresini iletin. Komut, sandbox çalışmaya başladığında döner ve ID'si dahil ayrıntılarını yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` parametresini iletin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; duraklatılmışsa önce onu sürdürür. `tuist`, ne kadar uzun sürerse sürsün çıktısını akış olarak verir ve komutun durumuyla çıkar; Ctrl-C ile sandbox içinde iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) parametrelerini iletin.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandbox'ları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya sürdür | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Yerel Git çalışma ağacının dosyalarını yansıt | `tuist sandbox sync <id>` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Bunun yerine kodla sandbox'ları yönetmek istiyorsanız, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) üzerinden kullanın veya bir aracının bunları <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

Etkileşimli giriş yapamayan araçlar, örneğin bir macOS sandbox'ında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> ile kimlik doğrulaması yapabilir. Hesabın bir üyesinin yapabileceği her şeyi yapabilir: sandbox'lar oluşturabilir, içinde komutlar çalıştırabilir ve bunları duraklatabilir, sürdürebilir, arşivleyebilir ve silebilir. Entegrasyon ayarları hesap yöneticilerinde kalır.

### Sandbox içindeki Tuist {#tuist-in-sandbox}

Sandbox imajları Tuist CLI ile gelmez, bu nedenle projenizin sabitlenmiş sürümü çalışır. İlk `tuist sandbox sync` işleminden sonra, sandbox üzerindeki depo kökünde `mise install` çalıştırın (`mise` ve `brew` yüklüdür), ardından `tuist` öğesini mise üzerinden çalıştırın; örneğin `PATH` üzerinde `$HOME/.local/share/mise/shims` ile.

`tuist sandbox exec` ile başlattığınız her komut, bir Tuist runner'ın aldıklarını alır; bu sayede sandbox'taki derlemeler, kimlik bilgilerini iletmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sandbox ana bilgisayarının erişebildiği durumlarda, örneğin macOS'ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik token'ıdır. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komutta önce `tuist auth login` çalıştırın.

Token her komut için basılır ve yalnızca o komut çalışırken bir Tuist token'ı ile değiştirilebilir; bu nedenle bir sandbox asla uzun ömürlü bir kimlik bilgisini tutmaz. Komutu başlatan kişinin veya token'ın önbellekle yapabileceğinden fazlasını asla sağlamaz: Yalnızca yazma yetkisi olan token'lara sahip hesap üyeleri okuma erişimi alır ve sandbox'ın önbelleği kullanabilmesi için bir hesap token'ının `account:sandboxes:write` yanı sıra `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile ilettiğiniz değişkenler önceliklidir.

## Bir kodlama aracısından Mac'te derleme yapın {#coding-agents}

Linux üzerinde çalışan bir kodlama aracısı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandbox'ında derleyebilir, test edebilir ve çalıştırabilir. Amp'te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer aracılar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. `create_sandbox` aracı, aracıya Mac'i nasıl yöneteceğini söyler.
2. Tuist CLI'yi aracının çalıştığı yere yükleyin; örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM'de `tuist-linux-aarch64`).
3. CLI'nin kimlik doğrulamasını yapın. MCP sunucusunun girişi buna aktarılmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> olarak ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` alanına izin verin. CLI, dosyaları Mac'e bunun üzerinden yükler; bu nedenle başka bir alana ihtiyaç duymaz.

Aracı, görev başına bir Mac oluşturur ve projenin sabitlediği [Xcode](#xcode) sürümünü kullanır: `create_sandbox`, seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitlemesini, örneğin `.xcode-version` değerini okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git'in yoksaymadığı dosyaları, commit edilmiş olsun veya olmasın kopyalar ve sonrasında yalnızca değişenleri kopyalar. İlk senkronizasyondan sonra Mac'teki depo kök dizininde `mise install` çalıştırır; böylece [projenin sabitlenmiş Tuist'i](#tuist-in-sandbox) orada olur ve hesabınızın önbelleğinde oturum açmış halde bulunur. Aracı daha sonra `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş bir uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev tamamlandığında Mac'i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır, böylece sonraki komut hemen başlar; `tuist sandbox pause` onu daha erken geri verir. Geride bırakılan bir Mac duraklatılır ve 14 gün duraklatıldıktan sonra silinir.

## Linux ve macOS {#platforms}

**Linux** sandbox'ları Ubuntu 24.04 çalıştırır:

- 2 vCPU, 4 GiB RAM (varsayılan)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** sandbox'ları Apple silicon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Bir Xcode seçin {#xcode}

Her macOS sandbox'ı tek bir Xcode çalıştırır; bunu oluşturulurken siz seçersiniz. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı önyükler, böylece bir aracı CI'nızla aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev üzerinde macOS sandbox'ları şu anda şunları sunar:

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
| Claude Code ve Claude Managed Agents | Ortamda `xcode_version` veya Managed Agents oturumu başına (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılan sürümü alır.
- **Tuist'in sunmadığı bir sürüm reddedilir** ve hata mesajı seçebileceğiniz sürümleri listeler, böylece şu anda nelerin mevcut olduğunu bilirsiniz.
- **Tuist, deponuzdaki `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac'i isteyen aracı seçer. MCP aracı ve Tuist Mac eklentisi, aracılara projenin sabitlediği sürümü eşleştirmelerini söyler.
- **Bir sandbox, Xcode'unu ömrü boyunca korur.** Başka bir Xcode ile derleme yapmak için yeni bir sandbox oluşturun. `xcodebuild -version`, bir Mac'in hangi Xcode'u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandbox'lar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandbox'lar bir hesaba aittir ve hesabın herhangi bir üyesi, entegrasyona hizmet eden sandbox'lar dahil olmak üzere bunları kullanabilir ve yönetebilir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlar, yalnızca entegrasyonun bağlı olduğu hesabın sandbox'larına erişir.
- Bir entegrasyonu bağlamak için Tuist'e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı token'ı veya bir Claude ortam anahtarı, şifrelenerek saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının ondan erişebileceği şeyleri, bir CI işine nasıl davranacağınızı düşünerek değerlendirin.
