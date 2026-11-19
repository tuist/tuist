---
{
  "title": "Sandboxlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sandboxları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Davet usulü**
>
> Tuist Sandboxları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda davet usulü erişime açıktır. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın. Fiyatlandırma, Sandboxlar genel kullanıma sunulduğunda duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandbox’ına sahiptir; bu sandbox, oturum süresince checkout’unu, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde kaldığı yerden devam eder.

Sandboxlar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı altyapıda, ekibinizin <.localized_link href="/guides/features/cache">önbelleği</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandboxları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb’larını Tuist üzerinde çalıştırın veya <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile herhangi bir Amp sohbetine Xcode derlemeleri için bir Mac tahsis edin.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: terminalinizden veya API üzerinden kendi araçlarınızla sandbox oluşturun ve içinde komutlar çalıştırın.

## CLI ile başlayın {#cli}

`tuist sandbox` kullanarak terminalinizden bir sandbox oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Hesabın herhangi bir üyesi sandboxlarını oluşturup yönetebilir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için, örneğin `--xcode 26.1.1` gibi bir sürümle birlikte `--xcode` geçin; bu seçenek `--platform macos` anlamına gelir. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` geçin, bir Linux sandbox’ına daha fazla [CPU](#guaranteed-cpu) garantisi vermek için `--guaranteed-vcpus` geçin ve daha büyük bir disk için `--workspace-gb` geçin. Komut, sandbox çalışmaya başladığında döner ve ID’si dahil ayrıntılarını yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` geçin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; duraklatılmışsa önce onu sürdürür. `tuist`, ne kadar uzun sürerse sürsün çıktısını akış olarak verir ve komutun durum koduyla çıkar; Ctrl-C ile sandbox içindeki işlemi iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) geçin.

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

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Sandboxları kod üzerinden yönetmek isterseniz, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) aracılığıyla kullanın veya bir aracının <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden bunları kullanmasına izin verin.

Etkileşimli giriş yapamayan araçlar, örneğin bir macOS sandbox’ında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> ile kimlik doğrulaması yapabilir. Bu jeton, hesabın bir üyesinin yapabileceği her şeyi yapabilir: sandbox oluşturmak, içinde komut çalıştırmak ve onları duraklatmak, sürdürmek, arşivlemek ve silmek. Entegrasyon ayarları hesap yöneticilerinde kalır.

### Sandbox içinde Tuist {#tuist-in-sandbox}

Sandbox imajları Tuist CLI ile birlikte gelmez, bu nedenle projenizin sabitlenmiş sürümü çalışır. İlk `tuist sandbox sync` sonrası, sandbox üzerindeki depo kökünde `mise install` çalıştırın (`mise` ve `brew` yüklüdür). `tuist sandbox exec` ile başlattığınız her komutta mise’in shim’leri (`$HOME/.local/share/mise/shims`) `PATH` üzerinde ilk sırada yer alır; böylece `tuist` ve diğer mise araçları komutlarınızda ve Xcode derleme aşamalarında, örneğin bir şemanın post-action’larında çalışır.

`tuist sandbox exec` ile başlattığınız her komut ayrıca bir Tuist runner’ın sahip olduğu erişimi alır; bu sayede sandbox’taki derlemeler, kimlik bilgilerini iletmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sandbox host’unun erişebildiği durumlarda, örneğin macOS’ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik jetonu. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komut içinde önce `tuist auth login` çalıştırın.

Jeton her komut için basılır ve yalnızca o komut çalışırken bir Tuist jetonuyla takas edilebilir; bu nedenle sandbox asla uzun ömürlü bir kimlik bilgisini tutmaz. Komutu başlatan kişinin veya jetonun önbellekle yapabileceğinden fazlasını asla sağlamaz: Yalnızca yazma yetkisine sahip önbellek jetonları olan bir hesabın üyeleri okuma erişimi alır ve sandbox’ın önbelleği kullanabilmesi için bir hesap jetonunun `account:sandboxes:write` yanında `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile geçtiğiniz değişkenler önceliklidir.

## Bir kodlama aracısından Mac üzerinde derleme {#coding-agents}

Linux üzerinde çalışan bir kodlama aracısı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandbox’ında derleyebilir, test edebilir ve çalıştırabilir. Amp’te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer aracılar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac’i nasıl yöneteceğini bildirir.
2. Tuist CLI’yı aracının çalıştığı yere yükleyin, örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM üzerinde `tuist-linux-aarch64`).
3. CLI’yı kimlik doğrulamasından geçirin. MCP sunucusundaki giriş bu ortama taşınmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> olarak ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` adresine izin verin. CLI dosyaları Mac’e bu adres üzerinden yükler; başka bir alan adına gerek yoktur.

