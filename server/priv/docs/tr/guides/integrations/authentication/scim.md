---
{
  "title": "SCIM sağlama",
  "titleTemplate": ":title | Kimlik Doğrulama | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Okta veya Microsoft Entra ID ile SCIM sağlamayı nasıl yapılandıracağınızı öğrenin."
}
---
# SCIM sağlama {#scim-provisioning}

Tuist, bir kimlik sağlayıcının kuruluş üyelerini otomatik olarak oluşturabilmesi, güncelleyebilmesi ve sağlamasını iptal edebilmesi için SCIM 2.0 sağlamayı destekler.

SCIM, kuruluş ayarlarınızdaki **Kimlik Doğrulama** sekmesinden yapılandırılır. SCIM belirteci, SCIM erişimi kapsamına sahip kuruluşa ait bir hesap belirtecidir ve oluşturulduğunda yalnızca bir kez gösterilir.

> [!NOTE]
> SCIM, üyeliği ve yaşam döngüsünü kontrol eder. <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> işlevinin yerine geçmez. Sağlanan kullanıcıların kimlik sağlayıcınız üzerinden de oturum açması gerekiyorsa SSO’yu ayrı olarak yapılandırın.

Sağlanan kullanıcılar zaten kuruluş üyesidir. Aynı e-posta adresiyle oturum açtıklarında bu üyelik, sağlayıcı kimliklerinin bağlanması için güven ilişkisi kurabilir. <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">doğrulanmış oturum açma e-posta etki alanı</.localized_link> ve <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">kaydolma politikası</.localized_link>, henüz sağlanmamış veya kuruluşa eklenmemiş kullanıcıları denetler.

## Okta {#okta}

Okta, Tuist için iki ayrı uygulama kullanır:

- Tuist’e oturum açmak için bir **OIDC Web Uygulaması**.
- Kullanıcıları ve grupları Tuist’e sağlamak için bir **SCIM 2.0 Test Uygulaması (Üst Bilgi Kimlik Doğrulaması)** uygulaması.

Kullanıcıların Okta ile oturum açması gerekiyorsa önce <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> yapılandırmasını yapın, ardından aşağıdaki adımlarla SCIM sağlamayı yapılandırın.

### Adım 1: Bir Tuist SCIM belirteci oluşturun {#okta-step-1}

1. Tuist’te kuruluşunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. **SCIM sağlama** bölümünde **SCIM uç noktası URL’sini** kopyalayın. Sonu `/scim/v2` ile bitmelidir.
3. **Belirteç oluştur** seçeneğine tıklayın.
4. Belirtece bir ad verin (örneğin, `Okta`).
5. Oluşturulan belirteci kopyalayın. Tuist belirteci yalnızca bir kez gösterir.

### Adım 2: Okta SCIM uygulamasını ekleyin {#okta-step-2}

1. Okta yönetici panosunda **Uygulamalar > Uygulamalar > Uygulama Kataloğuna Göz At** yolunu izleyin.
2. **SCIM 2.0 Test Uygulaması (Üst Bilgi Kimlik Doğrulaması)** öğesini arayın ve ekleyin.
3. Tanımlanabilir bir ad verin, örneğin `Tuist SCIM`.
4. SCIM test uygulaması için oturum açma ayarlarını tamamlayın. Tuist bu uygulamayı oturum açma için kullanmaz; oturum açma işlemi SSO kılavuzundaki OIDC uygulaması tarafından gerçekleştirilir.

### Adım 3: API entegrasyonunu yapılandırın {#okta-step-3}

