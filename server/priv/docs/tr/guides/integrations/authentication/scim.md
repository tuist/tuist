---
{
  "title": "SCIM sağlama",
  "titleTemplate": ":title | Kimlik Doğrulama | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Okta veya Microsoft Entra ID ile SCIM sağlamayı nasıl yapılandıracağınızı öğrenin."
}
---
# SCIM sağlama {#scim-provisioning}

Tuist, bir kimlik sağlayıcının organizasyon üyelerini otomatik olarak oluşturabilmesi, güncelleyebilmesi ve sağlama işlemini iptal edebilmesi için SCIM 2.0 sağlamayı destekler.

SCIM, organizasyon ayarlarınızdaki **Kimlik Doğrulama** sekmesinden yapılandırılır. SCIM belirteci, SCIM erişimi kapsamına sahip organizasyona ait bir hesap belirtecidir ve oluşturulduğunda yalnızca bir kez gösterilir.

> [!NOTE]
> SCIM üyeliği ve yaşam döngüsünü kontrol eder. <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> özelliğinin yerine geçmez. Sağlanan kullanıcıların kimlik sağlayıcınız üzerinden de oturum açması gerekiyorsa SSO'yu ayrı olarak yapılandırın.

Sağlanan kullanıcılar zaten organizasyon üyesidir. Aynı e-posta adresiyle oturum açtıklarında, bu üyelik sağlayıcı kimliklerinin bağlanması için güven oluşturabilir. <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">doğrulanmış oturum açma e-posta alanı</.localized_link> ve <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">kayıt politikası</.localized_link>, henüz sağlanmamış veya organizasyona eklenmemiş kullanıcıları kontrol eder.

## Okta {#okta}

Okta, Tuist için iki ayrı uygulama kullanır:

- Tuist'te oturum açmak için bir **OIDC Web Uygulaması**.
- Kullanıcıları ve grupları Tuist'e sağlamak için bir **SCIM 2.0 Test Uygulaması (Üst Bilgi Kimlik Doğrulaması)** uygulaması.

Kullanıcıların Okta ile oturum açması gerekiyorsa önce <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> özelliğini yapılandırın, ardından aşağıdaki adımları izleyerek SCIM sağlamayı yapılandırın.

### Adım 1: Bir Tuist SCIM belirteci oluşturun {#okta-step-1}

1. Tuist'te organizasyonunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. **SCIM sağlama** bölümünde, **SCIM uç noktası URL'sini** kopyalayın. `/scim/v2` ile bitmelidir.
3. **Belirteç oluştur** seçeneğine tıklayın.
4. Belirtece bir ad verin (örneğin, `Okta`).
5. Oluşturulan belirteci kopyalayın. Tuist belirteci yalnızca bir kez gösterir.

### Adım 2: Okta SCIM uygulamasını ekleyin {#okta-step-2}

1. Okta yönetici panonuzda **Uygulamalar > Uygulamalar > Uygulama Kataloğuna Göz At** yolunu izleyin.
2. **SCIM 2.0 Test Uygulaması (Üst Bilgi Kimlik Doğrulaması)** öğesini arayın ve ekleyin.
3. Tanınabilir bir ad verin, örneğin `Tuist SCIM`.
4. SCIM test uygulaması için oturum açma ayarlarını tamamlayın. Tuist bu uygulamayı oturum açma için kullanmaz; oturum açma, SSO kılavuzundaki OIDC uygulaması tarafından handledir.

### Adım 3: API entegrasyonunu yapılandırın {#okta-step-3}

