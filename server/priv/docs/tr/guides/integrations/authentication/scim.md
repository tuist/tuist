---
{
  "title": "SCIM sağlama",
  "titleTemplate": ":title | Kimlik Doğrulama | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Okta veya Microsoft Entra ID ile SCIM sağlamayı nasıl yapılandıracağınızı öğrenin."
}
---
# SCIM sağlama {#scim-provisioning}

Tuist, bir kimlik sağlayıcının kuruluş üyelerini otomatik olarak oluşturabilmesi, güncelleyebilmesi ve sağlayabileceği SCIM 2.0 sağlamayı destekler.

SCIM, kuruluş ayarlarınızdaki **Kimlik Doğrulama** sekmesinden yapılandırılır. SCIM belirteci, SCIM erişimi kapsamına sahip kuruluşa ait bir hesap belirtecdir ve oluşturulduğunda yalnızca bir kez gösterilir.

> [!NOTE]
> SCIM üyelik ve yaşam döngüsünü kontrol eder. <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> özelliğinin yerine geçmez. Sağlanan kullanıcıların kimlik sağlayıcınız üzerinden de oturum açması gerekiyorsa SSO'yu ayrı olarak yapılandırın.

Sağlanan kullanıcılar zaten kuruluş üyesidir. Aynı e-posta adresiyle oturum açtıklarında, bu üyelik sağlayıcı kimliklerinin bağlanması için güven tesis edebilir. <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">doğrulanmış oturum açma e-posta alanı</.localized_link> ve <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">kayıt politikası</.localized_link>, henüz sağlanmamış veya kuruluşa eklenmemiş kullanıcıları kontrol eder.

## Okta {#okta}

Okta, Tuist için iki ayrı uygulama kullanır:

- Tuist'te oturum açmak için bir **OIDC Web Uygulaması**.
- Kullanıcıları ve grupları Tuist'e sağlamak için bir **SCIM 2.0 Test Uygulaması (Üst Bilgi Kimlik Doğrulaması)** uygulaması.

Kullanıcıların Okta ile oturum açması gerekiyorsa önce <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> özelliğini yapılandırın, ardından aşağıdaki adımlarla SCIM sağlamayı yapılandırın.

### Adım 1: Bir Tuist SCIM belirteci oluşturun {#okta-step-1}

1. Tuist'te kuruluşunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. **SCIM sağlama** bölümünde, **SCIM uç noktası URL'sini** kopyalayın. `/scim/v2` ile bitmelidir.
3. **Belirteç oluştur** seçeneğine tıklayın.
4. Belirtece bir ad verin (örneğin, `Okta`).
5. Oluşturulan belirteci kopyalayın. Tuist belirteci yalnızca bir kez gösterir.

### Adım 2: Okta SCIM uygulamasını ekleyin {#okta-step-2}

1. Okta yönetici panosunda **Uygulamalar > Uygulamalar > Uygulama Kataloğuna Göz At** seçeneğine gidin.
2. **SCIM 2.0 Test Uygulaması (Üst Bilgi Kimlik Doğrulaması)** öğesini arayın ve ekleyin.
3. Tanınabilir bir ad verin, örneğin `Tuist SCIM`.
4. SCIM test uygulaması için oturum açma ayarlarını tamamlayın. Tuist bu uygulamayı oturum açmak için kullanmaz; oturum açma işlemi SSO kılavuzundaki OIDC uygulaması tarafından gerçekleştirilir.

### Adım 3: API entegrasyonunu yapılandırın {#okta-step-3}