1. SCIM uygulamasının **Sağlama** sekmesini açın.
2. **Ayarlar > Entegrasyon** altında **API Entegrasyonunu Yapılandır** veya **Düzenle** seçeneğine tıklayın.
3. **API entegrasyonunu etkinleştir** kutusunu işaretleyin.
4. Tuist **SCIM uç noktası URL’sini** Okta’nın **Temel URL** alanına yapıştırın.
5. Tuist SCIM belirtecini, başına `Bearer ` eklenmiş şekilde **API Belirteci** alanına yapıştırın. Örneğin, `Bearer tuist_scim_...`. Okta bu alanı `Authorization` üst bilgisi olarak gönderir ve Tuist bir bearer belirteci bekler.
6. Okta’nın Tuist’in SCIM gruplarını okumasını istiyorsanız **Grupları İçe Aktar** seçeneğini etkinleştirin.
7. **API Kimlik Bilgilerini Test Et** seçeneğine tıklayın. Okta, entegrasyonun başarıyla doğrulandığını bildirmelidir.
8. **Kaydet** seçeneğine tıklayın.

### Adım 4: Sağlama eylemlerini etkinleştirin {#okta-step-4}

1. SCIM uygulamasının **Sağlama** sekmesinde **Ayarlar > Uygulamaya** bölümünü açın.
2. **Düzenle** seçeneğine tıklayın.
3. Şunları etkinleştirin:
   - **Kullanıcı Oluştur**
   - **Kullanıcı Özelliklerini Güncelle**
   - **Kullanıcıları Devre Dışı Bırak**
4. **Kaydet** seçeneğine tıklayın.

### Adım 5: Kullanıcıları veya grupları atayın {#okta-step-5}

1. SCIM uygulamasının **Atamalar** sekmesini açın.
2. Tuist’e sağlanması gereken kullanıcıları veya grupları atayın.
3. Kullanıcıların SSO ile de oturum açabilmesi gerekiyorsa, aynı kullanıcıları veya grupları Okta OIDC uygulamasına da atayın.
4. Atanan kullanıcıların organizasyonda göründüğünü doğrulamak için Tuist’in **Üyeler** sekmesini kontrol edin.

Sağlama iptalini test etmek için Okta’da bir kullanıcının atamasını kaldırın veya hesabını devre dışı bırakın ve Tuist organizasyonunun **Üyeler** sekmesinden kaybolduklarını doğrulayın.

### Rolleri atama {#okta-assigning-roles}

Tuist üç <.localized_link href="/guides/server/accounts-and-projects#roles">role</.localized_link> sahiptir: `admin`, `user` ve `viewer`. Tuist, her rol için bir SCIM grubu sunar: `Tuist Admins`, `Tuist Users` ve `Tuist Viewers`. Okta gruplarını **Grup İtme** ile bunlara eşleyin:

1. Atamak istediğiniz her rol için bir Okta grubu seçin veya oluşturun ve bu grupları SCIM uygulamasının **Atamalar** sekmesinde atayın.
2. API entegrasyonunda **Grupları İçe Aktar** seçeneğinin etkin olduğundan emin olun, ardından Okta’nın Tuist’in gruplarını tanıması için SCIM uygulamasının **İçe Aktar** sekmesini açın ve **Şimdi İçe Aktar** seçeneğine tıklayın.
3. SCIM uygulamasının **Grupları İt** sekmesini açın ve **Grupları İt > Ada göre grupları bul** seçeneğine tıklayın.
4. Bir Okta grubu seçin, itme eylemi olarak **Grubu Bağla** seçeneğini belirleyin ve eşleşen Tuist grubunu seçin. Tuist SCIM üzerinden grup oluşturmayı desteklemez, bu nedenle yeni bir grup oluşturmak yerine mevcut bir gruba bağlantı kurun.
5. **Kaydet** seçeneğine tıklayın ve kalan roller için işlemi tekrarlayın.

Bir kullanıcıyı bağlı bir gruba eklemek, ona o rolü verir. Kullanıcıyı gruptan çıkarmak, onu organizasyonun tek oturum açma üyelerini kaydettiği role geri döndürür; bu rol, bir yönetici **Ayarlar > Kimlik Doğrulama** altında değiştirmediyse `user` olur. Herhangi bir bağlı grupta olmayan kullanıcılar da bu rolü alır. Bir kullanıcıyı gruptan çıkarmak, onu organizasyondan kaldırmaz; bunu yapmak için Okta’da atamasını kaldırın veya hesabını devre dışı bırakın.

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID, Tuist’i galeri dışı bir kurumsal uygulama aracılığıyla sağlar. Kullanıcıların Entra ID ile de oturum açması gerekiyorsa önce <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link> yapılandırmasını yapın.