1. SCIM uygulamasının **Sağlama** sekmesini açın.
2. **Ayarlar > Entegrasyon** altında, **API Entegrasyonunu Yapılandır** veya **Düzenle** seçeneğine tıklayın.
3. **API entegrasyonunu etkinleştir** seçeneğini işaretleyin.
4. Tuist **SCIM uç noktası URL'sini** Okta'nın **Temel URL** alanına yapıştırın.
5. Tuist SCIM belirtecini, başında `Bearer ` olacak şekilde **API Belirteci** alanına yapıştırın. Örneğin, `Bearer tuist_scim_...`. Okta bu alanı `Authorization` üst bilgisi olarak gönderir ve Tuist bir bearer belirteci bekler.
6. Okta'nın Tuist'in SCIM gruplarını okumasını istiyorsanız **Grupları İçe Aktar** seçeneğini etkinleştirin.
7. **API Kimlik Bilgilerini Test Et** seçeneğine tıklayın. Okta, entegrasyonun başarıyla doğrulandığını bildirmelidir.
8. **Kaydet** seçeneğine tıklayın.

### Adım 4: Sağlama eylemlerini etkinleştirin {#okta-step-4}

1. SCIM uygulamasının **Sağlama** sekmesinde, **Ayarlar > Uygulamaya** seçeneğini açın.
2. **Düzenle** seçeneğine tıklayın.
3. Etkinleştirin:
   - **Kullanıcı Oluştur**
   - **Kullanıcı Özelliklerini Güncelle**
   - **Kullanıcıları Devre Dışı Bırak**
4. **Kaydet** seçeneğine tıklayın.

### Adım 5: Kullanıcıları veya grupları atayın {#okta-step-5}

1. SCIM uygulamasının **Atamalar** sekmesini açın.
2. Tuist'e sağlanması gereken kullanıcıları veya grupları atayın.
3. Kullanıcıların SSO ile de oturum açabilmesi gerekiyorsa, aynı kullanıcıları veya grupları Okta OIDC uygulamasına da atayın.
4. Atanan kullanıcıların organizasyonda göründüğünü doğrulamak için Tuist'in **Üyeler** sekmesini kontrol edin.

Sağlama iptalini test etmek için Okta'da bir kullanıcının atamasını kaldırın veya onu devre dışı bırakın ve Tuist organizasyonunun **Üyeler** sekmesinden kaybolduğunu doğrulayın.

### Rolleri atama {#okta-assigning-roles}

Tuist'te üç <.localized_link href="/guides/server/accounts-and-projects#roles">rol</.localized_link> bulunur: `admin`, `user` ve `viewer`. Tuist, her rol için bir SCIM grubu sunar: `Tuist Admins`, `Tuist Users` ve `Tuist Viewers`. Okta gruplarını bunlarla **Grup İtme** özelliğini kullanarak eşleştirin:

1. Atamak istediğiniz her rol için bir Okta grubu seçin veya oluşturun ve bu grupları SCIM uygulamasının **Atamalar** sekmesinde atayın.
2. API entegrasyonunda **Grupları İçe Aktar** seçeneğinin etkin olduğundan emin olun, ardından Okta'nın Tuist gruplarını tanıması için SCIM uygulamasının **İçe Aktar** sekmesini açın ve **Şimdi İçe Aktar** seçeneğine tıklayın.
3. SCIM uygulamasının **Grupları İt** sekmesini açın ve **Grupları İt > Grupları ada göre bul** seçeneğine tıklayın.
4. Bir Okta grubu seçin, itme eylemi olarak **Grubu Bağla** seçeneğini belirleyin ve eşleşen Tuist grubunu seçin. Tuist, SCIM aracılığıyla grup oluşturmayı desteklemez; bu nedenle yeni bir grup oluşturmak yerine mevcut bir gruba bağlantı kurun.
5. **Kaydet** seçeneğine tıklayın ve kalan roller için işlemi tekrarlayın.

Bir kullanıcıyı bağlı bir gruba eklemek, ona o rolü verir. Kullanıcıyı gruptan kaldırmak, onu organizasyonun tek oturum açma üyelerini kaydettiği role geri döndürür; bu rol, bir yönetici **Ayarlar > Kimlik Doğrulama** altında değiştirmedikçe `user` olur. Herhangi bir bağlı grupta olmayan kullanıcılar da bu rolü alır. Bir kullanıcıyı gruptan kaldırmak, onu organizasyondan silmez; bunu yapmak için Okta'da kullanıcının atamasını kaldırın veya onu devre dışı bırakın.

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID, Tuist'i galeri dışı bir kurumsal uygulama aracılığıyla sağlar. Kullanıcıların Entra ID ile de oturum açması gerekiyorsa öncelikle <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link> yapılandırmasını yapın.