1. SCIM uygulamasının **Sağlama** sekmesini açın.
2. **Ayarlar > Entegrasyon** altında, **API Entegrasyonunu Yapılandır** veya **Düzenle** seçeneğine tıklayın.
3. **API entegrasyonunu etkinleştir** seçeneğini işaretleyin.
4. Tuist **SCIM uç noktası URL'sini** Okta'nın **Temel URL** alanına yapıştırın.
5. Tuist SCIM belirtecini, `Bearer ` ön ekiyle birlikte **API Belirteci** alanına yapıştırın. Örneğin, `Bearer tuist_scim_...`. Okta bu alanı `Authorization` üst bilgisi olarak gönderir ve Tuist bir bearer belirteci bekler.
6. Okta'nın Tuist'in SCIM gruplarını okumasını istiyorsanız **Grupları İçe Aktar** seçeneğini etkinleştirin.
7. **API Kimlik Bilgilerini Test Et** seçeneğine tıklayın. Okta, entegrasyonun başarıyla doğrulandığını bildirmelidir.
8. **Kaydet** seçeneğine tıklayın.

### Adım 4: Sağlama eylemlerini etkinleştirin {#okta-step-4}

1. SCIM uygulamasının **Sağlama** sekmesinde, **Ayarlar > Uygulamaya** seçeneğini açın.
2. **Düzenle** seçeneğine tıklayın.
3. Etkinleştirin:
   - **Kullanıcı Oluştur**
   - **Kullanıcı Özniteliklerini Güncelle**
   - **Kullanıcıları Devre Dışı Bırak**
4. **Kaydet** seçeneğine tıklayın.

### Adım 5: Kullanıcıları veya grupları atayın {#okta-step-5}

1. SCIM uygulamasının **Atamalar** sekmesini açın.
2. Tuist'e sağlanması gereken kullanıcıları veya grupları atayın.
3. Kullanıcıların SSO ile de oturum açabilmesi gerekiyorsa, aynı kullanıcıları veya grupları Okta OIDC uygulamasına atayın.
4. Atanan kullanıcıların organizasyonda göründüğünü doğrulamak için Tuist'in **Üyeler** sekmesini kontrol edin.

Sağlama iptalini test etmek için Okta'da bir kullanıcının atamasını kaldırın veya devre dışı bırakın ve Tuist organizasyonunun **Üyeler** sekmesinden kaybolduklarını doğrulayın.

### Rolleri atama {#okta-assigning-roles}

Tuist'te üç <.localized_link href="/guides/server/accounts-and-projects#roles">rol</.localized_link> bulunur: `admin`, `user` ve `viewer`. Tuist, her rol için bir SCIM grubu sunar: `Tuist Admins`, `Tuist Users` ve `Tuist Viewers`. Okta gruplarını **Grup İtme** ile bunlara eşleyin:

1. Atamak istediğiniz her rol için bir Okta grubu seçin veya oluşturun ve bu grupları SCIM uygulamasının **Atamalar** sekmesinde atayın.
2. API entegrasyonunda **Grupları İçe Aktar** seçeneğinin etkin olduğundan emin olun, ardından SCIM uygulamasının **İçe Aktar** sekmesini açın ve Okta'nın Tuist gruplarını tanıması için **Şimdi İçe Aktar** seçeneğine tıklayın.
3. SCIM uygulamasının **Grupları İt** sekmesini açın ve **Grupları İt > Ada göre grup bul** seçeneğine tıklayın.
4. Bir Okta grubu seçin, itme eylemi olarak **Grubu Bağla** seçeneğini belirleyin ve eşleşen Tuist grubunu seçin. Tuist, SCIM aracılığıyla grup oluşturmayı desteklemez; bu nedenle yeni bir grup oluşturmak yerine mevcut bir gruba bağlayın.
5. **Kaydet** seçeneğine tıklayın ve kalan roller için işlemi tekrarlayın.

Bir kullanıcıyı bağlantılı bir gruba eklemek, ona o rolü verir. Kullanıcıyı gruptan çıkarmak, onu organizasyonun tek oturum açma üyelerini kaydettiği role geri döndürür; bu rol, bir yönetici **Ayarlar > Kimlik Doğrulama** altında değiştirmediyse `user` olur. Herhangi bir bağlantılı grupta olmayan kullanıcılar da bu rolü alır. Bir kullanıcıyı gruptan çıkarmak, onu organizasyondan kaldırmaz; bunu yapmak için Okta'da atamasını kaldırın veya devre dışı bırakın.

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID, Tuist'i galeri dışı bir kurumsal uygulama aracılığıyla sağlar. Kullanıcıların Entra ID ile de oturum açması gerekiyorsa önce <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link> yapılandırmasını yapın.