Tek oturum açma için kaydettiğiniz uygulama ile sağlama için kullandığınız kurumsal uygulama aynı olabilir. Sağlama, kurumsal uygulama girişi üzerinde yapılandırılır.

### Adım 1: Bir Tuist SCIM belirteci oluşturun {#entra-step-1}

1. Tuist’te organizasyonunuzun **Kimlik Doğrulama** ayarları sekmesine gidin.
2. **SCIM sağlama** bölümünde **SCIM uç noktası URL’sini** kopyalayın. Sonu `/scim/v2` ile bitmelidir.
3. **Belirteç oluştur** seçeneğine tıklayın.
4. Belirtece bir ad verin (örneğin, `Entra ID`).
5. Oluşturulan belirteci kopyalayın. Tuist belirteci yalnızca bir kez gösterir.

### Adım 2: Sağlamayı yapılandırın {#entra-step-2}

1. Microsoft Entra yönetim merkezinde **Kimlik > Uygulamalar > Kurumsal uygulamalar** yolunu izleyin ve Tuist uygulamasını açın.
2. **Sağlama** sekmesini açın ve **Sağlama Modu** seçeneğini **Otomatik** olarak ayarlayın.
3. **Kiracı URL’si** alanını Tuist SCIM uç noktası URL’sine ayarlayın.
4. **Gizli Belirteç** alanını Tuist SCIM belirtecine ayarlayın. Belirteci başında `Bearer ` öneki olmadan, tek başına girin; Entra ID şemayı kendisi ekler.
5. **Bağlantıyı Test Et** seçeneğine tıklayın. Entra ID, sağlanan kimlik bilgilerinin yetkilendirildiğini bildirmelidir.
6. Yapılandırmayı kaydedin.

### Adım 3: Eşleştirme özelliğini ayarlayın {#entra-step-3}

1. **Eşlemeler** altında **Microsoft Entra ID Kullanıcılarını Sağla** seçeneğini açın.
2. `userPrincipalName` veya `mail` öğesinin SCIM `userName` özelliğine eşlendiğini ve bu özelliğin **Eşleştirme önceliği 1** için kullanıldığını doğrulayın.
3. Varsa `externalId` öğesini eşleştirme özelliklerinden kaldırın.

Tuist, sağlanan kullanıcıları `userName` ile eşleştirir. Entra ID’nin `externalId` olarak gönderdiği dizin nesnesi tanımlayıcısını saklamaz, bu nedenle bu özellik üzerindeki bir filtre mevcut bir üyeyi bulamaz ve sağlama döngüleri beklenmedik şekilde davranabilir.

### Adım 4: Grup sağlamayı devre dışı bırakın {#entra-step-4}

**Eşlemeler** altında **Microsoft Entra ID Gruplarını Sağla** seçeneğini devre dışı bırakın.

Tuist’in SCIM grupları, oluşturabileceğiniz dizin grupları yerine organizasyon rolü başına sabit bir gruptur, bu nedenle bir dizin grubunu sağlama girişimi başarısız olur. Bunun yerine aşağıda açıklandığı gibi rolleri atayın.

### Adım 5: Kullanıcıları atayın ve sağlamayı başlatın {#entra-step-5}

1. Uygulamanın **Kullanıcılar ve gruplar** sekmesini açın ve Tuist’e sağlanması gereken kullanıcıları veya grupları atayın.
2. **Sağlama** sekmesine dönün ve işlemi başlatın.
3. Atanan kullanıcıların organizasyonda göründüğünü doğrulamak için Tuist’in **Üyeler** sekmesini kontrol edin.