Tek oturum açma için kaydettiğiniz uygulama ile sağlama için kullandığınız kurumsal uygulama aynı olabilir. Sağlama, kurumsal uygulama girişi üzerinde yapılandırılır.

### Adım 1: Bir Tuist SCIM belirteci oluşturun {#entra-step-1}

1. Tuist'te, organizasyonunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. **SCIM sağlama** bölümünde, **SCIM uç noktası URL'sini** kopyalayın. `/scim/v2` ile bitmelidir.
3. **Belirteç oluştur** seçeneğine tıklayın.
4. Belirtece bir ad verin (örneğin, `Entra ID`).
5. Oluşturulan belirteci kopyalayın. Tuist belirteci yalnızca bir kez gösterir.

### Adım 2: Sağlamayı yapılandırın {#entra-step-2}

1. Microsoft Entra yönetim merkezinde **Kimlik > Uygulamalar > Kurumsal uygulamalar** yolunu izleyin ve Tuist uygulamasını açın.
2. **Sağlama** seçeneğini açın ve **Sağlama Modu** değerini **Otomatik** olarak ayarlayın.
3. **Kiracı URL'si** değerini Tuist SCIM uç noktası URL'sine ayarlayın.
4. **Gizli Belirteç** değerini Tuist SCIM belirtecine ayarlayın. Belirteci, başında `Bearer ` öneki olmadan tek başına girin; Entra ID şemayı kendisi ekler.
5. **Bağlantıyı Test Et** seçeneğine tıklayın. Entra ID, verilen kimlik bilgilerinin yetkili olduğunu bildirmelidir.
6. Yapılandırmayı kaydedin.

### Adım 3: Eşleştirme özelliğini ayarlayın {#entra-step-3}

1. **Eşleştirmeler** altında, **Microsoft Entra ID Kullanıcılarını Sağla** seçeneğini açın.
2. `userPrincipalName` veya `mail` öğesinin SCIM `userName` özelliğine eşlendiğini ve bu özelliğin **Eşleştirme önceliği 1** için kullanıldığını doğrulayın.
3. Varsa, `externalId` öğesini eşleştirme özelliklerinden kaldırın.

Tuist, sağlanan kullanıcıları `userName` üzerinden eşleştirir. Entra ID'nin `externalId` olarak gönderdiği dizin nesne tanımlayıcısını saklamaz; bu nedenle, bu özellik üzerindeki bir filtre mevcut bir üyeyi bulamaz ve sağlama döngüleri öngörülemeyen şekilde davranabilir.

### Adım 4: Grup sağlamayı devre dışı bırakın {#entra-step-4}

**Eşleştirmeler** altında, **Microsoft Entra ID Gruplarını Sağla** seçeneğini devre dışı bırakın.

Tuist'in SCIM grupları, oluşturabileceğiniz dizin grupları yerine organizasyon rolü başına sabit bir gruptur; bu nedenle bir dizin grubunu sağlama girişimi başarısız olur. Bunun yerine aşağıda açıklandığı gibi rolleri atayın.

### Adım 5: Kullanıcıları atayın ve sağlamayı başlatın {#entra-step-5}

1. Uygulamanın **Kullanıcılar ve gruplar** sekmesini açın ve Tuist'e sağlanması gereken kullanıcıları veya grupları atayın.
2. **Sağlama** seçeneğine dönün ve başlatın.
3. Atanan kullanıcıların organizasyonda göründüğünü doğrulamak için Tuist'in **Üyeler** sekmesini kontrol edin.

