---
{
  "title": "Sandboxlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sandboxları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sanal Ortamlar {#sandboxes}

> [!IMPORTANT]
> **Davet usulü**
>
> Tuist Sanal Ortamları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda davet usulüyle erişime açıktır. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack kanalında](https://slack.tuist.dev) bize yazın. Fiyatlandırma, Sanal Ortamlar genel kullanıma sunulduğunda duyurulacaktır.

Sanal ortam, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sanal ortamına sahiptir; bu ortam, oturum süresince checkout durumunu, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sanal ortam duraklatılır; sonraki mesaj geldiğinde kaldığı yerden devam eder.

Sanal ortamlar, <.localized_link href="/guides/features/runners">Tuist Çalıştırıcıları</.localized_link> ile aynı filo üzerinde, ekibinizin <.localized_link href="/guides/features/cache">önbelleğinin</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sanal ortamları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb’larını Tuist üzerinde çalıştırın veya <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile herhangi bir Amp thread’ine Xcode derlemeleri için bir Mac tahsis edin.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Yönetilen Aracılar oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden sanal ortamlar oluşturun ve bunlarda komutlar çalıştırın veya kendi araçlarınızdan API üzerinden erişin.

## CLI ile başlayın {#cli}

Terminalinizden `tuist sandbox` kullanarak bir sanal ortam oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Hesabın herhangi bir üyesi sanal ortamlarını oluşturup yönetebilir:

```bash
tuist auth login
```

### 2. Bir sanal ortam oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için `--xcode` seçeneğini `--xcode 26.1.1` gibi bir sürümle birlikte verin; bu seçenek `--platform macos` anlamına gelir. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile `--memory-gb` seçeneğini, bir Linux sanal ortamına daha fazla [CPU](#guaranteed-cpu) garantisi vermek için `--guaranteed-vcpus` seçeneğini ve daha büyük bir disk için `--workspace-gb` seçeneğini kullanın. Sanal ortam, oluşturulduktan sonra iki saat boyunca çalışır ve her yeniden başlatmada süre sıfırlanır; 5 dakika ile bir gün arasında bir süre belirlemek için `--lifetime-minutes` seçeneğini kullanın. Ömrü sona erdiğinde çalışan komutlar iptal edilir, sanal ortam duraklatılır ve arşivlenir; dosyaları korunur, böylece unutulmuş bir sanal ortam hesabınızın kapasitesini tüketmeyi bırakır. Komut, sanal ortam çalışmaya başladığında döner ve kimliği dahil olmak üzere ayrıntıları yazdırır. Tüm sunucular meşgulken, örneğin CI işleri paylaşılan Mac’leri tutarken, sunucu oluşturma işlemi `fleet_busy` hatasıyla başarısız olmadan önce 25 saniye bekler; en fazla 5 dakikaya kadar (maksimum bir saat) denemeye devam etmek için `--wait-timeout 5m` seçeneğini kullanın; neden yaklaşık dakikada bir stderr’e yazılır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` seçeneğini kullanın.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sanal ortamda `bash -l` ile çalışır; duraklatılmışsa önce yeniden başlatılır. `tuist` ne kadar uzun çalışırsa çalışsın çıktısını aktarır ve komutun durumuyla çıkar; Ctrl-C ile sanal ortamda iptal edilebilir. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) seçeneklerini kullanın.

Komut `tuist` öğesinden bağımsız olarak çalışır, bu nedenle bağlantı kopsa bile devam eder. Uzun bir derlemeyi zaman sınırlı bir araç çağrısına, örneğin bir aracının çağrısına sığdırmak için `--wait <seconds>` seçeneğini kullanın: süre dolduğunda `tuist` komutu çalışır durumda bırakır, 75 koduyla çıkar ve çıktısının kaldığı yerden devam edip komutun durumuyla çıkan `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` komutunu yazdırır.

### Sık yapılan işlemler {#cli-tasks}

| İşlem | Komut |
| --- | --- |
| Sanal ortamları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya devam ettir | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Süresi dolmasından sonra çalışır durumda tut | `tuist sandbox extend <id> --lifetime-minutes 240` |
| Yerel Git çalışma ağacının dosyalarını yansıt | `tuist sandbox sync <id>` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Sanal ortamları kod üzerinden yönetmek yerine, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) aracılığıyla kullanın veya bir aracının <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

