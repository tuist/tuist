---
{
  "title": "Tek Oturum Açma",
  "titleTemplate": ":title | Kimlik Doğrulama | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tek oturum açmayı nasıl yapılandıracağınızı, bir giriş e-posta alanını nasıl doğrulayacağınızı ve kullanıcıların kuruluşunuza nasıl katılacağını seçmeyi öğrenin."
}
---
# Tek Oturum Açma {#single-sign-on}

Tuist, kuruluşunuz için ek hesap güvenliği sağlamak amacıyla bir oturum açma seçeneği olarak tek oturum açmayı sunar.

Tek oturum açma, kuruluş ayarlarınızdaki **Kimlik Doğrulama** sekmesinden yapılandırılır. Google Workspace, Okta, Microsoft Entra ID ve özel [OAuth 2.0](https://oauth.net/2/) sağlayıcıları desteklenir.

Microsoft Entra ID, Tuist'in dizin tanımlayıcınızdan sizin için yapılandırdığı bir OpenID Connect sağlayıcısıdır. Bu kılavuzun özel sağlayıcılar için açıkladığı her şey, giriş e-posta alanı doğrulaması ve kaydı da dahil olmak üzere, bunun için de geçerlidir.

> [!NOTE]
> Tek oturum açma, üyelerin nasıl kimlik doğrulaması yaptığını ve kimliği doğrulanmış kullanıcıların otomatik olarak katılıp katılamayacağını kontrol eder. <.localized_link href="/guides/integrations/authentication/scim">Çapraz Alan Kimlik Yönetimi sağlama</.localized_link>, bir kimlik sağlayıcısının kuruluş üyeleri oluşturup güncelleyebileceğini ve sağlamanın iptal edilebileceğini kontrol eder. Okta için çoğu kuruluş her ikisini de yapılandırır.

## Erişim nasıl çalışır {#how-access-works}

Sağlayıcı kimliği, oturum açma keşfi ve kuruluş kaydı ayrı konulardır:

- **Sağlayıcı yayıncısı:** Kullanıcının kimliğini doğrulayan sağlayıcı kuruluşu veya yetkilendirme sunucusu. Tuist, bağlı bir kimliği ararken sağlayıcıyı, yayıncıyı ve kararlı sağlayıcı kullanıcı tanımlayıcısını birleştirir. Okta için yayıncı, Okta alan adı ile temsil edilir. Microsoft Entra ID için dizin (kiracı) tanımlayıcısından türetilir. Özel bir sağlayıcı için sağlayıcı URL'si ile temsil edilir.
- **Giriş e-posta alanı:** Tuist'in genel oturum açma sayfasından bir Okta veya özel sağlayıcıyı keşfetmek için kullandığı e-posta alanı. Doğrulandıktan sonra, yeni hesap bağlama ve otomatik kayıt için hangi e-posta adreslerinin güvenilir olabileceğini de belirler.
- **Kayıt politikası:** Güvenilir alandan gelen bir kullanıcının davete ihtiyacı olup olmadığını veya otomatik olarak katılıp katılamayacağını belirler.
- **Sağlama:** Oturum açma akışından bağımsız olarak kuruluş üyeliğini oluşturur ve yönetir.

Sağlayıcı yayıncısı ve giriş e-posta alanı genellikle farklıdır. Örneğin, bir şirket çalışan e-postası için `example.com` kullanırken sağlayıcı yayıncısı `https://login.vendor.example.net` olabilir. Yeni Okta ve özel sağlayıcı yapılandırmaları bu değerleri ayrı olarak saklar.

### Giriş e-posta alanını doğrula {#verify-a-login-email-domain}

Okta ve özel sağlayıcı yapılandırmaları, yeni bir Tuist hesabı oluşturabilmeleri veya mevcut bir hesabı e-posta adresiyle bağlayabilmeleri için doğrulanmış bir giriş e-posta alanı gerektirir. Üyeler, alan doğrulanmamışken bile <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">mevcut hesaplarını bağlayabilir</.localized_link>.

1. Çalışan e-posta alanını, örneğin `example.com`, **Giriş e-posta alanı** alanına girin.
2. Tek oturum açma yapılandırmasını kaydedin.
3. Tuist tarafından gösterilen metin kaydını alanın [Alan Adı Sistemi](https://www.cloudflare.com/learning/dns/dns-records/dns-txt-record/) yapılandırmasına ekleyin.
4. Kimlik Doğrulama ayarlarına dönün ve **Alanı doğrula** öğesine tıklayın.

Doğrulanmış bir giriş e-posta alanı yalnızca bir Tuist kuruluşuna ait olabilir. Alanı değiştirmek doğrulamayı temizler ve yeni metin kaydının yayınlanmasını gerektirir. Otomatik kayıt, alan doğrulanana kadar duraklatılmış olarak kalır.

Tuist metin kaydını günlük olarak yeniden kontrol eder. Çözümlemeyi durduran bir kayıt doğrulamayı hemen temizlemez: alan bunu 14 gün boyunca korur ve Kimlik Doğrulama ayarları, tekrar yayınlamak üzere kayıtla birlikte **Doğrulama süresi doluyor** gösterir. Kaydı yayınlamak ve doğrulamak uyarıyı temizler. 14 gün sonra kaydı hala eksik olan bir alan doğrulanmamış durumuna döner ve sağlayıcı keşfi, kimlik bağlama ve otomatik kayıt, tekrar doğrulanana kadar durur. Başka bir nedenle başarısız olan bir arama zamanlayıcıyı yenilemez ve doğrulamayı kendi başına temizlemez. Günlük yeniden kontroller tanıtılmadan önce doğrulanan alanlar yeniden kontrol edilmez.

Google, doğrulanmış Workspace alanını kimliği doğrulanmış kimliğin bir parçası olarak sağladığından Google Workspace bu ayrı Tuist doğrulama adımını gerektirmez.

### Bir kayıt politikası seçin {#choose-an-enrollment-policy}

Tuist iki kayıt politikasını destekler:

- **Yalnızca davetle:** Kullanıcının bir kuruluş davetine ihtiyacı vardır. Okta ve özel sağlayıcılar için, sağlayıcının yepyeni bir Tuist hesabı oluşturabilmesi için giriş e-posta alanının hala doğrulanmış olması gerekir. Mevcut bir Tuist hesabı olan davetli kullanıcı önce daveti kabul eder, ardından <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">Mevcut bir Tuist hesabını bağla</.localized_link> bölümünde açıklandığı gibi sağlayıcı kimliğini bağlar.
- **Otomatik:** Kimliği doğrulanmış e-postası güvenilir alanla eşleşen bir kullanıcı, davet olmadan hesap oluşturabilir veya bağlayabilir ve kuruluşa katılabilir. Google yapılandırmaları Workspace alanını kullanır. Okta ve özel sağlayıcılar doğrulanmış bir giriş e-posta alanı gerektirir.

Google yapılandırmaları varsayılan olarak otomatik kayda ayarlanır. Yeni Okta ve özel sağlayıcı yapılandırmaları varsayılan olarak yalnızca davetle kayda ayarlanır.

**Tek oturum açmayı zorla** ayarı kayıttan bağımsızdır. Kuruluşun korunan tarayıcı sayfalarına erişim, mevcut sağlayıcısı ve yayıncısı (veya doğrulanmış Google Workspace) aracılığıyla kimliği doğrulanmış bir oturum gerektirir. Geçmişte bağlanmış bir kimlik veya farklı bir kuruluşun sağlayıcısı aracılığıyla kimlik doğrulama yetersizdir. Tuist'e normal oturum açma ve diğer hesaplara erişim kullanılabilir olmaya devam eder; zorlama, kuruluş üyeliği sağlamaz. Anonim genel panolar ve sınırlı süreli operatör destek izinleri kendi erişim kurallarını korur. Uygulama önizleme sayfaları zorlamayı yalnızca kuruluş üyelerine uygular, bu nedenle kuruluş dışında paylaşılan önizleme bağlantıları, ziyaretçilerin zaten açabildiği önizlemeler için çalışmaya devam eder.

Zorlama, bir üyenin oturumunun kuruluşa ulaştığı her yerde uygulanır:

- **Pano**: Kuruluşun sayfaları ve bunların <.localized_link href="/guides/features/agentic-coding/mcp#webmcp">WebMCP</.localized_link> aracılığıyla tarayıcı aracılarına sunduğu araçlar, kuruluşun sağlayıcısıyla oturum açılmış bir oturum gerektirir.
- **Tuist CLI, Tuist uygulaması, MCP istemcileri ve API referansı**: Bunlarda oturum açmak, üye adına her kuruluşta işlem yapan bir kimlik bilgisi oluşturur; bu nedenle tek oturum açmayı zorlayan kuruluş üzerinden oturum açılmış bir oturum gerektirir. Tuist, başka bir şekilde oturum açmış üyeyi önce sağlayıcıya yönlendirir ve e-posta/parola veya Apple ile oturum açmayı reddeder. Bu istemcilerden biri kimlik bilgisini her yenilediğinde Tuist tekrar kontrol eder. Kuruluşun tek oturum açma yöntemiyle elde edilen bir kimlik bilgisi yenilenmeye devam eder; daha önce kuruluşun sağlayıcısı üzerinden oturum açmış bir üyenin başka bir yolla elde ettiği kimlik bilgisi de aynı şekilde yenilenir. Parola gibi başka bir yolla, kuruluş tek oturum açmayı zorlamadan önce elde edilmiş diğer kimlik bilgileri, zorlama altındaki ilk yenilemelerinden itibaren dört hafta boyunca yenilenmeye devam eder; ardından istemci üyeden tekrar oturum açmasını ister. Bu süre içinde panoda veya `tuist auth login` kullanarak sağlayıcı üzerinden oturum açmak, yenilemenin sürmesini sağlar.

Tek oturum açmayı zorlayan birkaç kuruluşun üyesi olan bir kişi, CLI'ye, uygulamaya veya MCP istemcilerine oturum açamaz çünkü bir oturum yalnızca bir kuruluş üzerinden oturum açar.

### Kayıtlı üyelerin alacağı rolü seçin {#choose-the-enrollment-role}

Otomatik olarak katılan üyeler, **Kayıtlı üyeler için rol** altında ayarlanan <.localized_link href="/guides/server/accounts-and-projects#roles">rolü</.localized_link> alır; bir yönetici değiştirmedikçe bu rol `user` olur. Bunu `viewer` olarak ayarlamak, dizindeki herkese değişiklik yapma yetkisi vermeden oturum açmaya izin verir.

Ayar `admin` olarak ayarlanamaz; rolü olmayan <.localized_link href="/guides/integrations/authentication/scim">SCIM</.localized_link> üzerinden sağlanan üyelere ve oturum açanlara uygulanır ve bir yöneticinin manuel olarak ayarladığı bir rolü asla üzerine yazmaz.

### Mevcut bir Tuist hesabını bağla {#link-an-existing-account}

Bağlı bir sağlayıcı kimliği, hesabın ait olduğu diğer tüm kuruluşlar dahil olmak üzere tüm Tuist hesabında oturum açar. Okta ve özel sağlayıcılar için Tuist, mevcut bir hesabı yalnızca e-posta adresi doğrulanmış giriş e-posta alanında olduğunda veya kuruluşun SCIM sağlaması hesabı oluşturduğunda otomatik olarak bağlar.

Hesabı uygun olmayan üyeler kimliği kendileri bağlar:

1. Hesabın normal oturum açma yöntemiyle Tuist'e giriş yapın.
2. Kimlik sağlayıcısından (örneğin uygulama kutucuğundan) Tuist'i açın veya tek oturum açmayı zorluyorsa kuruluşun projelerinden birini açın.
3. Tuist'in gösterdiği kuruluşu ve kimlik sağlayıcı hesabını onaylayın, ardından **Hesabı bağla** düğmesine tıklayın.

Oturumu kapalıyken tek oturum açmayla başlayan bir üyeden önce oturum açması istenir ve Tuist ardından onaylamaya geri döner. Bağlama alan doğrulamasına bağlı değildir, bu nedenle üyeler alan doğrulanmadan önce tek oturum açmayı kullanabilir.

### Mevcut kuruluşlar {#existing-organizations}

Tüm Okta ve özel sağlayıcı kuruluşları doğrulanmış alan modelini kullanır. Geçici uyumluluk modu kaldırıldı.

Giriş e-posta alanınız doğrulanmamışsa:

- Mevcut bağlı üyeler oturum açmaya devam edebilir ve mevcut SSO zorlaması kuruluş üyelerine uygulanmaya devam eder.
- Giriş sayfası sağlayıcınızı yalnızca mevcut kuruluş üyeliği aracılığıyla keşfeder.
- Otomatik kayıt duraklatılır ve sağlayıcı, davetle bile olsa yeni Tuist hesapları oluşturamaz.
- Bağlantısı olmayan üyeler mevcut Tuist hesaplarında oturum açar ve yukarıda açıklandığı gibi bağlantıyı onaylar. Kuruluşun SCIM sağlaması tarafından oluşturulan hesaplar, ilk SSO oturum açmada hala bağlanabilir.
- Yeni kayıtlar, e-posta adresleri alanınızı kullandığı için yalnızca sağlayıcınızı kullanmak zorunda değildir.

Mevcut etkin kayıt ve zorlama ayarları kaydedilir ve kapatılabilir. Yöneticiler alan doğrulanmamışken yapılandırmayı düzenleyebilir; herhangi bir ayarı etkinleştirmek doğrulama gerektirir. Doğrulama, bu ayar etkinleştirildiğinde eşleşen e-posta adresleri için otomatik kaydı yeniden başlatır. Google Workspace davranışı değişmez.

**Giriş e-posta alanı** kuruluşunuzun üyelerinden zaten doldurulmuş olabilir. Değeri onaylayın, metin kaydını yayınlayın ve **Alanı doğrula** düğmesine tıklayın. Günlük yeniden kontroller için kaydı yayında tutun.

## Google Workspace {#google}

Google Workspace tek oturum açma, kullanıcıları bir Workspace alanına karşı doğrular. Yöneticiler eşleşen kullanıcıların otomatik olarak katılmasına izin verebilir veya davet isteyebilir.

> [!NOTE]
> **Ön koşullar**
>
> Doğrulanmış bir alana sahip bir Google Workspace kuruluşuna ihtiyacınız var. Ayrıca, kurduğunuz alanla ilişkili bir e-posta kullanarak Google ile kimlik doğrulamanız gerekir.

### Kurulum {#google-setup}

1. Kuruluşunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. Tek oturum açmayı etkinleştirin.
3. Sağlayıcı olarak **Google** seçeneğini belirleyin.
4. Google Workspace alanınızı girin, örneğin `example.com`.
5. **Otomatik kayıt** veya yalnızca davetle kaydı seçin. Google için otomatik kayıt varsayılan olarak etkindir.
6. İsteğe bağlı olarak, oturum açma akışını test ettikten sonra **Tek oturum açmayı zorla** seçeneğini etkinleştirin.
7. **Değişiklikleri kaydet** düğmesine tıklayın.

## Okta {#okta}

Okta, üyeleri doğrulamak için [OpenID Connect](https://openid.net/developers/how-connect-works/) kullanır. Okta alanı sağlayıcı yayıncısını tanımlar; ayrı olarak doğrulanmış giriş e-posta alanı keşfi, yeni hesap bağlamayı ve kaydı kontrol eder.

Okta'nın üyeleri otomatik olarak oluşturmasını, güncellemesini veya sağlama dışı bırakmasını da istiyorsanız, tek oturum açma çalıştıktan sonra <.localized_link href="/guides/integrations/authentication/scim#okta">Okta Sistemler Arası Kimlik Yönetimi sağlamasını</.localized_link> yapılandırın.

### Adım 1: Bir Okta uygulaması oluşturun {#okta-step-1}

1. Okta yönetici panonuzda **Uygulamalar > Uygulamalar > Uygulama Entegrasyonu Oluştur** yolunu izleyin.
2. **OpenID Connect** ve **Web Uygulaması** seçeneklerini belirleyin.
3. Uygulama adını girin, örneğin `Tuist`. İsteğe bağlı olarak [Tuist logosunu](https://tuist.dev/images/tuist_dashboard.png) yükleyin.
4. **Oturum açma yönlendirme URI'sini**, Kimlik Doğrulama ayarları sayfasında gösterilen değerle eşleşecek şekilde ayarlayın, örneğin `https://tuist.dev/users/auth/okta/callback`.
5. **Atamalar** altında istenen erişim kontrolünü seçin ve kaydedin.
6. Uygulamanın genel ayarlarından **İstemci Kimliğini** ve **İstemci Sırrını** kopyalayın. **Okta alanınızı** not edin, örneğin `your-company.okta.com`.
7. İsteğe bağlı olarak, Okta panosundan oturum açmaya izin vermek için Genel Ayarlar'da **Düzenle** düğmesine tıklayın, **Oturum açmayı başlatan** seçeneğini **Okta veya Uygulama** olarak değiştirin, **Kullanıcılara uygulama simgesini göster** seçeneğini işaretleyin ve **Oturum açma başlatma URI'sini** Kimlik Doğrulama ayarları sayfasında gösterilen değere ayarlayın.

### Adım 2: Tuist'i yapılandırın {#okta-step-2}

1. Kuruluşunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. Tek oturum açmayı etkinleştirin.
3. Sağlayıcı olarak **Okta** seçeneğini belirleyin.
4. **Okta alanını**, **İstemci Kimliğini** ve **İstemci Sırrını** girin.
5. Çalışan e-posta alanını **Giriş e-posta alanı** altına girin. Örneğin, `your-company.okta.com` Okta alanının giriş e-posta alanı `example.com` olabilir.
6. **Değişiklikleri kaydet** düğmesine tıklayın.
7. Tuist tarafından gösterilen metin kaydını giriş e-posta alanına ekleyin, ardından **Alanı doğrula** düğmesine tıklayın.
8. Kullanıcıların davete ihtiyacı olup olmadığını veya otomatik kayıt yapabileceklerini seçin, ardından yapılandırmayı tekrar kaydedin.
9. İsteğe bağlı olarak, oturum açma akışını test ettikten sonra **Tek oturum açmayı zorla** seçeneğini etkinleştirin.

### Adım 3: Kullanıcıları Okta uygulamasına atayın {#okta-step-3}

Okta uygulaması üzerinden kimlik doğrulamasına izin verilmesi gereken kullanıcıları veya grupları atayın.

Atama, oturum açma akışına erişim sağlar ancak kuruluş üyeliği yine de kayıt politikasına tabidir. Aynı kullanıcılar Sistemler Arası Kimlik Yönetimi ile sağlanıyorsa, Tuist Okta kimliğini kullanıcının ilk kez oturum açtığında SCIM'in oluşturduğu hesaba bağlar. SCIM eklenmeden önce hesabı mevcut olan bir üye, e-posta adresi doğrulanmış giriş e-posta alanında olduğunda veya oturum açmış hesabından bağlantıyı onayladıktan sonra bağlanır.

## Microsoft Entra ID {#microsoft-entra-id}

Microsoft Entra ID, üyeleri [OpenID Connect](https://openid.net/developers/how-connect-works/) üzerinden doğrular. Tuist yetkilendirme, token ve kullanıcı bilgisi uç noktalarını dizin (kiracı) tanımlayıcınızdan türetir; bu nedenle yalnızca bu değeri uygulama kimlik bilgileriyle birlikte girmeniz gerekir.

Entra ID'nin üyeleri otomatik olarak oluşturmasını, güncellemesini veya sağlama dışı bırakmasını da istiyorsanız, tek oturum açma çalıştıktan sonra <.localized_link href="/guides/integrations/authentication/scim#microsoft-entra-id">Microsoft Entra ID Sistemler Arası Kimlik Yönetimi sağlamasını</.localized_link> yapılandırın.

### Adım 1: Bir Entra uygulaması kaydedin {#entra-step-1}

1. [Microsoft Entra yönetici merkezinde](https://entra.microsoft.com), **Kimlik > Uygulamalar > Uygulama kayıtları > Yeni kayıt** yolunu izleyin.
2. Uygulama adını girin, örneğin `Tuist`.
3. **Yönlendirme URI'si** altında **Web** platformunu seçin ve Kimlik Doğrulama ayarları sayfasında gösterilen değeri girin, örneğin `https://tuist.dev/users/auth/oauth2/callback`.
4. Uygulamayı kaydedin, ardından genel bakış sayfasından **Dizin (kiracı) Kimliğini** ve **Uygulama (istemci) Kimliğini** kopyalayın.
5. **Sertifikalar ve sırlar > Yeni istemci sırrı** bölümüne gidin, bir sır oluşturun ve **Değerini** kopyalayın. Microsoft değeri yalnızca bir kez gösterir ve her istemci sırrının bir son kullanma tarihi vardır; bu nedenle ne zaman yenilenmesi gerektiğini not edin.
6. **API izinleri** bölümüne gidin ve temsilci Microsoft Graph izinlerinin `openid`, `profile` ve `email` verildiğini onaylayın.
7. İsteğe bağlı olarak, üyelerin oturum açma akışını My Apps portalından başlatmasına izin vermek için **Markalama ve özellikler** altındaki **Ana sayfa URL'sini** Kimlik Doğrulama ayarları sayfasında gösterilen değere ayarlayın.

### Adım 2: Tuist'i yapılandırın {#entra-step-2}

1. Kuruluşunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. Tek oturum açmayı etkinleştirin.
3. Sağlayıcı olarak **Microsoft Entra ID** seçeneğini belirleyin.
4. **Dizin (kiracı) Kimliğini**, **İstemci Kimliğini** ve **İstemci Sırrını** girin.
5. Çalışan e-posta alanını **Giriş e-posta alanı** altına girin. Örneğin, kullanıcılarının `first.last@example.com` olarak oturum açtığı bir dizinin giriş e-posta alanı `example.com` olur.
6. **Değişiklikleri kaydet** düğmesine tıklayın.
7. Tuist tarafından gösterilen metin kaydını giriş e-posta alanına ekleyin, ardından **Alanı doğrula** düğmesine tıklayın.
8. Kullanıcıların davete ihtiyacı olup olmadığını veya otomatik kayıt yapabileceklerini seçin, ardından yapılandırmayı tekrar kaydedin.
9. İsteğe bağlı olarak, oturum açma akışını test ettikten sonra **Tek oturum açmayı zorla** seçeneğini etkinleştirin.

### Adım 3: Kullanıcıları Entra uygulamasına atayın {#entra-step-3}

Kimlik doğrulamasına izin verilecek kullanıcıları veya grupları atayın. Uygulama atama gerektirecek şekilde yapılandırılmışsa, yalnızca atanmış kullanıcılar oturum açabilir.

Atama, oturum açma akışına erişim sağlar ancak kuruluş üyeliği hâlâ kayıt politikasına tabidir. Aynı kullanıcılar Alanlar Arası Kimlik Yönetimi Sistemi (SCIM) aracılığıyla sağlanıyorsa, Tuist Entra kimliğini kullanıcının ilk kez oturum açtığında SCIM tarafından oluşturulan hesaba bağlar. SCIM eklemeden önce hesabı bulunan bir üye, e-posta adresi doğrulanmış giriş e-posta alanında yer aldığında veya oturum açmış hesabından bağlantıyı onayladığında bağlanır.

### E-posta talebi için gereksinimler {#entra-email-claim}

Tuist, kimliği doğrulanmış kullanıcının profilini Microsoft Graph kullanıcı bilgileri uç noktasından okur; bu uç nokta yalnızca kullanıcının mevcut bir e-posta adresi varsa döndürür. `mail` özniteliği boş olan bir dizin kullanıcısı oturum açamaz çünkü Tuist'in giriş e-posta alanıyla eşleştirebileceği bir adresi yoktur.

Tek oturum açmayı yaygınlaştırmadan önce atadığınız üyelerin dizinde bir e-posta adresine sahip olduğunu onaylayın. Posta kutusu olmayan yerel Active Directory'den senkronize edilen kullanıcılar, bu özniteliğin eksik olduğu en yaygın durumdur.

### Koşullu Erişim ve çok faktörlü kimlik doğrulama {#entra-conditional-access}

Koşullu Erişim ilkeleri, çok faktörlü kimlik doğrulama ve oturum açma riski ilkeleri, yetkilendirme isteği sırasında değerlendirildikleri için Tuist uygulamasına diğer tüm Entra uygulamalarına uygulandığı şekilde uygulanır. Ekstra bir Tuist yapılandırması gerekmez.

## Özel OAuth 2.0 sağlayıcısı {#custom-oauth-2-provider}

Özel bir OAuth 2.0 sağlayıcısı, bir kuruluşun Google Workspace veya Okta dışındaki bir kimlik hizmetini kullanmasına olanak tanır. Sağlayıcının kullanıcı bilgileri uç noktası kararlı bir kullanıcı tanımlayıcısı ve bir e-posta adresi döndürmelidir.

1. Sağlayıcıda bir OAuth 2.0 web uygulaması oluşturun.
2. **Oturum açma yönlendirme URI'sini** ve isteğe bağlı **Oturum açmayı başlatma URI'sini** Tuist'in Kimlik Doğrulama ayarlarında gösterilen değerlere ayarlayın.
3. Tuist'te tek oturum açmayı etkinleştirin ve **OAuth2** seçeneğini belirleyin.
4. Sağlayıcı URL'sini, yetkilendirme uç noktasını, jeton uç noktasını, kullanıcı bilgileri uç noktasını, istemci tanımlayıcısını ve istemci sırrını girin.
5. **Giriş e-posta alanını** girin ve kaydedin. Bu, çalışan e-posta alanıdır, sağlayıcı URL'si değildir.
6. Tuist tarafından gösterilen metin kaydını giriş e-posta alanına ekleyin, ardından **Alanı doğrula** düğmesine tıklayın.
7. Yalnızca davetli veya otomatik kayıt seçeneklerinden birini seçin ve yapılandırmayı kaydedin.
8. İsteğe bağlı olarak **Tek oturum açmayı zorla** seçeneğini etkinleştirmeden önce oturum açmayı test edin.

Sağlayıcı URL'si, kimlikleri veren sağlayıcıya göre sınırlar. Doğrulanmış giriş e-posta alanı, Tuist'in kullanıcıları bağlarken veya kaydederken hangi e-posta adreslerine güvenebileceğini belirler.

## Komut satırı yapılandırması {#command-line-configuration}

Komut satırı arayüzü Google Workspace veya Okta'yı yapılandırabilir ve bir kayıt politikası seçebilir. Örneğin:

```bash
tuist organization update sso example \
  --provider okta \
  --organization-id your-company.okta.com \
  --enrollment-policy invitation-only
```

Microsoft Entra ID ve özel sağlayıcılar, komut satırı yerine kuruluşun Kimlik Doğrulama ayarlarından yapılandırılır.

`--organization-id` değeri, sağlayıcı kuruluşunu tanımlar. Bu, giriş e-posta alanı değildir. Yeni Okta kullanıcılarını kaydetmeden önce giriş e-posta alanını kuruluşun Kimlik Doğrulama ayarlarından ekleyin ve doğrulayın.

## Sorun giderme {#troubleshooting}

### Mevcut üyeler oturum açabiliyor ancak yeni kullanıcılar açamıyor {#existing-members-can-sign-in-but-new-users-cannot}

Okta ve özel sağlayıcı yapılandırmaları için giriş e-posta alanının doğrulandığını onaylayın. Ardından kullanıcıyı davet edin veya otomatik kaydı etkinleştirin.

### Tek oturum açma önce oturum açmanızı istiyor {#single-sign-on-asks-you-to-log-in-first}

Tuist hesabınızın e-posta adresi kuruluşun doğrulanmış giriş e-posta alanında değil veya alan henüz doğrulanmamış; bu nedenle Tuist sağlayıcı kimliğini otomatik olarak bağlamaz. Her zamanki oturum açma yönteminizle giriş yapın ve <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">Mevcut bir Tuist hesabını bağlama</.localized_link> bölümünde açıklandığı gibi bağlantıyı onaylayın.
### Tuist bir e-posta adresi için kuruluş bulamıyor {#tuist-cannot-find-an-organization-for-an-email-address}

Kullanıcının beklenen çalışan e-posta adresini girdiğini ve alan adının doğrulanmış giriş e-posta alanıyla tam olarak eşleştiğini onaylayın. Mevcut üyeler ayrıca mevcut kuruluş üyelikleri üzerinden de keşfedilebilir.

### Alan doğrulaması hâlâ beklemede {#domain-verification-remains-pending}

Metin kaydı adının ve değerinin Tuist'te gösterilen değerlerle tam olarak eşleştiğini onaylayın. Alan Adı Sistemi değişikliklerinin yayılması zaman alabilir; bu nedenle kayıt herkese açık hale geldikten sonra doğrulamayı yeniden deneyin.

### Sağlayıcı değiştirildikten sonra oturum açma durdu {#sign-in-stopped-after-changing-the-provider}

Yeni sağlayıcı yapılandırmasını onaylayın, giriş e-posta alanını doğrulayın ve zorlamayı etkinleştirmeden önce oturum açma akışını test edin.