Entra ID kendi zamanlamasına göre sağlar; bu genellikle her 40 dakikada bir olur, bu nedenle üyeler anında görünmez. Tek bir kullanıcıyı hemen test etmek için **Talep üzerine sağla** seçeneğini kullanın.

Sağlama iptalini test etmek için Entra ID'de bir kullanıcının atamasını kaldırın veya hesabını devre dışı bırakın ve Tuist organizasyonunun **Üyeler** sekmesinden kaybolduklarını doğrulayın.

Daha sonra sağlama kapsamını değiştirirseniz, örneğin **Tüm kullanıcıları ve grupları eşitle** seçeneğinden **Yalnızca atanmış kullanıcıları ve grupları eşitle** seçeneğine geçerseniz, ardından **Sağlamayı yeniden başlat** seçeneğine tıklayın. Entra ID, artık kapsamda olmayan kullanıcıların sağlama işlemini iptal etme dahil olmak üzere yeni kapsamı yalnızca yeniden başlatmadan sonra uygular.

### Rolleri atama {#entra-assigning-administrators}

Tuist'te üç <.localized_link href="/guides/server/accounts-and-projects#roles">rol</.localized_link> bulunur: `admin`, `user` ve `viewer`. Bunları Entra ID üzerinden ayarlamak için:

1. **Uygulama kayıtları** bölümünde Tuist uygulamasını açın ve atamak istediğiniz her Tuist rolü için bir uygulama rolü ekleyin. **İzin verilen üye türleri** değerini **Kullanıcılar/Gruplar** olarak, **Değer** alanını ise `admin`, `user` veya `viewer` olarak ayarlayın.
2. Kurumsal uygulamanın **Kullanıcılar ve gruplar** sekmesinde, her kullanıcıya veya gruba bu uygulama rollerinden birini atayın. Bir kullanıcı birden fazla uygulama rolüne sahip olabilir. Tuist en yetkili olanı uygular; burada `admin`, `user` üzerindedir ve `user`, `viewer` üzerindedir, bu nedenle farklı rollere eşlenmiş gruplara ait olan bir kullanıcı en yüksek yetkiye sahip olanı alır.
3. **Sağlama > Eşleştirmeler** altında, **Gelişmiş Seçenekler** açılır menüsünü açın ve **Hedef Kullanıcı özelliklerini düzenle** seçeneğini belirleyin. Adı `roles` olan bir özellik ekleyin; **Tür** değerini `String` olarak ayarlayın ve **Çoklu Değer** kutusunu işaretleyin.
4. **Sağlama > Eşleştirmeler > Microsoft Entra ID Kullanıcılarını Sağla** altında **Yeni Eşleştirme Ekle** seçeneğine tıklayın. **Eşleştirme türü** değerini **İfade** olarak, **İfade** değerini `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])` olarak ve **Hedef özellik** değerini eklediğiniz `roles` özelliği olarak ayarlayın.
5. Sağlama kapsamını **Yalnızca atanmış kullanıcıları ve grupları eşitle** olarak bırakın. `AssertiveAppRoleAssignmentsComplex`, **Tüm kullanıcıları ve grupları eşitle** ile uyumlu değildir.

`AssertiveAppRoleAssignmentsComplex`, bir kullanıcının sahip olduğu her uygulama rolünü gönderir ve kaldırmaları da iletir; bu nedenle Entra ID'de bir rolün kaldırılması, kullanıcının hala sahip olduğu en yetkili role düşmesine neden olur. `roles[primary eq "True"].value` öğesine eşlenen `SingleAppRoleAssignment([appRoleAssignments])` de çalışır, ancak yalnızca tek bir rol gönderir ve Entra ID, bir kullanıcı birden fazla role sahip olduğunda hangisini seçeceği konusunda garanti vermez.

Entra ID'de bir kullanıcının uygulama rollerini değiştirmek, bir sonraki sağlama döngüsünde Tuist rolünü günceller. Bir uygulama rolü olmadan veya `admin`, `user` ya da `viewer` dışındaki değerlerle sağlanan bir kullanıcı, organizasyonun tek oturum açma üyelerini kaydettiği rolü alır; bu, bir yönetici **Ayarlar > Kimlik Doğrulama** altında değiştirmediyse `user` rolüdür.