Tek oturum açma için kaydettiğiniz uygulama ile sağlama için kullandığınız kurumsal uygulama aynı olabilir. Sağlama, kurumsal uygulama girişi üzerinde yapılandırılır.

### Adım 1: Bir Tuist SCIM belirteci oluşturun {#entra-step-1}

1. Tuist'te, organizasyonunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. **SCIM sağlama** bölümünde, **SCIM uç noktası URL'sini** kopyalayın. `/scim/v2` ile bitmelidir.
3. **Belirteç oluştur** seçeneğine tıklayın.
4. Belirtece bir ad verin (örneğin, `Entra ID`).
5. Oluşturulan belirteci kopyalayın. Tuist belirteci yalnızca bir kez gösterir.

### Adım 2: Sağlamayı yapılandırın {#entra-step-2}

1. Microsoft Entra yönetim merkezinde **Kimlik > Uygulamalar > Kurumsal uygulamalar** seçeneğine gidin ve Tuist uygulamasını açın.
2. **Sağlama** seçeneğini açın ve **Sağlama Modu** değerini **Otomatik** olarak ayarlayın.
3. **Tenant URL** değerini Tuist SCIM uç noktası URL'sine ayarlayın.
4. **Gizli Belirteç** değerini Tuist SCIM belirtecine ayarlayın. Belirteci `Bearer ` ön eki olmadan, tek başına girin; Entra ID şemayı kendisi ekler.
5. **Bağlantıyı Test Et** seçeneğine tıklayın. Entra ID, sağlanan kimlik bilgilerinin yetkili olduğunu bildirmelidir.
6. Yapılandırmayı kaydedin.

### Adım 3: Eşleştirme özniteliğini ayarlayın {#entra-step-3}

1. **Eşlemeler** altında, **Microsoft Entra ID Kullanıcılarını Sağla** seçeneğini açın.
2. `userPrincipalName` veya `mail` öğesinin SCIM `userName` özniteliğine eşlendiğini ve bu özniteliğin **Eşleştirme önceliği 1** için kullanıldığını onaylayın.
3. Varsa, `externalId` öğesini eşleştirme özniteliklerinden kaldırın.

Tuist, sağlanan kullanıcıları `userName` ile eşleştirir. Entra ID'nin `externalId` olarak gönderdiği dizin nesne tanımlayıcısını saklamaz; bu nedenle, bu öznitelik üzerindeki bir filtre mevcut bir üyeyi bulamaz ve sağlama döngüleri öngörülemeyen şekilde davranabilir.

### Adım 4: Grup sağlamayı devre dışı bırakın {#entra-step-4}

**Eşlemeler** altında, **Microsoft Entra ID Gruplarını Sağla** seçeneğini devre dışı bırakın.

Tuist'in SCIM grupları, oluşturabileceğiniz dizin grupları yerine organizasyon rolü başına sabit bir gruptur; bu nedenle bir dizin grubu sağlama girişimi başarısız olur. Bunun yerine aşağıda açıklandığı gibi rolleri atayın.

### Adım 5: Kullanıcıları atayın ve sağlamayı başlatın {#entra-step-5}

1. Uygulamanın **Kullanıcılar ve gruplar** sekmesini açın ve Tuist'e sağlanması gereken kullanıcıları veya grupları atayın.
2. **Sağlama** seçeneğine dönün ve başlatın.
3. Atanan kullanıcıların organizasyonda göründüğünü doğrulamak için Tuist'in **Üyeler** sekmesini kontrol edin.

