---
{
  "title": "Kimlik Doğrulama",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "CLI'den Tuist sunucusuyla nasıl kimlik doğrulaması yapılacağını öğrenin."
}
---
# Kimlik Doğrulama {#authentication}

Sunucuyla etkileşim kurmak için CLI, istekleri [bearer authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/) kullanarak kimlik doğrulamalıdır. CLI; kullanıcı olarak, hesap olarak veya bir OIDC belirteci kullanarak kimlik doğrulamayı destekler.

## Kullanıcı olarak {#as-a-user}

CLI'yi makinenizde yerel olarak kullanırken, kullanıcı olarak kimlik doğrulamanızı öneririz. Kullanıcı olarak kimlik doğrulamak için aşağıdaki komutu çalıştırmanız gerekir:

```bash
tuist auth login
```

Komut, sizi web tabanlı bir kimlik doğrulama akışından geçirir. Kimlik doğruladıktan sonra, CLI uzun ömürlü bir yenileme belirteci ve kısa ömürlü bir erişim belirtecini `~/.config/tuist/credentials` altında saklar. Dizindeki her dosya, kimlik doğruladığınız alan adını temsil eder; varsayılan olarak bu `tuist.dev.json` olmalıdır. Bu dizinde saklanan bilgiler hassastır, bu nedenle **güvenli tuttuğunuzdan emin olun**.

CLI, sunucuya istek yaparken kimlik bilgilerini otomatik olarak arar. Erişim belirtecinin süresi dolmuşsa, CLI yeni bir erişim belirteci almak için yenileme belirtecini kullanır.

> [!NOTE]
> Kuruluşunuz tek oturum açma (SSO) kullanıyorsa, tarayıcıda kurumsal giriş seçeneğini belirleyin ve iş e-posta adresinizi girin. Tuist, sağlayıcıyı mevcut kuruluş üyeliğinizden veya <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">doğrulanmış giriş e-posta alan adından</.localized_link> bulabilir.

## OIDC belirteçleri {#oidc-tokens}

OpenID Connect (OIDC) destekleyen CI ortamları için Tuist, uzun ömürlü gizli anahtarları yönetmenizi gerektirmeden otomatik olarak kimlik doğrulayabilir. Desteklenen bir CI ortamında çalışırken, CLI OIDC belirteç sağlayıcısını otomatik olarak algılar ve CI tarafından sağlanan belirteci bir Tuist erişim belirteciyle değiştirir.

### Desteklenen sağlayıcılar {#supported-ci-providers}

Tuist bu CI sağlayıcılarını tanır ve belirteçlerini depo bağlantınız aracılığıyla projelerle eşler:

- GitHub Actions
- CircleCI
- Bitrise