Entra ID kendi programına göre, genellikle her 40 dakikada bir sağlama yapar, bu nedenle üyeler anında görünmez. Tek bir kullanıcıyı hemen test etmek için **Talep üzerine sağla** seçeneğini kullanın.

Sağlamayı kaldırmayı test etmek için Entra ID'de bir kullanıcının atamasını kaldırın veya devre dışı bırakın ve Tuist organizasyonunun **Üyeler** sekmesinden kaybolduklarını doğrulayın.

Daha sonra sağlama kapsamını değiştirirseniz, örneğin **Tüm kullanıcıları ve grupları eşitle** seçeneğinden **Yalnızca atanmış kullanıcıları ve grupları eşitle** seçeneğine geçerseniz, ardından **Sağlamayı yeniden başlat** seçeneğine tıklayın. Entra ID yeni kapsamı, artık kapsamda olmayan kullanıcıların sağlamasını kaldırmak dahil, yalnızca yeniden başlatmadan sonra uygular.

### Rolleri atama {#entra-assigning-administrators}

Tuist'te üç <.localized_link href="/guides/server/accounts-and-projects#roles">rol</.localized_link> bulunur: `admin`, `user` ve `viewer`. Bunları Entra ID üzerinden ayarlamak için:

1. **Uygulama kayıtları** bölümünde Tuist uygulamasını açın ve atamak istediğiniz her Tuist rolü için bir uygulama rolü ekleyin. **İzin verilen üye türleri** seçeneğini **Kullanıcılar/Gruplar** olarak, **Değer** alanını ise `admin`, `user` veya `viewer` olarak ayarlayın.
2. Kurumsal uygulamanın **Kullanıcılar ve gruplar** sekmesinde, her kullanıcıya veya gruba bu uygulama rollerinden birini atayın. Bir kullanıcı birden fazla uygulama rolüne sahip olabilir. Tuist en yetkili olanı uygular; burada `admin`, `user` üzerinde ve `user`, `viewer` üzerinde önceliklidir, bu nedenle farklı rollere eşlenmiş gruplara ait olan bir kullanıcı bunların en yüksek yetkili olanını alır.
3. **Sağlama > Eşlemeler** altında **Gelişmiş Seçenekler** açılır menüsünü açın ve **Hedef Kullanıcı özelliklerini düzenle** seçeneğini belirleyin. **Tür** alanı `String` olarak ayarlanmış ve **Çoklu Değer** seçeneği işaretlenmiş `roles` adlı bir özellik ekleyin.
4. **Sağlama > Eşlemeler > Microsoft Entra ID Kullanıcılarını Sağla** altında **Yeni Eşleme Ekle** seçeneğine tıklayın. **Eşleme türü** alanını **İfade** olarak, **İfade** alanını `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])` olarak ve **Hedef özellik** alanını eklediğiniz `roles` özelliğine ayarlayın.
5. Sağlama kapsamını **Yalnızca atanmış kullanıcıları ve grupları eşitle** olarak bırakın. `AssertiveAppRoleAssignmentsComplex`, **Tüm kullanıcıları ve grupları eşitle** ile uyumlu değildir.

`AssertiveAppRoleAssignmentsComplex`, bir kullanıcının sahip olduğu her uygulama rolünü gönderir ve kaldırmaları da iletir, bu nedenle Entra ID'de bir rolün alınması kullanıcıyı hala sahip oldukları en yetkili role düşürür. `roles[primary eq "True"].value` öğesine eşlenmiş `SingleAppRoleAssignment([appRoleAssignments])` de çalışır, ancak yalnızca tek bir rol gönderir ve Entra ID bir kullanıcı birden fazla role sahip olduğunda hangisini seçeceğine dair garanti vermez.

Entra ID'de bir kullanıcının uygulama rollerini değiştirmek, sonraki sağlama döngüsünde Tuist rolünü günceller. Uygulama rolü olmadan veya `admin`, `user` ya da `viewer` dışındaki değerlerle sağlanan bir kullanıcı, organizasyonun tek oturum açma üyelerini kaydettiği rolü alır; bu, bir yönetici **Ayarlar > Kimlik Doğrulama** altında değiştirmediyse `user` rolüdür.