Entra ID, kendi zamanlamasına göre sağlama yapar; bu genellikle her 40 dakikada bir gerçekleşir, bu nedenle üyeler anında görünmez. Tek bir kullanıcıyı hemen test etmek için **Talep üzerine sağla** seçeneğini kullanın.

Sağlama iptalini test etmek için Entra ID'de bir kullanıcının atamasını kaldırın veya devre dışı bırakın ve Tuist organizasyonunun **Üyeler** sekmesinden kaybolduklarını doğrulayın.

Daha sonra sağlama kapsamını değiştirirseniz, örneğin **Tüm kullanıcıları ve grupları senkronize et** seçeneğinden **Yalnızca atanmış kullanıcıları ve grupları senkronize et** seçeneğine geçerseniz, ardından **Sağlamayı yeniden başlat** seçeneğine tıklayın. Entra ID, artık kapsamda olmayan kullanıcıların sağlama işlemini iptal etme dahil olmak üzere yeni kapsamı yalnızca yeniden başlatmadan sonra uygular.

### Rollerin atanması {#entra-assigning-administrators}

Tuist'te üç <.localized_link href="/guides/server/accounts-and-projects#roles">rol</.localized_link> bulunur: `admin`, `user` ve `viewer`. Bunları Entra ID üzerinden ayarlamak için:

1. **Uygulama kayıtları** bölümünde Tuist uygulamasını açın ve atamak istediğiniz her Tuist rolü için bir uygulama rolü ekleyin. **İzin verilen üye türleri** değerini **Kullanıcılar/Gruplar** olarak, **Değer** değerini ise `admin`, `user` veya `viewer` olarak ayarlayın.
2. Kurumsal uygulamanın **Kullanıcılar ve gruplar** sekmesinde, her kullanıcıya veya gruba bu uygulama rollerinden birini atayın. Bir kullanıcı birden fazla uygulama rolüne sahip olabilir. Tuist en yetkili olanı uygular; burada `admin`, `user` üzerinde ve `user`, `viewer` üzerinde önceliklidir, bu nedenle farklı rollere eşlenmiş gruplara ait olan bir kullanıcı bunların en yüksek olanını alır.
3. **Sağlama > Eşlemeler** altında, **Gelişmiş Seçenekler** açılır menüsünü açın ve **Hedef Kullanıcı özniteliklerini düzenle** seçeneğini belirleyin. **Tür** değeri `String` olarak ayarlanmış ve **Çoklu Değer** seçeneği işaretlenmiş `roles` adlı bir öznitelik ekleyin.
4. **Sağlama > Eşlemeler > Microsoft Entra ID Kullanıcılarını Sağla** altında, **Yeni Eşleme Ekle** seçeneğine tıklayın. **Eşleme türü** değerini **İfade** olarak, **İfade** değerini `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])` olarak ve **Hedef öznitelik** değerini eklediğiniz `roles` özniteliği olarak ayarlayın.
5. Sağlama kapsamını **Yalnızca atanmış kullanıcıları ve grupları senkronize et** olarak tutun. `AssertiveAppRoleAssignmentsComplex`, **Tüm kullanıcıları ve grupları senkronize et** ile uyumlu değildir.

`AssertiveAppRoleAssignmentsComplex`, bir kullanıcının sahip olduğu her uygulama rolünü gönderir ve kaldırmaları da iletir; bu nedenle Entra ID'de bir rolün alınması, kullanıcının hala sahip olduğu en yetkili role düşmesine neden olur. `roles[primary eq "True"].value` öğesine eşlenen `SingleAppRoleAssignment([appRoleAssignments])` de çalışır, ancak yalnızca tek bir rol gönderir ve Entra ID, bir kullanıcı birden fazla role sahip olduğunda hangisini seçeceğine dair garanti vermez.

Entra ID'de bir kullanıcının uygulama rollerini değiştirmek, sonraki sağlama döngüsünde Tuist rolünü günceller. Bir uygulama rolü olmadan veya `admin`, `user` ya da `viewer` dışındaki değerlerle sağlanan bir kullanıcı, organizasyonun tek oturum açma üyelerini kaydettiği rolü alır; bu, bir yönetici **Ayarlar > Kimlik Doğrulama** altında değiştirmediyse `user` rolüdür.

