---
{
  "title": "Kimlik Doğrulama",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "CLI'dan Tuist sunucusuyla nasıl kimlik doğrulaması yapılacağını öğrenin."
}
---
# Kimlik Doğrulama {#authentication}

Sunucuyla etkileşim kurmak için CLI, istekleri [bearer authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/) kullanarak doğrulamalıdır. CLI; kullanıcı olarak, hesap olarak veya bir OIDC jetonu kullanarak kimlik doğrulamayı destekler.

## Kullanıcı olarak {#as-a-user}

CLI'yı makinenizde yerel olarak kullanırken, kullanıcı olarak kimlik doğrulamanızı öneririz. Kullanıcı olarak kimlik doğrulamak için aşağıdaki komutu çalıştırmanız gerekir:

```bash
tuist auth login
```

Komut, web tabanlı bir kimlik doğrulama akışından geçmenizi sağlar. Kimlik doğruladıktan sonra CLI, uzun ömürlü bir yenileme jetonu ve kısa ömürlü bir erişim jetonunu `~/.config/tuist/credentials` altında saklar. Dizindeki her dosya, kimlik doğrulamasını yaptığınız alan adını temsil eder; varsayılan olarak bu `tuist.dev.json` olmalıdır. Bu dizinde saklanan bilgiler hassastır, bu nedenle **güvenli tuttuğunuzdan emin olun**.

CLI, sunucuya istek yaparken kimlik bilgilerini otomatik olarak arar. Erişim jetonunun süresi dolmuşsa, CLI yeni bir erişim jetonu almak için yenileme jetonunu kullanır.

> [!NOTE]
> Kuruluşunuz tek oturum açma (SSO) kullanıyorsa, tarayıcıda kurumsal giriş seçeneğini belirleyin ve iş e-posta adresinizi girin. Tuist, sağlayıcıyı mevcut kuruluş üyeliğinizden veya <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">doğrulanmış giriş e-posta alan adından</.localized_link> bulabilir.

## OIDC jetonları {#oidc-tokens}

OpenID Connect (OIDC) destekleyen CI ortamları için Tuist, uzun ömürlü gizli anahtarları yönetmenize gerek kalmadan otomatik olarak kimlik doğrulayabilir. Desteklenen bir CI ortamında çalışırken, CLI OIDC jeton sağlayıcısını otomatik olarak algılar ve CI tarafından sağlanan jetonu bir Tuist erişim jetonu ile değiştirir.

### Desteklenen sağlayıcılar {#supported-ci-providers}

Tuist şu CI sağlayıcılarını tanır ve jetonlarını depo bağlantınız aracılığıyla projelere eşler:

- GitHub Actions
- CircleCI
- Bitrise