## Yaşam döngüsü davranışı {#lifecycle-behavior}

Kimlik sağlayıcınız bir kullanıcıyı sağlama uygulamasına atadığında, Tuist e-posta adresi zaten bilinmiyorsa kullanıcıyı oluşturur ve ardından organizasyona ekler. E-posta adresi zaten organizasyon dışındaki mevcut bir Tuist kullanıcısına aitse, Tuist o kullanıcıyı ekler ve durumu hakkında e-posta gönderir; ancak hesap başka bir organizasyonun SCIM entegrasyonu tarafından oluşturulmuşsa bu işlem yapılmaz. Bu durumda Tuist isteği `409` ile reddeder, böylece bir kimlik sağlayıcısı başka bir organizasyonun yönettiği bir hesabı talep edemez.

Kimlik sağlayıcınız, yalnızca organizasyonunuz hesabı tek başına yönetirken bir kullanıcının e-posta adresini (`userName`) değiştirebilir. Bu, Tuist'in hesabı SCIM entegrasyonunuz aracılığıyla oluşturduğu ve o tarihten itibaren kullanıcının şifre belirlemediği, organizasyonunuzun tek oturum açma sistemi dışındaki bir sağlayıcıyla giriş yapmadığı, bir ajan kaydı talep etmediği veya başka bir organizasyona katılmadığı anlamına gelir. Diğer herhangi bir kullanıcı için Tuist değişikliği `400` ve `mutability` SCIM hata türü ile reddeder. Aynı istekte gönderilen bir devre dışı bırakmayı yine de uygular. Tuist ayrıca, başka bir organizasyonun doğruladığı bir giriş alanına veya tuist.dev üzerinde Tuist'in kendi alan adına kullanıcı oluşturmayı veya kullanıcıları bu alan adlarına yeniden adlandırmayı reddeder. Yeniden adlandırma, kullanıcının eski adresin kontrolünü kanıtladığı kaydı temizler.

Kimlik sağlayıcınız kullanıcının atamasını kaldırdığında veya kullanıcıyı devre dışı bıraktığında, Tuist kullanıcı kaydını ve sahip oldukları işleri korurken organizasyon rolünü kaldırır. Sağlamayı kaldırmak kullanıcıyı küresel olarak devre dışı bırakmaz, çünkü aynı Tuist kullanıcısı diğer organizasyonlara da ait olabilir.

Tuist üç sentetik SCIM grubunu sunar: `Tuist Admins`, `Tuist Users` ve `Tuist Viewers`. Bir gruba üye eklemek, onların organizasyon rolünü ayarlar. Mevcut rolleriyle eşleşen gruptan bir üyeyi kaldırmak, onları kayıt rolüne geri taşır ve üyelik yalnızca kullanıcının ataması kaldırıldığında veya devre dışı bırakıldığında sona erer. Kimlik sağlayıcıları ayrıca bir kullanıcıdaki SCIM `roles` özelliği aracılığıyla rolü `admin`, `user` veya `viewer` değeriyle ayarlayabilir. Birden fazla değer gönderen bir kimlik sağlayıcısı, bunların en yetkili olanını alır; burada `admin`, `user` üzerinde ve `user`, `viewer` üzerinde önceliklidir.

## Desteklenen SCIM özellikleri {#supported-scim-features}

Tuist, kimlik sağlayıcılarının yaşam döngüsü yönetimi için ihtiyaç duyduğu SCIM 2.0 uç noktalarını destekler:

- `/Users` için `POST`, `GET`, `PUT`, `PATCH` ve `DELETE`.
- `/Groups` için `GET` ve `PATCH`.
- `/ServiceProviderConfig`, `/ResourceTypes` ve `/Schemas` için SCIM keşif uç noktaları.