## Yaşam döngüsü davranışı {#lifecycle-behavior}

Kimlik sağlayıcınız bir kullanıcıyı sağlama uygulamasına atadığında, Tuist e-posta adresi zaten bilinmiyorsa kullanıcıyı oluşturur ve ardından onu organizasyona ekler. E-posta adresi zaten organizasyon dışındaki mevcut bir Tuist kullanıcısına aitse, Tuist o kullanıcıyı ekler ve durumu hakkında e-posta gönderir; ancak hesap başka bir organizasyonun SCIM entegrasyonu tarafından oluşturulduysa bu geçerli değildir. Bu durumda Tuist, isteği `409` ile reddeder, böylece kimlik sağlayıcısı başka bir organizasyonun yönettiği bir hesabı talep edemez.

Kimlik sağlayıcınız, yalnızca organizasyonunuz hesabı tek başına yönetirken bir kullanıcının e-posta adresini (`userName`) değiştirebilir. Bu, Tuist'in hesabı SCIM entegrasyonunuz aracılığıyla oluşturduğu ve o zamandan beri kullanıcının bir parola ayarlamadığı, organizasyonunuzun tek oturum açma hizmeti dışındaki bir sağlayıcıyla giriş yapmadığı, bir aracı kaydı talep etmediği veya başka bir organizasyona katılmadığı anlamına gelir. Diğer tüm kullanıcılar için Tuist, değişikliği `400` ve `mutability` SCIM hata türü ile reddeder. Yine de aynı istekte gönderilen bir devre dışı bırakmayı uygular. Tuist ayrıca, başka bir organizasyonun doğruladığı bir giriş alanına veya tuist.dev üzerinde Tuist'in kendi alan adına kullanıcı oluşturmayı veya kullanıcıları bu alan adlarına yeniden adlandırmayı reddeder. Yeniden adlandırma, kullanıcının eski adresin kontrolünü kanıtladığı kaydı temizler.

Kimlik sağlayıcınız kullanıcının atamasını kaldırdığında veya kullanıcıyı devre dışı bıraktığında, Tuist kullanıcı kaydını ve sahiplendiği tüm çalışmaları korurken organizasyon rolünü kaldırır. Sağlama iptali, aynı Tuist kullanıcısının diğer organizasyonlara ait olabilmesi nedeniyle kullanıcıyı küresel olarak devre dışı bırakmaz.

Tuist üç sentetik SCIM grubunu sunar: `Tuist Admins`, `Tuist Users` ve `Tuist Viewers`. Bir gruba üye eklemek, onların organizasyon rolünü ayarlar. Mevcut rolleriyle eşleşen gruptan bir üyeyi kaldırmak, onları kayıt rolüne geri döndürür ve üyelik yalnızca kullanıcının ataması kaldırıldığında veya devre dışı bırakıldığında sona erer. Kimlik sağlayıcıları, rolü bir kullanıcıdaki SCIM `roles` özniteliği aracılığıyla da ayarlayabilir; değer olarak `admin`, `user` veya `viewer` kullanılabilir. Birden fazla değer gönderen bir kimlik sağlayıcı için, bunların en yetkilisi uygulanır; burada `admin`, `user` üzerinde ve `user`, `viewer` üzerinde önceliklidir.

## Desteklenen SCIM özellikleri {#supported-scim-features}

Tuist, kimlik sağlayıcılarının yaşam döngüsü yönetimi için ihtiyaç duyduğu SCIM 2.0 uç noktalarını destekler:

- `/Users` için `POST`, `GET`, `PUT`, `PATCH` ve `DELETE`.
- `/Groups` için `GET` ve `PATCH`.
- `/ServiceProviderConfig`, `/ResourceTypes` ve `/Schemas` için SCIM keşif uç noktaları.