## Yaşam döngüsü davranışı {#lifecycle-behavior}

Kimlik sağlayıcınız bir kullanıcıyı sağlama uygulamasına atadığında, Tuist e-posta adresi zaten bilinmiyorsa kullanıcıyı oluşturur ve ardından organizasyona ekler. E-posta adresi zaten organizasyon dışındaki mevcut bir Tuist kullanıcısına aitse, Tuist o kullanıcıyı ekler ve bunu kendisine e-posta ile bildirir; ancak hesap başka bir organizasyonun SCIM entegrasyonu tarafından oluşturulmadıysa. Bu durumda Tuist, isteği `409` koduyla reddeder, böylece bir kimlik sağlayıcı başka bir organizasyonun yönettiği bir hesabı talep edemez.

Kimlik sağlayıcınız, yalnızca organizasyonunuz hesabı bağımsız olarak yönetirken bir kullanıcının e-posta adresini (`userName`) değiştirebilir. Bu, Tuist'in hesabı SCIM entegrasyonunuz aracılığıyla oluşturduğu ve o tarihten itibaren kullanıcının bir parola ayarlamadığı, organizasyonunuzun tek oturum açma sistemi dışındaki bir sağlayıcıyla giriş yapmadığı, bir ajan kaydı talep etmediği veya başka bir organizasyona katılmadığı anlamına gelir. Diğer tüm kullanıcılar için Tuist, değişikliği `400` kodu ve `mutability` SCIM hata türü ile reddeder. Yine de aynı istekte gönderilen bir devre dışı bırakmayı uygular. Tuist ayrıca, başka bir organizasyonun doğruladığı bir giriş alan adına veya tuist.dev üzerinde Tuist'in kendi alan adına kullanıcı oluşturmayı veya kullanıcıları bu alan adına yeniden adlandırmayı reddeder. Yeniden adlandırma, kullanıcının eski adresin kontrolünü kanıtladığı kaydı temizler.

Kimlik sağlayıcınız kullanıcının atamasını kaldırdığında veya hesabını devre dışı bıraktığında, Tuist kullanıcı kaydını ve sahip oldukları işleri koruyarak organizasyon rolünü kaldırır. Sağlama iptali, kullanıcıyı genel olarak devre dışı bırakmaz çünkü aynı Tuist kullanıcısı diğer organizasyonlara da ait olabilir.

Tuist üç sentetik SCIM grubunu sunar: `Tuist Admins`, `Tuist Users` ve `Tuist Viewers`. Bir gruba üye eklemek, onların organizasyon rolünü ayarlar. Mevcut rolleriyle eşleşen gruptan bir üyeyi çıkarmak, onları kayıt rolüne geri taşır ve üyelik yalnızca kullanıcının ataması kaldırıldığında veya hesabı devre dışı bırakıldığında sona erer. Kimlik sağlayıcıları, rolü bir kullanıcıdaki SCIM `roles` özelliği aracılığıyla da ayarlayabilir; değer olarak `admin`, `user` veya `viewer` kullanılabilir. Birden fazla değer gönderen bir kimlik sağlayıcı, bunların en yetkili olanını alır; burada `admin`, `user` üzerindedir ve `user`, `viewer` üzerindedir.

## Desteklenen SCIM özellikleri {#supported-scim-features}

Tuist, kimlik sağlayıcılarının yaşam döngüsü yönetimi için ihtiyaç duyduğu SCIM 2.0 uç noktalarını destekler:

- `/Users` için `POST`, `GET`, `PUT`, `PATCH` ve `DELETE`.
- `/Groups` için `GET` ve `PATCH`.
- `/ServiceProviderConfig`, `/ResourceTypes` ve `/Schemas` için SCIM keşif uç noktaları.