OpenID Connect jetonları veren başka herhangi bir kimlik sağlayıcısı, hesabınızdaki tüm mevcut ve gelecekteki projeler için bir kez yapılandıracağınız bir [iş yükü kimliği güven ilkesi](#workload-identity-trust-policies) aracılığıyla kimlik doğrulayabilir; örneğin [Fly.io Machines](#flyio-machines).

### OIDC kimlik doğrulamasını ayarlama {#setting-up-oidc-authentication}

GitHub Actions, CircleCI ve Bitrise için:

1. **Deponuzu Tuist'e bağlayın**: GitHub deponuzu Tuist projenize bağlamak için <.localized_link href="/guides/integrations/gitforge/github">GitHub entegrasyon kılavuzunu</.localized_link> izleyin.

2. **`tuist auth login` komutunu çalıştırın**: CI iş akışınızda, kimlik doğrulama gerektiren komutlardan önce `tuist auth login` komutunu çalıştırın. CLI, CI ortamını otomatik olarak algılar ve OIDC kullanarak kimlik doğrular.

Sağlayıcıya özel yapılandırma örnekleri için <.localized_link href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzuna</.localized_link> bakın.

### İş yükü kimliği güven ilkeleri {#workload-identity-trust-policies}

Bir güven ilkesi, dağıtım platformu, Kubernetes kümesi veya kendi yönettiğiniz bir CI sistemi gibi başka bir kimlik sağlayıcısından gelen iş yüklerinin, uzun ömürlü bir Tuist gizli anahtarı olmadan bir projeye erişmesine olanak tanır. Sağlayıcı şunları yapmalıdır:

- Genel bir adreste HTTPS üzerinden erişilebilir olmalıdır. Tuist yönlendirmeleri takip etmez ve barındırılan Tuist sunucularından gelenler dahil olmak üzere özel veya dahili ağ adreslerine bağlanmaz.
- Asimetrik bir anahtarla imzalanmış JWT'ler yayınlamalıdır, örneğin `RS256` veya `ES256`. İmzasız jetonlar ve paylaşılan bir gizli anahtarla imzalanan jetonlar (`HS256` ve benzerleri) reddedilir.
- İmzalama anahtarlarını sabit bir HTTPS URL'sinde JSON Web Key Set (JWKS) olarak yayınlamalıdır. Yanıt en fazla 64 KiB olmalı ve en fazla 20 anahtar içermelidir.
- Her jetonda bir son kullanma süresi (`exp`) bulunmalıdır.

GitHub Actions, CircleCI ve Bitrise yayıncıları yukarıdaki depo tabanlı akış için ayrılmıştır ve bir güven ilkesinde kullanılamaz.

> [!NOTE]
> Kendi barındırdığınız bir dağıtım için, iş yükü kimliklerini yapılandırmadan veya işleri bunlara taşımadan önce veritabanı geçişlerini uygulayın ve hizmet veren her Tuist sunucu kopyasını yükseltin. Ardından CLI veya Elixir entegrasyonunu `TUIST_OIDC_TOKEN` ve `TUIST_OIDC_ACCOUNT` destekleyen bir sürüme yükseltin. Mevcut GitHub Actions, CircleCI ve Bitrise işleri depo tabanlı yetkilendirmeyi kullanmaya devam eder ve bir hesap tanıtıcısı gerektirmez. Üretim işlerine geçmeden önce, kısa ömürlü bir jeton değişimini ve hedeflenen iş yüküyle bir önbellek işlemini doğrulayın. Yeni değişimleri durdurmak için ilkeyi kaldırın; zaten verilmiş Tuist erişim jetonlarının süresinin dolması için en fazla bir saat bekleyin. Bir ilkenin silinmesi bu jetonları hemen iptal etmez.

#### İlke oluşturma {#create-a-trust-policy}

Tuist kontrol panelinde, hesabınızın **Ayarlar** > **Kimlik Doğrulama** bölümünü açın ve **İş yükü kimlikleri** bölümünü bulun. Hesap yöneticisi (veya kişisel bir hesabın sahibi) olmalısınız. Her hesap en fazla 20 ilkeye sahip olabilir. Hesap genelinde CI erişimi için bir kimliği bir kez yapılandırın; proje seçimi gerekmez.

İlke formunu açmak için **İş yükü kimlikleri** yanındaki anahtarı kullanın. Anahtar, hesap kaydedilmiş kimliklere sahipse açık konumda başlar ve kaydetmeden sonra açık kalır. Kimliği olmayan hesaplar için kapalı konumda başlar. Kuruluşlar için bu bölüm **SCIM provisionlama** altında görünür. Formu gizlemek taslağınızı korur ve iş yükü kimlik doğrulamasını devre dışı bırakmaz: kaydedilen kimlik kartları ve kurulum belgesi bağlantısı görünür kalır. Her kart kimliğin adını, yayıncı ve JWKS URL'lerini, hedef kitleyi, tam JSON iddialarını, hesap genelindeki kapsamı ve oluşturulma zamanını gösterir. Bir kimliği kartındaki eylemi kullanarak kaldırın.

Aşağıdaki alanları girmek için **Özel sağlayıcı** seçeneğini veya bunları kuruluş slug'ınız ve sayısal kuruluş ve uygulama kimliklerinizden oluşturmak için **Fly.io Machines** seçeneğini belirleyin. Fly şablonu, oluşturulan yayıncıyı, JWKS URL'sini ve iddiaları **Gelişmiş yapılandırma** altında düzenlenebilir tutar. Şablonları veya yardımcı değerleri değiştirmek, manuel olarak düzenlediğiniz alanları korur. Yayıncınız, JWKS URL'niz veya iddialarınız şablonu geçersiz kılıyorsa, Tuist **Gelişmiş yapılandırma** bölümünü genişletir ve kaydedilecek ilkeyi gözden geçirebilmeniz için bir uyarı gösterir. Fly yardımcıları olmadan devam etmek için **Özel sağlayıcı** seçeneğine geri dönün. Şablonlar yalnızca yapılandırmayı doldurur ve Tuist'in jetonları nasıl doğruladığını değiştirmez.

| Alan | Açıklama |
| --- | --- |
| Ad | İlkeyi tanımlamak için kullanılan, hesap içinde benzersiz bir etiket. |
| Yayıncı URL'si | Jetonun `iss` iddiası. Sondaki eğik çizgi dahil olmak üzere tam olarak eşleşmelidir. |
| JWKS URL'si | Sağlayıcının imzalama anahtarlarının HTTPS URL'si. Tuist bu URL'yi doğrudan kullanır ve sağlayıcının OpenID Connect keşif belgesini okumaz; bu nedenle `jwks_uri` değerini sağlayıcının belgelerinden veya `<issuer>/.well-known/openid-configuration` adresinden kopyalayın. |
| Hedef kitle | Jetonun verilmesi gereken hedef kitle, varsayılan olarak `tuist`. Jetonun `aud` değeri buna eşit olmalı veya `aud` bir liste olduğunda bunu içermelidir. Yalnızca Tuist'in kabul ettiği bir değer kullanın; böylece diğer hizmetler için basılan jetonlar burada tekrar oynatılamaz. |
| İddialar | Jetonun içermesi gereken 1 ila 10 iddiadan oluşan bir JSON nesnesi, örneğin `{"sub": "system:serviceaccount:ci:builder"}`. JSON girişi 8 KiB ile sınırlıdır. Değerler dizeler, işaretli 64 bitlik tamsayılar veya boole değerleri olmalı ve türleri dahil olmak üzere tam olarak eşleşmelidir: `"123"`, `123` ile eşleşmez. İç içe geçmiş nesnelere, listelere ve `iss`, `aud`, `exp`, `nbf`, `iat` ve `jti` gibi zaman veya jeton iddialarına izin verilmez. |

Her ilke, tek tek projeleri seçmeye gerek kalmadan **hesaba ait tüm mevcut ve gelecekteki projelere** CI erişimi sağlar. İlk projeyi oluşturmadan önce bir kimlik yapılandırabilirsiniz. Bu, hesap yönetimi veya başka bir hesaba erişim sağlamaz.

Eşleşen iddialara sahip bir jeton alabilen her iş yükü bu projelerin tümüne erişebilir; bu nedenle sağlayıcının garanti ettiği ve kimsenin yeniden kullanamayacağı iddiaları seçin. Silindikten sonra yeniden adlandırılabilecek veya tekrar kaydedilebilecek isimler yerine kararlı sayısal kimlikleri tercih edin.

> [!WARNING]
> Paylaşımlı bir kimlik sağlayıcısında, ilkeyi kuruluşunuz veya kiracınız **ve** amaçlanan uygulama, proje veya hizmet hesabıyla ilişkilendirin. `main` gibi bir dal adı, `production` gibi bir ortam veya genel bir rol tek başına bir kimlik sınırı değildir: başka bir kiracı aynı değerlere sahip bir jeton alabilir. Örneğin, bir GitLab.com ilkesi yalnızca `ref` değil, amaçlanan projenin kararlı `project_id` değerini de içermelidir. Eşleşen bir jeton, önbellek yazma işlemleri dahil olmak üzere hesap genelinde CI erişimi sağlar; bu nedenle alakasız iş yüklerine güvenen bir ilke önbellek zehirlenmesine yol açabilir.

Tuist, yayıncıyı, hedef kitleyi, sona erme süresini, geçerlilik başlangıç zamanını (en fazla 60 saniyelik saat sapmasıyla) ve her iddiayı kontrol ettikten sonra, yalnızca kendi JWKS URL'sinde jetonu imzalayan anahtarı barındıran ilkeler için erişim sağlar. Verilen bir saatlik CI jetonu hesap geneli içindir, proje kimliklerinin anlık görüntüsü değildir: verildikten sonra hesapta oluşturulan veya hesaba aktarılan projeleri içerir. Proje yetkilendirmesi hâlâ mevcut hesap sahipliği gerektirdiğinden, bir projeyi dışarı aktarmak o hesabın jetonu altındaki erişimini kaldırır.

#### Bir iş yükünü kimlik doğrulaması yapma {#authenticate-a-workload}

1. Sağlayıcınızdan ilkenin hedef kitlesine sahip bir kimlik jetonu isteyin.
2. `TUIST_OIDC_TOKEN` değerini bu jetona ve `TUIST_OIDC_ACCOUNT` değerini projeye sahip olan Tuist hesabının tanıtıcısına ayarlayın. Hesap, her güven ilkesi değişimi için gereklidir. Yalnızca nereye bakılacağını belirler ve tek başına hiçbir şey sağlamaz.
3. `tuist auth login` komutunu çalıştırın. Elixir projeleri için bunun yerine `mix tuist.login` kullanabilir veya `TUIST_TOKEN` ya da geçerli saklanmış kimlik bilgileri olmadığında Elixir entegrasyonunun jetonu otomatik olarak değiştirmesine izin verebilirsiniz.

Elde edilen Tuist erişim jetonu yalnızca `ci` kapsam grubuna sahiptir ve seçilen hesaba ait tüm mevcut ve gelecekteki projeleri kapsar. Hesaptaki 20'den fazla ilke aynı jetonla eşleşirse veya iki farklı JWKS URL'sinden fazlasını kullanırsa değişimler başarısız olur.

Tuist bu oturumları yenilemez. Erişim jetonları bir saat sonra sona erer ve yenileme jetonu yoktur. Sağlayıcı kimlik jetonları genellikle yalnızca birkaç dakika geçerlidir; bu nedenle eski bir `TUIST_OIDC_TOKEN` tutmak bir yenileme stratejisi değildir: bir saatten uzun süren işler için yeni bir kimlik jetonu isteyin ve Tuist oturumu sona ermeden önce tekrar giriş yapın. Bir ilkeyi kaldırmak yeni değişimleri durdurur ancak zaten verilen erişim jetonları sona erene kadar geçerli kalır.

Tuist, başarılı bir çekimden sonra sağlayıcının imzalama anahtarlarını özel, boyut sınırlı bir önbellekte en fazla 15 dakika önbelleğe alır. Girişler daha erken silinebilir ve tekrar çekilebilir. Başarısız çekimler önbelleğe alınmaz. Sağlayıcınız anahtarları döndürüyorsa, yeni anahtarı jetonlarla imzalamadan en az 15 dakika önce JWKS'sinde yayınlamalıdır; çünkü önbellekteki sette olmayan bir anahtarla imzalanan jetonlar, önbellek sona erene kadar reddedilir. Anahtar kimliği (`kid`) olmayan jetonlar, yalnızca JWKS tek bir uygun imzalama anahtarı içerdiğinde kabul edilir. JWKS'te bir anahtar kimliği varsa, bu en fazla 256 baytlık bir dize olmalıdır.

> [!NOTE]
> `TUIST_OIDC_TOKEN` genel bir jeton girdisidir, sunucu güvenini atlamanın bir yolu değildir. CI sağlayıcı algılamasına göre önceliklidir ve sunucu hâlâ yalnızca yerleşik sağlayıcıları ve eşleşen güven ilkesine sahip kimlikleri kabul eder. Bir Tuist kimlik bilgisi bekleyen `TUIST_TOKEN` içine bir kimlik jetonu koymayın.

Değişim başarısız olursa, yayıncının, hedef kitlenin ve ilkedeki her iddianın jetonla tam olarak eşleştiğini, JWKS URL'sinin jetonu imzalayan anahtarı sunduğunu, ilkenin kaldırılmadığını ve `TUIST_OIDC_ACCOUNT` değerinin projeye sahip olan hesabı gösterdiğini kontrol edin. Hangi kimliklere güvenildiğini ifşa etmemek için Tuist, tüm bu durumlar için aynı hatayı döndürür.

### Fly.io Machines {#flyio-machines}

[Fly.io, OIDC iş yükü kimliğini destekler](https://docs.fly.io/reference/openid-connect/). Bir Machine, Fly API jetonu veya uzun ömürlü bir Tuist gizli anahtarı olmadan, yerel `/.fly/api` Unix soketinden kısa ömürlü, imzalı bir kimlik jetonu isteyebilir. Fly jetonları bir kaynak deposunu değil, bir kuruluş ve uygulamayı tanımlar; bu nedenle GitHub deposu bağlamak yerine bir güven ilkesi kullanın:

1. Yayıncıyı (`iss`), kuruluş kimliğini (`org_id`) ve uygulama kimliğini (`app_id`) Fly Machine'ınız içinde verilen bir kimlik jetonundan edinin. Yayıncı `https://oidc.fly.io/<organization-slug>` şeklindedir. Kuruluş veya uygulama adları yerine sayısal kimlikleri kullanın.
2. **Fly.io Machines** şablonunu kullanarak [Bir güven ilkesi oluşturun](#create-a-trust-policy) ve kuruluş slug'ını ile her iki sayısal kimliği girin. Aşağıdaki değerleri doldurur ve kimlikleri dize olarak tutar. Bunları **Özel sağlayıcı** kullanarak manuel olarak da girebilirsiniz; iddialardaki kimliklerin etrafındaki tırnak işaretlerini koruyun.

   | Alan | Değer |
   | --- | --- |
   | Yayıncı URL'si | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL'si | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Hedef kitle | `tuist` |
   | İddialar | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. Machine içinde `TUIST_OIDC_ACCOUNT` değerini projeye sahip olan Tuist hesabının tanıtıcısına (Fly kuruluş slug'ına değil) ayarlayın, `tuist` hedef kitleli bir jeton isteyin ve bunu `TUIST_OIDC_TOKEN` kullanarak `tuist auth login` komutuna iletin:

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

İlk kurulum için, jetonu dışa aktardıktan sonra ve ortam değişkeninden kaldırmadan önce yalnızca kimlik alanlarını yerel olarak inceleyebilirsiniz. Bu işlem yapılandırma için iddiaları çözer; Tuist kimlik doğrulama sırasında imzayı ayrı olarak doğrular:

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

Jetonun kendisini yazdırmayın veya depoya kaydetmeyin. Yetkili Fly uygulamasındaki her Machine, Tuist hesabındaki tüm mevcut ve gelecekteki projelere kimlik doğrulaması yapabilir. Her ek uygulama için ayrı bir ilke oluşturun. Fly kimlik jetonları yaklaşık on dakika sonra sona erer, bu nedenle uzun süre çalışan Machine'larda yeni bir jeton isteyin ve bir saatlik Tuist oturumu sona ermeden önce `tuist auth login` komutunu tekrar çalıştırın.

### OIDC jeton kapsamları {#oidc-token-scopes}

OIDC jetonlarına `ci` kapsam grubu verilir. GitHub Actions, CircleCI ve Bitrise için bu, depoya bağlı tüm projelere erişim sağlar. İş yükü kimliği güven ilkeleri için bu, proje oluşturma, proje yönetimi, runner yönetimi veya hesap üyesi yönetimi izni vermeden seçilen hesaba ait tüm mevcut ve gelecekteki projelere erişim sağlar. `ci` kapsamının neleri içerdiğine ilişkin ayrıntılar için [Kapsam grupları](#scope-groups) bölümüne bakın.

> [!TIP]
> **Güvenlik avantajları**
>
> OIDC kimlik doğrulaması, uzun ömürlü jetonlardan daha güvenlidir çünkü:
> - Döndürülmesi veya yönetilmesi gereken gizli anahtar yok
> - Jetonlar kısa ömürlüdür
> - Kimlik doğrulama, depo kimliğinize veya açıkça yetkilendirilmiş bir iş yükü kimliğine bağlıdır


## Gradle eklentisi kimlik doğrulaması {#gradle-plugin-authentication}

Gradle eklentisi, Tuist CLI kimlik doğrulama durumunu kullanır ve ayrı bir giriş akışı tanımlamaz. CLI ile bir kez kimlik doğrulaması yapın; eklenti bu kimlik bilgilerini yeniden kullanacaktır.

Proje ve sunucu yapılandırması için, `project` ve `url` dahil olmak üzere kanonik <.localized_link href="/references/tuist-toml">tuist.toml referansını</.localized_link> kullanın.

Yerel kullanım için şunu çalıştırın:

```bash
tuist auth login
```

CI için şunlardan birini kullanın:

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC kimlik doğrulaması</.localized_link> (mevcut olduğunda önerilir)
- `TUIST_TOKEN` aracılığıyla <.localized_link href="/guides/server/authentication#continuous-integration">Hesap jetonu kimlik doğrulaması</.localized_link>

Kendi barındırdığınız Tuist sunucuları için sunucu URL'sini `tuist.toml` içinde tanımlayın (örneğin `url = "https://tuist.your-company.com"`) ve standart giriş akışını çalıştırın. URL, eklenti tarafından kullanılan aynı yapılandırma dosyasından çözülür.

Kimlik doğrulama yapılandırıldıktan sonra Gradle önbellekleme komutlarınızı ve görevlerinizi normal şekilde çalıştırın.

## Hesap jetonları {#account-tokens}

OIDC'yi desteklemeyen CI ortamları için veya izinler üzerinde ayrıntılı kontrole ihtiyaç duyduğunuzda hesap jetonlarını kullanabilirsiniz. Hesap jetonları, jetonun hangi kapsamlara ve projelere erişebileceğini tam olarak belirtmenize olanak tanır.

### Hesap jetonu oluşturma {#creating-an-account-token}

Hesap jetonu oluşturmanın en kolay yolu panodan geçmektedir:

1. Tuist panosunda kuruluşu açın.
2. **Ayarlar** > **Jetonlar** bölümüne gidin.
3. **Jeton oluştur** seçeneğini belirleyin.
4. Bir ad, isteğe bağlı sona erme tarihi, proje erişimi ve jetonun ihtiyaç duyduğu kapsamları seçin.
5. İletişim kutusunu kapatmadan önce oluşturulan jeton değerini kopyalayın. Jeton değerleri yalnızca bir kez gösterilir.

Hesap jetonlarını CLI'dan da oluşturabilirsiniz; bu, betikleme veya otomasyon için kullanışlıdır:

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> `account-handle` yerine, jetonun erişmesini istediğiniz projelere sahip olan hesabın tanıtıcısını yazın. Bu, kişisel hesabınız değil, bir kuruluş hesabı olabilir.

Komut aşağıdaki seçenekleri kabul eder:

| Seçenek | Açıklama |
| --- | --- |
| `--scopes` | Zorunlu. Jetona verilecek kapsamların boşlukla ayrılmış listesi. |
| `--name` | Zorunlu. Jeton için benzersiz bir tanımlayıcı (1-32 karakter, yalnızca alfasayısal karakterler, tire ve alt çizgi). |
| `--expires` | İsteğe bağlı. Jetonun ne zaman sona ereceği. `30d` (gün), `6m` (ay) veya `1y` (yıl) gibi biçim kullanın. Belirtilmezse jeton asla sona ermez. |
| `--projects` | Jetonu belirli proje tanıtıcılarıyla sınırlayın. Belirtilmezse jeton tüm projelere erişebilir. |

### Mevcut kapsamlar {#available-scopes}

| Kapsam | Açıklama |
| --- | --- |
| `account:cache:read` | Hesap kapsamındaki önbelleğe alınmış ikili dosyaları indir |
| `account:cache:write` | Hesap kapsamındaki önbelleğe alınmış ikili dosyaları yükle |
| `account:members:read` | Hesap üyelerini oku |
| `account:members:write` | Hesap üyelerini yönet |
| `account:registry:read` | Swift paket kayıt defterinden oku |
| `account:registry:write` | Swift paket kayıt defterine yayınla |
| `account:runners:read` | Çalıştırıcı işlerini, iş akışlarını, profilleri ve birimleri oku |
| `account:runners:write` | Çalıştırıcı profillerini yönet ve çalıştırıcı birimlerini sil |
| `project:previews:read` | Önizlemeleri indir |
| `project:previews:write` | Önizlemeleri yükle |
| `project:admin:read` | Projeleri ve ayarlarını oku |
| `project:admin:write` | Proje oluştur, güncelle ve sil. Proje oluşturmak tüm projelere erişimi olan bir jeton gerektirir |
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

Kapsam grupları, tek bir tanımlayıcıyla birden çok ilgili kapsamı vermenin kullanışlı bir yolunu sağlar. Bir kapsam grubu kullandığınızda, içerdiği tüm bireysel kapsamları içerecek şekilde otomatik olarak genişler.

| Kapsam Grubu | Dahil Edilen Kapsamlar |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### Sürekli Entegrasyon {#continuous-integration}

OIDC'yi desteklemeyen CI ortamları için CI iş akışlarınızın kimlik doğrulamasını yapmak üzere `ci` kapsam grubuna sahip bir hesap jetonu oluşturun. Panoda, jetonu oluştururken **CI** ön ayarını seçin.

Aynı jetonu CLI'dan da oluşturabilirsiniz:

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

Bu, tipik CI işlemleri (önbellek, önizlemeler, paketler, testler, derlemeler ve çalıştırmalar) için gereken tüm kapsamlara sahip bir jeton oluşturur. Oluşturulan jetonu CI ortamınızda bir gizli bilgi olarak saklayın ve `TUIST_TOKEN` ortam değişkeni olarak ayarlayın.

### Hesap jetonlarını yönetme {#managing-account-tokens}

Hesap jetonlarını görüntülemek, bir jetonun kapsamlarını ve proje erişimini incelemek ve döndürme sırasında jetonları iptal etmek için hesap panosunda **Ayarlar** > **Jetonlar** bölümünü açın.

Bir hesaba ait tüm jetonları listelemek için:

```bash
tuist account tokens list account-handle
```

Bir jetonu adına göre iptal etmek için:

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### Hesap jetonlarını kullanma {#using-account-tokens}

Hesap jetonlarının `TUIST_TOKEN` ortam değişkeni olarak tanımlanması beklenir:

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **Hesap jetonlarının ne zaman kullanılacağı**
>
> Şu durumlarda hesap jetonlarını kullanın:
> - OIDC'yi desteklemeyen CI ortamlarında kimlik doğrulama
> - Jetonun hangi işlemleri gerçekleştirebileceği üzerinde ayrıntılı kontrol
> - Bir hesap içindeki birden çok projeye erişebilen bir jeton
> - Otomatik olarak süresi dolan, zaman sınırlı jetonlar