Etkileşimli olarak giriş yapamayan araçlar, örneğin bir macOS sanal ortamında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> ile kimlik doğrulaması yapabilir. Hesabın bir üyesinin yapabileceği her şeyi yapabilir: sanal ortamlar oluşturabilir, içlerinde komutlar çalıştırabilir ve bunları duraklatabilir, devam ettirebilir, arşivleyebilir ve silebilir. Entegrasyon ayarları ve bir entegrasyona hizmet veren sanal ortamlarda komut çalıştırmak yalnızca hesap yöneticilerine aittir.

### Sanal ortam içindeki Tuist {#tuist-in-sandbox}

macOS sanal ortamları Tuist CLI ile birlikte gelir. Projeniz Tuist’i mise aracılığıyla sabitlediğinde (`mise.toml` veya `.tool-versions`), `tuist` bunun yerine o sürümü çalıştırır; bir komut ilk kez ihtiyaç duyduğunda yüklenir. `tuist sandbox exec` ile başlattığınız her komutta mise’nin shim’leri (`$HOME/.local/share/mise/shims`) `PATH` yolunun başında, imajdaki Tuist ise sonunda yer alır; böylece `tuist` ve diğer mise araçlarınız komutlarınızda ve Xcode derleme aşamalarında, örneğin bir şemanın post-action’larında çalışır. Her Mac ayrıca kodlama araçları için `/opt/tuist/agent-guide.md` konumunda bir kılavuz taşır; bu kılavuz imajdan oluşturulur: Xcode ve simülatörler, deposunun konumu ve hazır bir anlık görüntünün içeriği. Mac üzerinde çalışan Claude Code, Codex ve Amp bunu talimat dosyalarından bulur.

`tuist sandbox exec` ile başlattığınız her komut ayrıca bir Tuist çalıştırıcısının sahip olduğu everything’a erişir; böylece sanal ortamdaki derlemeler, kimlik bilgilerini geçmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sanal ortamın sunucusunun erişebildiği durumlarda, örneğin macOS’ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik jetonu. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komut içinde önce `tuist auth login` çalıştırın.

Jeton her komut için basılır ve yalnızca o komut çalışırken bir Tuist jetonuyla takas edilebilir; bu nedenle bir sanal ortam asla uzun ömürlü bir kimlik bilgisini tutmaz. Komutu başlatan kişinin veya jetonun önbellekle yapabileceğinden fazlasını asla sağlamaz: yalnızca yazma yetkisi olan önbellek jetonlarına sahip hesap üyeleri okuma erişimi alır ve bir hesap jetonunun önbelleği kullanabilmesi için `account:sandboxes:write` yanı sıra `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile geçtiğiniz değişkenler önceliklidir.

## Bir kodlama aracısından Mac üzerinde derleme {#coding-agents}

Linux üzerinde çalışan bir kodlama aracı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sanal ortamında derleyebilir, test edebilir ve çalıştırabilir. Amp’te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer araçlar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac’i nasıl yöneteceğini söyler.
2. Aracının çalıştığı yere Tuist CLI’yi yükleyin, örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM’de `tuist-linux-aarch64`).
3. CLI’yi kimlik doğrulayın. MCP sunucusunun oturum açma durumu buraya taşınmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` komutunu çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonuna</.localized_link> ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` alanına izin verin. CLI dosyaları Mac’e bunun üzerinden yükler, başka bir alana gerek duymaz.
5. İsteğe bağlı olarak, aracının her seferinde sormadan Mac’leri oluşturup silmesine olanak tanıyın. Aracılar, bir Mac hesabınızın limitlerine dahil olduğu için `create_sandbox` çağrısından önce ve geri alınamadığı için `delete_sandbox` öncesinde onay ister. Claude Code’da, MCP sunucusunu kaydettiğiniz adı kullanarak (`tuist` burada) ikisine de `.claude/settings.json` içinde izin verin:

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

Kurulumu aracının yapmasını sağlamak için şu istemi verin:

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

Aracı, proje tarafından sabitlenen [Xcode](#xcode) ile görev başına bir Mac oluşturur: `create_sandbox` seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitlemesini, örneğin `.xcode-version` dosyasını okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git’in görmezden gelmediği dosyaları, taahhüt edilmiş olsun veya olmasın kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac’te zaten [Tuist](#tuist-in-sandbox), proje bir sürüm sabitlediğinde o sabitlenmiş sürüm, hesabınızın önbelleğine giriş yapmış durumda bulunur ve aracı Mac’in rehberini bir kez okur. Aracı ardından `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş bir uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev tamamlandığında Mac’i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır, böylece sonraki komut hemen başlar; `tuist sandbox pause` onu daha erken geri verir. Geride bırakılan bir Mac duraklatılır, iki saatlik ömrü dolduğunda arşivlenir ve 14 gün sonra silinir; aracı uzun bir derlemeden önce ömrü uzatır.