[Amp](#amp-orbs) orb’ları, Tuist hesabınıza bağladığınız Amp çalışma alanları üzerinden kimlik doğrular; [Claude Code oturumları](#claude-code-sessions) ise Tuist Sandboxes üzerinde çalıştırmak üzere bağladığınız Claude Code ortamları üzerinden kimlik doğrular.

OpenID Connect belirteçleri veren başka herhangi bir kimlik sağlayıcısı, hesabınızdaki mevcut ve gelecekteki tüm projeler için bir kez yapılandıracağınız bir [iş yükü kimliği güven politikası](#workload-identity-trust-policies) aracılığıyla kimlik doğrulayabilir; örneğin [Fly.io Machines](#flyio-machines).

### OIDC kimlik doğrulamasını ayarlama {#setting-up-oidc-authentication}

GitHub Actions, CircleCI ve Bitrise için:

1. **Deponuzu Tuist’e bağlayın**: GitHub deponuzu Tuist projenize bağlamak için <.localized_link href="/guides/integrations/gitforge/github">GitHub entegrasyon kılavuzunu</.localized_link> izleyin.

2. **Kimlik belirtecine izin verin**: GitHub Actions’ta işe `permissions: id-token: write` izni verin; CircleCI ve Bitrise’ta proje için OIDC’yi etkinleştirin. Tuist 4.218.0’dan itibaren, CLI oturum açmamışsa ve `TUIST_TOKEN` ayarlanmamışsa, CI ortamını algılar ve ilk isteğinde kimlik belirtecini değiştirir, böylece ek bir giriş adımına gerek kalmaz. Daha önceki sürümler önce `tuist auth login` gerektirir; değişim reddedildiğinde erken hata almak ve açıkça oturum açmak için bunu yine de çalıştırabilirsiniz.

Sağlayıcıya özel yapılandırma örnekleri için <.localized_link href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzuna</.localized_link> bakın.

### Amp orb’ları {#amp-orbs}

[Amp](https://ampcode.com) orb’ları, Amp çalışma alanlarını tanımlayan OIDC belirteçleri basabilir. Bir çalışma alanını Tuist hesabınıza bir kez bağlayın; o çalışma alanındaki herhangi bir orb’daki Tuist CLI ve `tuist_ex` Mix görevleri, saklanan bir belirtece veya giriş adımına ihtiyaç duymadan kendi başlarına oturum açar:

1. Kimlikleri bulun: Bir orb içinde çalışan çalışma alanı iş parçacığında `echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID` komutunu çalıştırın.
2. Tuist hesabınızda **Ayarlar → Entegrasyonlar** bölümünü açın, Amp kartındaki **Çalışma alanını bağla** seçeneğini belirleyin ve çalışma alanı kimliğini yapıştırın. Yalnızca tek bir Amp projesinin orb’larına izin vermek için proje kimliğini de yapıştırın. Hesap yöneticisi veya sahibi olmanız gerekir.
3. Çalışma alanının orb’larında Tuist kullanın. Oturum açılmamışsa, CLI veya Mix görevi orb’u algılar, `amp orb id-token --audience https://tuist.dev` ile bir belirteç basar ve bunu bir Tuist oturumuyla değiştirir. `tuist auth login` ve `mix tuist.login` aynı değişimi açıkça gerçekleştirir.

[Amp’in OIDC kılavuzundaki](https://ampcode.com/manual/orbs/oidc) güven yapılandırmalarına benzer şekilde, Tuist her belirteçteki Amp imzasını doğrular ve yalnızca hedef kitlesi `https://tuist.dev`, `token_use` değeri `exchanged`, `workspace_id` bağlı bir çalışma alanıyla eşleşiyorsa ve projeyle sınırlı bir bağlantı söz konusuysa `project_id` o projeye karşılık geliyorsa kabul eder. `sub` alanı, şu iddialardaki gibi aynı çalışma alanını ve proje bağlantısı durumunda aynı projeyi göstermelidir: `workspace:<workspace-id>:project:<project-id>:…`; bu, `amp orb id-token` tarafından varsayılan olarak basılır.

Bir bağlantının izin verdiği her orb, önbellek yüklemeleri dahil olmak üzere hesabın sahip olduğu tüm mevcut ve gelecekteki projelere CI erişimi kazanır. Ayrıca `account:sandboxes:write` kapsamını alır, böylece hesabın bir üyesi gibi <.localized_link href="/guides/features/sandboxes">sandbox’lar</.localized_link> oluşturabilir ve bunlarda komutlar çalıştırabilir; örneğin Linux orb’undan macOS sandbox’ında derleme yapmak için. Bu erişime güvendiğiniz üyelere sahip çalışma alanlarını yalnızca o şekilde bağlayın. Kimliği dikkatlice kontrol edin: Tuist, bağlandığınız çalışma alanına ait olduğunuzu teyit edemez. Bir çalışma alanı birden fazla Tuist hesabına bağlıysa, orb’ların oturum açılacak hesabı belirtmek için `TUIST_OIDC_ACCOUNT` değerini ayarlaması gerekir; bunu Amp projesinin ortam değişkenlerinde ayarlamak, oturum açmanın hesabınıza sabit kalmasını sağlar. Çalışma alanı dışındaki iş parçacıklarının çalışma alanı kimliği yoktur ve bağlantı kullanamazlar. Yeni oturum açmaları durdurmak için Amp kartından çalışma alanının bağlantısını kesin; zaten verilmiş olan oturumlar bir saat sonra sona erene kadar geçerli kalır. Oturumların yenileme belirtecine ihtiyacı yoktur: biri sona yaklaşırken, orb’daki CLI yeni bir Amp belirteci basar ve tekrar değiştirir, böylece uzun süre çalışan orb’lar çalışma alanı bağlıyken oturum açık kalır.

Bir çalışma alanını bağlamadan önce oluşturduğunuz Amp yayıncısına yönelik güven politikaları, `TUIST_OIDC_ACCOUNT` ayarlandığında çalışmaya devam eder.

### Claude Code oturumları {#claude-code-sessions}

Kendi kendine barındırılan bir ortamdaki her Claude Code bulut oturumu, Anthropic tarafından imzalanan bir kimlik belirteci taşır (`CLAUDE_CODE_SESSION_ACCESS_TOKEN`). <.localized_link href="/guides/features/sandboxes/claude#claude-code">Tuist Sandboxes üzerinde çalıştırmak üzere bağladığınız</.localized_link> ortamlarda Tuist, bunu oturuma `TUIST_OIDC_TOKEN` olarak iletir; böylece Tuist CLI ve `tuist_ex` Mix görevleri kendi başlarına oturum açar.

Tuist, Anthropic’in imzasını doğrular ve belirteci yalnızca bir oturum belirteci olduğunda (`ccr:role` değeri `session_worker` ise) kabul eder; burada kitle (audience) alanında adı geçen ortam bir Tuist hesabına bağlı ve etkin olmalıdır. Bağlı bir ortamdaki her oturum, önbellek yüklemeleri dahil olmak üzere hesabın sahip olduğu tüm mevcut ve gelecekteki projelere CI erişimi kazanır ve hesabın bir üyesi gibi hesabın sandbox’larını oluşturup kullanabilir. Böylece Claude kuruluşunuzun ortamı kullanmasına izin verdiği herkes önbelleğinize yayın yapabilir ve üzerinde derleme yapmak için Mac gibi sandbox’lar başlatabilir. Bir oturumun Tuist oturumları, kimlik belirteciyle birlikte veya bir saat sonra, hangisi önce gelirse sona erer; belirteç oturumun başladığı andaki belirteçtir ve varsayılan olarak dört saat geçerlidir, bu nedenle daha uzun süren bir oturum, bir sonraki mesajı yeni bir runner’da devam ettirene kadar Tuist erişimini kaybeder. Yeni oturum açmaları durdurmak için ortamın bağlantısını kesin veya ortamı devre dışı bırakın.

### İş yükü kimliği güven politikaları {#workload-identity-trust-policies}

Bir güven politikası, bir dağıtım platformu, bir Kubernetes kümesi veya kendi yönettiğiniz bir CI sistemi gibi başka bir kimlik sağlayıcısından gelen iş yüklerinin, uzun ömürlü bir Tuist gizli anahtarı olmadan bir projeye erişmesini sağlar. Sağlayıcı şunları yapmalıdır:

- Genel bir adreste HTTPS üzerinden erişilebilir olmalıdır. Tuist yönlendirmeleri takip etmez ve barındırılan Tuist sunucularından gelenler de dahil olmak üzere özel veya dahili ağ adreslerine bağlanmaz.
- Asimetrik bir anahtarla imzalanmış JWT’ler yayınlamalıdır, örneğin `RS256` veya `ES256`. İmzasız belirteçler ve paylaşılan bir gizli anahtarla imzalanmış belirteçler (`HS256` ve benzerleri) reddedilir.
- İmzalama anahtarlarını sabit bir HTTPS URL’sinde JSON Web Key Set (JWKS) olarak yayınlamalıdır. Yanıt en fazla 64 KiB olmalı ve en fazla 20 anahtar içermelidir.
- Her belirtece bir son kullanma süresi (`exp`) eklemelidir.

GitHub Actions, CircleCI ve Bitrise yayıncıları yukarıdaki depo tabanlı akış için ayrılmıştır ve bir güven politikasında kullanılamaz.

> [!NOTE]
> Kendi kendine barındırılan bir dağıtım için, iş yükü kimliklerini yapılandırmadan veya işleri bunlara taşımadan önce veritabanı geçişlerini uygulayın ve hizmet veren her Tuist sunucu çoğaltmasını yükseltin. Ardından CLI veya Elixir entegrasyonunu `TUIST_OIDC_TOKEN` ve `TUIST_OIDC_ACCOUNT` destekleyen bir sürüme yükseltin. Mevcut GitHub Actions, CircleCI ve Bitrise işleri depo tabanlı yetkilendirmeyi kullanmaya devam eder ve bir hesap tanıtıcısı gerektirmez. Üretim işlerine geçmeden önce, kısa ömürlü bir belirteç değişimini ve amaçlanan iş yüküyle bir önbellek işlemini doğrulayın. Yeni değişimleri durdurmak için politikayı kaldırın; zaten verilmiş olan Tuist erişim belirteçlerinin sona ermesi için bir saate kadar süre tanıyın. Bir politikanın silinmesi bu belirteçleri hemen iptal etmez.

#### Politika oluşturma {#create-a-trust-policy}

Tuist kontrol panelinde, hesabınızın **Ayarlar** > **Kimlik Doğrulama** bölümünü açın ve **İş yükü kimlikleri** bölümünü bulun. Hesap yöneticisi (veya kişisel bir hesabın sahibi) olmalısınız. Her hesap en fazla 20 politikaya sahip olabilir. Hesap genelinde CI erişimi için bir kimliği bir kez yapılandırın; proje seçimi gerekmez.

Politika formunu açmak için **İş yükü kimlikleri** yanındaki anahtarı kullanın. Anahtar, hesapta kaydedilmiş kimlikler varsa açık konumda başlar ve kaydettikten sonra açık kalır. Kimliği olmayan hesaplar için kapalı konumda başlar. Kuruluşlar için bu bölüm **SCIM sağlama** altında görünür. Formu gizlemek taslağınızı korur ve iş yükü kimlik doğrulamasını devre dışı bırakmaz: kaydedilen kimlik kartları ve kurulum belgesi bağlantısı görünür kalır. Her kart kimliğin adını, yayıncı ve JWKS URL’lerini, kitleyi, tam JSON iddialarını, hesap genelindeki kapsamı ve oluşturulma zamanını gösterir. Bir kimliği kartındaki eylemi kullanarak kaldırın.

Aşağıdaki alanları girmek için **Özel sağlayıcı** seçeneğini veya bunları kuruluş kısaltmanız ile sayısal kuruluş ve uygulama kimliklerinden oluşturmak için **Fly.io Machines** seçeneğini seçin. Fly şablonu, oluşturulan yayıncıyı, JWKS URL’sini ve iddiaları **Gelişmiş yapılandırma** altında düzenlenebilir tutar. Şablonları veya yardımcı değerleri değiştirmek, elle düzenlediğiniz alanları korur. Yayıncınız, JWKS URL’niz veya iddialarınız şablonu geçersiz kılıyorsa, Tuist **Gelişmiş yapılandırma** bölümünü genişletir ve kaydedilecek politikayı gözden geçirebilmeniz için bir uyarı gösterir. Fly yardımcılarını kullanmadan devam etmek için **Özel sağlayıcı** seçeneğine geri dönün. Şablonlar yalnızca yapılandırmayı doldurur ve Tuist’in belirteçleri nasıl doğruladığını değiştirmez.

| Alan | Açıklama |
| --- | --- |
| Ad | Politikayı tanımak için kullanılan, hesap içinde benzersiz bir etiket. |
| Yayıncı URL’si | Belirtecin `iss` iddiası. Sonundaki eğik çizgi dahil olmak üzere tam olarak eşleşmelidir. |
| JWKS URL’si | Sağlayıcının imzalama anahtarlarının HTTPS URL’si. Tuist bu URL’yi doğrudan kullanır ve sağlayıcının OpenID Connect keşif belgesini okumaz, bu nedenle `jwks_uri` değerini sağlayıcının belgelerinden veya `<issuer>/.well-known/openid-configuration` adresinden kopyalayın. |
| Kitle | Belirtecin hangi kitle için verilmesi gerektiği, varsayılan olarak `tuist`. Belirtecin `aud` değeri buna eşit olmalı veya `aud` bir liste olduğunda bunu içermelidir. Diğer hizmetler için basılmış belirteçlerin burada yeniden oynatılamaması için yalnızca Tuist’in kabul ettiği bir değer kullanın. |
| İddialar | Belirtecin içermesi gereken 1 ila 10 iddiadan oluşan bir JSON nesnesi, örneğin `{"sub": "system:serviceaccount:ci:builder"}`. JSON girişi 8 KiB ile sınırlıdır. Değerler dizeler, işaretli 64 bit tamsayılar veya boole değerleri olmalı ve türleri dahil olmak üzere tam olarak eşleşmelidir: `"123"`, `123` ile eşleşmez. İç içe nesnelere, listelere ve `iss`, `aud`, `exp`, `nbf`, `iat` ve `jti` gibi zaman veya belirteç iddialarına izin verilmez. |

Her politika, tek tek proje seçmeden **hesabın sahip olduğu tüm mevcut ve gelecekteki projelere** CI erişimi sağlar. İlk projeyi oluşturmadan önce bir kimlik yapılandırabilirsiniz. Bu, hesap yönetimi veya başka bir hesaba erişim sağlamaz.

Eşleşen iddialarla bir belirteç alabilen her iş yükü bu projelerin tümüne erişebilir, bu nedenle sağlayıcının garanti ettiği ve kimsenin yeniden kullanamayacağı iddiaları seçin. Silindikten sonra yeniden adlandırılabilecek veya tekrar kaydedilebilecek isimler yerine kararlı sayısal kimlikleri tercih edin.

> [!WARNING]
> Paylaşılan bir kimlik sağlayıcısında, politikayı kuruluşunuz veya kiracınıza **ve** hedeflenen uygulamaya, projeye veya hizmet hesabına bağlayın. `main` gibi bir dal adı, `production` gibi bir ortam veya tek başına genel bir rol bir kimlik sınırı değildir: başka bir kiracı aynı değerlere sahip bir belirteç alabilir. Örneğin, bir GitLab.com politikası yalnızca `ref` değil, hedeflenen projenin kararlı `project_id` değerini de içermelidir. Eşleşen bir belirteç, önbelleğe yazma işlemleri dahil olmak üzere hesap genelinde CI erişimi sağlar; bu nedenle ilgisiz iş yüklerine güvenen bir politika önbellek zehirlenmesine izin verebilir.

Tuist, yayıncıyı, kitleyi, sona erme süresini, geçerlilik başlangıç zamanını (en fazla 60 saniyelik saat sapmasıyla) ve her iddiayı kontrol ettikten sonra yalnızca kendi JWKS URL’sinde belirteci imzalayan anahtarı barındıran politikalar için erişim sağlar. Verilen bir saatlik CI belirteci hesap geneli kapsamındadır, proje kimliklerinin anlık görüntüsü değildir: verilmesinden sonra hesaba oluşturulan veya aktarılan projeleri içerir. Proje yetkilendirmesi hâlâ mevcut hesap sahipliği gerektirdiğinden, bir projeyi dışarı aktarmak o hesabın belirteci altındaki erişimini kaldırır.

#### Bir iş yükünü kimlik doğrulama {#authenticate-a-workload}

1. Sağlayıcınızdan politikanın kitlesine sahip bir kimlik belirteci isteyin.
2. `TUIST_OIDC_TOKEN` değerini bu belirtece ve `TUIST_OIDC_ACCOUNT` değerini projenin sahibi olan Tuist hesabının tanıtıcısına ayarlayın. Hesap, her güven politikası değişimi için gereklidir. Yalnızca nereye bakılacağını seçer ve tek başına hiçbir şey vermez.
3. Tuist’i çalıştırın. `TUIST_TOKEN` veya geçerli saklanmış kimlik bilgileri olmadığında, CLI ve Elixir entegrasyonu belirteci otomatik olarak değiştirir. `tuist auth login` ve `mix tuist.login` aynı değişimi açıkça gerçekleştirir.

Elde edilen Tuist erişim belirteci yalnızca `ci` kapsam grubuna sahiptir ve seçilen hesabın sahip olduğu tüm mevcut ve gelecekteki projeleri kapsar. Hesaptaki 20’den fazla politika aynı belirteçle eşleşirse veya iki farklı JWKS URL’sinden fazlasını kullanırsa değişimler başarısız olur.

Tuist bu oturumları yenilemez. Erişim belirteçleri bir saat sonra sona erer ve yenileme belirteci yoktur. Sağlayıcı kimlik belirteçleri genellikle yalnızca birkaç dakika geçerlidir, bu nedenle eski bir `TUIST_OIDC_TOKEN` tutmak bir yenileme stratejisi değildir: bir saatten uzun süren işler için yeni bir kimlik belirteci isteyin ve Tuist oturumu sona ermeden önce tekrar giriş yapın. Bir politikanın kaldırılması yeni değişimleri durdurur ancak zaten verilmiş olan erişim belirteçleri sona erene kadar geçerli kalır.

Tuist, başarılı bir çekmeden sonra bir sağlayıcının imzalama anahtarlarını özel, boyut sınırlı bir önbellekte en fazla 15 dakika önbelleğe alır. Girdiler daha erken silinebilir ve tekrar çekilebilir. Başarısız çekimler önbelleğe alınmaz. Sağlayıcınız anahtarları döndürüyorsa, yeni anahtarı JWKS’sinde anahtarla belirteç imzalamadan en az 15 dakika önce yayınlamalıdır çünkü önbellekteki kümede olmayan bir anahtarla imzalanan belirteçler önbellek süresi dolana kadar reddedilir. Anahtar kimliği (`kid`) olmayan belirteçler yalnızca JWKS tek bir uygun imzalama anahtarı içerdiğinde kabul edilir. JWKS’de bir anahtar kimliği varsa, bu en fazla 256 bayt uzunluğunda bir dize olmalıdır.

> [!NOTE]
> `TUIST_OIDC_TOKEN` genel bir belirteç girdisidir, sunucu güvenini atlatmanın bir yolu değildir. CI sağlayıcı algılamasına göre önceliklidir ve sunucu hâlâ yalnızca yerleşik sağlayıcıları ve eşleşen bir güven politikasına sahip kimlikleri kabul eder. Bir Tuist kimlik bilgisini bekleyen `TUIST_TOKEN` içine bir kimlik belirteci koymayın.

Değişim başarısız olursa, yayıncının, kitlenin ve politikadaki her iddianın belirteçle tam olarak eşleştiğini, JWKS URL’sinin belirteci imzalayan anahtarı sunduğunu, politikanın kaldırılmadığını ve `TUIST_OIDC_ACCOUNT` değerinin projenin sahibi olan hesabı gösterdiğini kontrol edin. Hangi kimliklerin güvenilir olduğunu ifşa etmemek için Tuist, tüm bu durumlar için aynı hatayı döndürür.

### Fly.io Makineleri {#flyio-machines}

[Fly.io, OIDC iş yükü kimliğini destekler](https://docs.fly.io/reference/openid-connect/). Bir Makine, Fly API belirteci veya uzun ömürlü bir Tuist gizli anahtarı olmadan, yerel `/.fly/api` Unix soketinden kısa ömürlü, imzalı bir kimlik belirteci isteyebilir. Fly belirteçleri bir kaynak deposunu değil, bir kuruluşu ve uygulamayı tanımlar; bu nedenle GitHub deposu bağlamak yerine bir güven politikası kullanın:

1. Fly Makinenizin içinde verilen bir kimlik belirtecinden yayıncıyı (`iss`), kuruluş kimliğini (`org_id`) ve uygulama kimliğini (`app_id`) edinin. Yayıncı `https://oidc.fly.io/<organization-slug>` şeklindedir. Kuruluş veya uygulama adları yerine sayısal kimlikleri kullanın.
2. **Fly.io Makineleri** şablonunu kullanarak [bir güven politikası oluşturun](#create-a-trust-policy) ve kuruluş slug’ını ile her iki sayısal kimliği girin. Aşağıdaki değerleri doldurur ve kimlikleri dize olarak korur. Bunları **Özel sağlayıcı** kullanarak manuel olarak da girebilirsiniz; iddialardaki kimliklerin etrafındaki tırnak işaretlerini koruyun.

   | Alan | Değer |
   | --- | --- |
   | Yayıncı URL’si | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL’si | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Kitle | `tuist` |
   | İddialar | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. Makinenin içinde `TUIST_OIDC_ACCOUNT` değerini projenin sahibi olan Tuist hesap tanıtıcısına (Fly kuruluş slug’ına değil) ayarlayın, `tuist` kitlesiyle bir belirteç isteyin ve bunu `TUIST_OIDC_TOKEN` kullanarak `tuist auth login` komutuna iletin:

```bash
set -euo pipefail
export TUIST_OIDC_ACCOUNT="my-tuist-account"

TUIST_OIDC_TOKEN="$(curl --fail --silent --show-error \
  --unix-socket /.fly/api \
  -X POST http://localhost/v1/tokens/oidc \
  -H 'Content-Type: application/json' \
  --data '{"aud":"tuist"}')"
export TUIST_OIDC_TOKEN

tuist auth login
unset TUIST_OIDC_TOKEN
```

İlk kurulum için, belirteci dışa aktardıktan sonra ve kaldırmadan önce yalnızca kimlik alanlarını yerel olarak inceleyebilirsiniz. Bu, yapılandırma için iddiaları çözer; Tuist kimlik doğrulama sırasında imzayı ayrı olarak doğrular:

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

Belirtecin kendisini yazdırmayın veya depolamayın. Yetkili Fly uygulamasındaki her Makine, Tuist hesabındaki tüm mevcut ve gelecekteki projelere kimlik doğrulayabilir. Her ek uygulama için ayrı bir politika oluşturun. Fly kimlik belirteçleri yaklaşık on dakika sonra sona erer, bu nedenle uzun süre çalışan Makinelerde yeni bir tane isteyin ve bir saatlik Tuist oturumu sona ermeden önce `tuist auth login` komutunu tekrar çalıştırın.

### OIDC belirteç kapsamları {#oidc-token-scopes}

OIDC belirteçlerine `ci` kapsam grubu verilir. GitHub Actions, CircleCI ve Bitrise için bu, depoya bağlı tüm projelere erişim sağlar. Bağlı Amp çalışma alanları, bağlı Claude Code ortamları ve iş yükü kimliği güven politikaları için bu, proje oluşturma, proje yönetimi, çalıştırıcı yönetimi veya hesap üyesi yönetimi vermeden seçilen hesabın sahip olduğu tüm mevcut ve gelecekteki projelere erişim sağlar. `ci` kapsamının neleri içerdiği hakkında ayrıntılar için [Kapsam grupları](#scope-groups) bölümüne bakın.

> [!TIP]
> **Güvenlik avantajları**
>
> OIDC kimlik doğrulaması uzun ömürlü belirteçlerden daha güvenlidir çünkü:
> - Döndürülecek veya yönetilecek gizli anahtar yok
> - Belirteçler kısa ömürlüdür
> - Kimlik doğrulama, depo kimliğinize veya açıkça yetkilendirilmiş bir iş yükü kimliğine bağlıdır


## Gradle eklentisi kimlik doğrulaması {#gradle-plugin-authentication}

Gradle eklentisi, Tuist CLI kimlik doğrulama durumunu kullanır ve ayrı bir giriş akışı tanımlamaz. CLI ile bir kez kimlik doğrulayın; eklenti bu kimlik bilgilerini yeniden kullanacaktır.

Proje ve sunucu yapılandırması için, `project` ve `url` dahil olmak üzere, standart <.localized_link href="/references/tuist-toml">tuist.toml referansını</.localized_link> kullanın.

Yerel kullanım için şunu çalıştırın:

```bash
tuist auth login
```

CI için şunlardan birini kullanın:

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC kimlik doğrulaması</.localized_link> (kullanılabilir olduğunda önerilir)
- `TUIST_TOKEN` aracılığıyla <.localized_link href="/guides/server/authentication#continuous-integration">Hesap belirteci kimlik doğrulaması</.localized_link>

Kendi barındırdığınız Tuist sunucuları için, sunucu URL’sini `tuist.toml` içinde tanımlayın (örneğin `url = "https://tuist.your-company.com"`) ve standart oturum açma akışını çalıştırın. URL, eklenti tarafından kullanılan aynı yapılandırma dosyasından çözülür.

Kimlik doğrulama yapılandırıldıktan sonra Gradle önbellekleme komutlarınızı ve görevlerinizi normal şekilde çalıştırın.

## Hesap belirteçleri {#account-tokens}

OIDC’yi desteklemeyen CI ortamları için veya izinler üzerinde ince ayarlı kontrole ihtiyaç duyduğunuzda hesap belirteçlerini kullanabilirsiniz. Hesap belirteçleri, belirtecin hangi kapsamlara ve projelere erişebileceğini tam olarak belirtmenize olanak tanır.

### Hesap belirteci oluşturma {#creating-an-account-token}

Hesap belirteci oluşturmanın en kolay yolu panodan yapılır:

1. Tuist panosunda kuruluşu açın.
2. **Ayarlar** > **Belirteçler** bölümüne gidin.
3. **Belirteç oluştur** seçeneğini belirleyin.
4. Bir ad, isteğe bağlı sona erme tarihi, proje erişimi ve belirtecin ihtiyaç duyduğu kapsamları seçin.
5. İletişim kutusunu kapatmadan önce oluşturulan belirteç değerini kopyalayın. Belirteç değerleri yalnızca bir kez gösterilir.

Hesap belirteçlerini CLI’dan da oluşturabilirsiniz; bu, betik yazma veya otomasyon için kullanışlıdır:

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> Belirtecin erişmesini istediğiniz projelerin sahibi olan hesabın tanıtıcısıyla `account-handle` ifadesini değiştirin. Bu, kişisel hesabınız olmak zorunda olmayan bir kuruluş hesabı olabilir.

Komut aşağıdaki seçenekleri kabul eder:

| Seçenek | Açıklama |
| --- | --- |
| `--scopes` | Zorunlu. Belirtece verilecek kapsamların boşlukla ayrılmış listesi. |
| `--name` | Zorunlu. Belirteç için benzersiz bir tanımlayıcı (1-32 karakter, yalnızca alfasayısal karakterler, tireler ve alt çizgiler). |
| `--expires` | İsteğe bağlı. Belirtecin ne zaman sona ereceği. `30d` (gün), `6m` (ay) veya `1y` (yıl) gibi biçimler kullanın. Belirtilmezse belirteç asla sona ermez. |
| `--projects` | Belirteci belirli proje tanıtıcılarıyla sınırlayın. Belirtilmezse belirtecin tüm projelere erişimi olur. |

### Mevcut kapsamlar {#available-scopes}

| Kapsam | Açıklama |
| --- | --- |
| `account:cache:read` | Hesap kapsamındaki önbelleğe alınmış ikili dosyaları indir |
| `account:cache:write` | Hesap kapsamındaki önbelleğe alınmış ikili dosyaları yükle |
| `account:members:read` | Hesap üyelerini oku |
| `account:members:write` | Hesap üyelerini yönet |
| `account:pulse:write` | Sentry SDK’dan hesabın Pulse’una hata göndermek için belirteci DSN anahtarı olarak kullan |
| `account:registry:read` | Swift paket kayıt defterinden oku |
| `account:registry:write` | Swift paket kayıt defterine yayınla |
| `account:runners:read` | Çalıştırıcı işlerini, iş akışlarını, profilleri ve birimleri oku |
| `account:runners:write` | Çalıştırıcı profillerini yönet ve çalıştırıcı birimlerini sil |
| `account:sandboxes:write` | Hesabın bir üyesi gibi sanal alanlar oluştur ve bunlarda komutları çalıştır |
| `project:previews:read` | Önizlemeleri indir |
| `project:previews:write` | Önizlemeleri yükle |
| `project:admin:read` | Projeleri ve ayarlarını oku |
| `project:admin:write` | Projeler oluştur, güncelle ve sil. Proje oluşturmak için tüm projelere erişimi olan bir belirteç gerekir. |
| `project:cache:read` | Önbelleğe alınmış ikili dosyaları indir |
| `project:cache:write` | Önbelleğe alınmış ikili dosyaları yükle |
| `project:bundles:read` | Paketleri görüntüle |
| `project:bundles:write` | Paketleri yükle |
| `project:tests:read` | Test sonuçlarını oku |
| `project:tests:write` | Test sonuçlarını yükle |
| `project:builds:read` | Derleme analizlerini oku |
| `project:builds:write` | Derleme analizlerini yükle |
| `project:runs:read` | Komut çalıştırmalarını oku |
| `project:runs:write` | Komut çalıştırmaları oluştur ve güncelle |

### Kapsam grupları {#scope-groups}

Kapsam grupları, tek bir tanımlayıcıyla birden fazla ilgili kapsamı vermenin kullanışlı bir yolunu sağlar. Bir kapsam grubu kullandığınızda, içerdiği tüm bireysel kapsamları otomatik olarak genişletir.

| Kapsam Grubu | Dahil Edilen Kapsamlar |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### Sürekli Entegrasyon {#continuous-integration}

OIDC’yi desteklemeyen CI ortamları için, CI iş akışlarınızın kimlik doğrulamasını yapmak üzere `ci` kapsam grubuna sahip bir hesap belirteci oluşturun. Panoda, belirteci oluştururken **CI** ön ayarını seçin.

Aynı belirteci CLI’dan da oluşturabilirsiniz:

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

Bu işlem, tipik CI işlemleri (önbellek, önizlemeler, paketler, testler, derlemeler ve çalıştırmalar) için gereken tüm kapsamlara sahip bir belirteç oluşturur. Oluşturulan belirteci CI ortamınızda bir gizli bilgi olarak saklayın ve `TUIST_TOKEN` ortam değişkeni olarak ayarlayın.

### Hesap belirteçlerini yönetme {#managing-account-tokens}

Hesap panosunda **Ayarlar** > **Belirteçler** bölümünü açarak hesap belirteçlerini görüntüleyebilir, bir belirtecin kapsamlarını ve proje erişimini inceleyebilir ve döndürme sırasında belirteçleri iptal edebilirsiniz.

Bir hesabın tüm belirteçlerini listelemek için:

```bash
tuist account tokens list account-handle
```

Bir belirteci adına göre iptal etmek için:

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### Hesap belirteçlerini kullanma {#using-account-tokens}

Hesap belirteçlerinin `TUIST_TOKEN` ortam değişkeni olarak tanımlanması beklenir:

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **Hesap belirteçleri ne zaman kullanılır**
>
> Şu durumlarda hesap belirteçlerini kullanın:
> - OIDC’yi desteklemeyen CI ortamlarında kimlik doğrulama
> - Belirtecin hangi işlemleri gerçekleştirebileceği üzerinde ayrıntılı kontrol
> - Bir hesap içindeki birden fazla projeye erişebilen bir belirteç
> - Otomatik olarak sona eren süre sınırlı belirteçler