Aracı, görev başına bir Mac oluşturur ve projenin sabitlediği [Xcode](#xcode) sürümünü kullanır: `create_sandbox`, seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitleme dosyasını, örneğin `.xcode-version` dosyasını okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git’in yoksaymadığı dosyaları, commit edilmiş olsun ya da olmasın kopyalar; sonrasında yalnızca değişenleri kopyalar. İlk senkronizasyondan sonra Mac’teki depo kök dizininde `mise install` çalıştırır; böylece [projeye sabitlenmiş Tuist](#tuist-in-sandbox) orada hazır olur ve hesabınızın önbelleğine giriş yapmış durumdadır. Aracı ardından `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev tamamlandığında Mac’i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır; böylece sonraki komut anında başlar. `tuist sandbox pause` onu daha erken serbest bırakır. Arkada bırakılan bir Mac duraklatılır ve 14 gün duraklatıldıktan sonra silinir.

## Linux ve macOS {#platforms}

**Linux** sandbox’ları Ubuntu 24.04 üzerinde çalışır. Her Linux sandbox’ı 16 vCPU’ya sahiptir ve üzerinde çalıştığı makinenin boşta kalan çekirdeklerine kadar genişleyebilir; bu nedenle bellek miktarı seçilen şekle göre belirlenir:

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`, varsayılan)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS** sandbox’ları Apple silicon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Garantili CPU {#guaranteed-cpu}

Bir Linux sandbox’ına, belleğinin her GiB’si için bir vCPU’nun dörtte biri garanti edilir; örneğin 8 GiB için 2 vCPU. Makinede boşta kalan kaynaklar olduğunda, 16 vCPU sınırına kadar ek kapasite kullanabilir. Bu model, çoğunlukla bekleyen ve ardından ani derleme yükleri oluşturan bir aracı için uygundur. Yoğun bir makinede bile daha istikrarlı CPU ihtiyacı duyulduğunda, sandbox oluşturulurken 1, 2, 4 veya 8 vCPU garanti edilebilir; sandbox, bu değer ile bellek garantisi arasındaki daha büyük olanı alır:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API ve MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **Garanti bir alt sınırdır, üst sınır değildir.** 4 garantili vCPU’ya sahip bir sandbox, çekirdekler boşta olduğunda hâlâ 16’ya kadar genişler. Rekabet durumunda her sandbox, garantisine orantılı olarak CPU alır.
- **Minimum olarak faturalandırılır.** Çalışan bir sandbox, kullandığı CPU için faturalandırılır ancak garantiden daha az ücretlendirilmez.
- **Sandbox garantisini ömrü boyunca korur.** Değiştirmek için yeni bir sandbox oluşturun.
- **macOS sandbox’ları her zaman tüm şekillerine sahiptir**, bu nedenle garanti almazlar.

### Bir Xcode seçin {#xcode}

Her macOS sandbox’ı tek bir Xcode sürümüyle çalışır; bu sürümü sandbox oluşturulurken seçersiniz. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı başlatır, böylece aracı CI ortamınızdakiyle aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev üzerinde macOS sandbox’ları şu anda şunları sunar:

- `26.6` (varsayılan)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Runner profillerinde olduğu gibi tam sürümü kullanarak `xcode_version` ile (CLI’da `--xcode`) birini seçin:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API ve MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp için Tuist Mac eklentisi | `xcode` ile `tuist_mac_start` |
| Amp orb’ları | `macos-xcode-26-1-1` orb türü (bkz. <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code ve Claude Yönetilen Aracılar | Ortamda veya Yönetilen Aracı oturumu başına `xcode_version` (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılan sürümü alır.
- **Tuist’in sunmadığı bir sürüm reddedilir** ve hata mesajı seçebileceğiniz sürümleri listeler; böylece şu anda hangilerinin mevcut olduğunu görürsünüz.
- **Tuist, deponuzdaki `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac isteyen aracı seçer. MCP aracı ve Tuist Mac eklentisi, aracılara projenin sabitlediği sürümle eşleşmelerini söyler.
- **Bir sandbox, Xcode’unu ömrü boyunca korur.** Başka bir Xcode ile derlemek için yeni bir sandbox oluşturun. `xcodebuild -version`, bir Mac’in hangi Xcode’u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandbox’lar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandbox’lar bir hesaba aittir ve hesabın herhangi bir üyesi bunları kullanabilir ve yönetebilir; entegrasyonlara hizmet eden sandbox’lar da buna dahildir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlar, yalnızca entegrasyonun bağlı olduğu hesabın sandbox’larına erişebilir.
- Bir entegrasyonu bağlamak için Tuist’e verdiğiniz kimlik bilgileri (örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı) şifrelenerek saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının sandbox üzerinden erişebileceği kaynakları, bir CI işine对待 ettiğiniz gibi değerlendirin.