## Linux ve macOS {#platforms}

**Linux** sanal ortamları Ubuntu 24.04 üzerinde çalışır. Her Linux sanal ortamı 16 vCPU’ya sahiptir ve üzerinde çalıştığı makinenin boşta kalan çekirdeklerine kadar genişler; bu nedenle şekli belleğini belirler:

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`, varsayılan)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS** sanal ortamları Apple silicon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Garantili CPU {#guaranteed-cpu}

Bir Linux sanal ortamı, belleğinin her GiB’si başına çeyrek vCPU garantisi alır; örneğin 8 GiB için 2 vCPU ve üzerinde çalıştığı makinede boşta kalan kaynaklar ölçüsünde, en fazla 16 vCPU’ya kadar genişler. Bu durum, çoğunlukla bekleyen ve ardından ani derlemeler yapan bir araca uygundur. Yoğun bir makinede bile daha istikrarlı CPU gerektiğinde, sanal ortam oluşturulurken 1, 2, 4 veya 8 vCPU garanti edin; sanal ortam, bu değer ile bellek garantisi arasında daha büyük olanı alır:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API ve MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **Garanti bir alt sınırdır, üst sınır değil.** 4 garantili vCPU’ya sahip bir sanal ortam, çekirdekler boşta olduğunda yine de 16’ya kadar genişler. Rekabet altında, her sanal ortam garantisine orantılı olarak CPU alır.
- **Minimum olarak faturalandırılır.** Çalışan bir sanal ortam, kullandığı CPU için faturalandırılır ancak garantiden daha az için asla faturalandırılmaz.
- **Bir sanal ortam garantisini ömrü boyunca korur.** Değiştirmek için yeni bir sanal ortam oluşturun.
- **macOS sanal ortamları her zaman tüm şekillerine sahiptir**, bu nedenle garanti almazlar.

### Bir Xcode seçin {#xcode}

Her macOS sanal ortamı, oluşturulurken seçtiğiniz tek bir Xcode sürümüyle çalışır. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı önyükler; böylece bir aracı, CI’nızla aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev üzerinde macOS sanal ortamları şu anda şunları sunar:

- `26.6` (varsayılan)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Çalıştırıcı profillerinde olduğu gibi, tam sürümü kullanarak `xcode_version` (CLI’da `--xcode`) ile birini seçin:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API ve MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp için Tuist Mac eklentisi | `xcode` ile `tuist_mac_start` |
| Amp orb’ları | Orb türü `macos-xcode-26-1-1` (bkz. <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code ve Claude Yönetilen Aracılar | Ortamda `xcode_version` veya Yönetilen Aracı oturumu başına (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılanı alır.
- **Tuist’in sunmadığı bir sürüm reddedilir** ve hata mesajı seçebileceğiniz sürümleri listeler, böylece şu anda nelerin mevcut olduğunu bilirsiniz.
- **Tuist, deponuzdaki `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac’i talep eden aracı seçer. MCP aracı ve Tuist Mac eklentisi, aracılara projenin sabitlediği sürümü eşleştirmelerini söyler.
- **Bir sanal ortam Xcode’unu ömrü boyunca korur.** Başka bir Xcode ile derleme yapmak için yeni bir sanal ortam oluşturun. `xcodebuild -version`, bir Mac’in hangi Xcode’u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sanal ortam kendi sanal makinesidir. Sanal ortamlar, birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sanal ortamlar bir hesaba aittir ve hesabın herhangi bir üyesi bunları kullanabilir ve yönetebilir. Amp orb’u veya Claude Code oturumu gibi bir entegrasyona hizmet veren sanal ortamlar, o oturumun çalışmalarını ve kimlik bilgilerini barındırır: üyeler bunları görebilir, duraklatabilir, devam ettirebilir, arşivleyebilir ve silebilir; ancak yalnızca yöneticiler bunlarda komut çalıştırabilir veya dosya yükleyebilir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlara yalnızca entegrasyonun bağlı olduğu hesabın sanal ortamları erişilebilir.
- Bir entegrasyonu bağlamak için Tuist’e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı, şifrelenmiş olarak saklanır ve bir daha asla gösterilmez.
- Bir sanal ortam internete erişebilir. Bir aracının ondan erişebileceği şeyleri, bir CI işine yaklaşacağınız şekilde ele alın.
