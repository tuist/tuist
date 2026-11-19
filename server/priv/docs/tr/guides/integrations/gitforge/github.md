---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forjları | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tuist'i GitHub ile entegre ederek iş akışlarınızı nasıl geliştireceğinizi öğrenin."
}
---
# GitHub entegrasyonu {#github}

Git depoları, mevcut yazılım projelerinin büyük çoğunluğunun merkezinde yer alır. Çekme isteklerinizde doğrudan Tuist içgörülerini sunmak ve varsayılan dalınızı senkronize etmek gibi bazı yapılandırmalardan tasarruf etmenizi sağlamak için GitHub ile entegre oluruz.

## Kurulum {#setup}

Tuist GitHub uygulamasını kuruluşunuzun `Integrations` sekmesine yüklemeniz gerekecektir: ![Entegrasyonlar sekmesini gösteren bir görsel](/images/guides/integrations/gitforge/github/integrations.png)

Uygulamayı doğrudan GitHub'dan da yükleyebilirsiniz. Gerekirse Tuist'e giriş yapın, Tuist'in kurulum erişiminizi doğrulayabilmesi için GitHub Uygulamasına yetki verin ve bağlanılacak Tuist kuruluşunu seçin. Uygulamanın yüklendiği GitHub kuruluşuna (veya kişisel GitHub hesabına) sahip olmalısınız. Yalnızca yönettiğiniz Tuist kuruluşları ve kişisel Tuist hesabınız kullanılabilir. Tuist, uygulama yalnızca kişisel GitHub hesabınıza yüklendiğinde ve kişisel Tuist hesabınız tek seçenek olduğunda seçim ekranını atlar. Bir GitHub kuruluşu için, kişisel hesabınız tek seçenek olsa bile Tuist her zaman sorar. Ekibinizin Tuist kuruluşu listede yoksa **Bir kuruluş oluştur** seçeneğini belirleyin veya yöneticilerinden birinden sizi yönetici yapmasını isteyin. Liste sayfa açıkken güncellenir; Tuist'e döndükten sonraki on dakika içinde seçtiğiniz sürece kuruluş yeniden başlatmaya gerek kalmadan görünür. Tuist'ten başladığınızda kuruluş zaten seçili olur ve bu adım atlanır.

Bundan sonra, GitHub deponuz ile Tuist projeniz arasında bir proje bağlantısı ekleyebilirsiniz:

![Proje bağlantısının eklenmesini gösteren bir görsel](/images/guides/integrations/gitforge/github/add-project-connection.png)

Uygulama yüklendikten sonra, panoya ihtiyaç duymadan bir projeyi de bağlayabilirsiniz:

- **CLI:** `tuist project repository connect owner/name` ve bağlantıyı kaldırmak için `tuist project repository disconnect`.
- **REST API:** `PUT` ve `DELETE` üzerinde `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** `connect_project_repository` ve `disconnect_project_repository` araçları.

Depo, GitHub Uygulaması kurulumunun erişebileceği bir depo olmalı ve proje, deponun varsayılan dalını benimsemelidir. Hesap jetonlarının `project:admin:write` kapsamına ihtiyacı vardır.

> [!TIP]
> **IP izin listesi**
>
> GitHub kuruluşunuz [IP izin listeleri](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) kullanıyorsa veya GitHub örneğiniz bir güvenlik duvarının arkasındaysa, entegrasyonun deponuzla iletişim kurabilmesi için Tuist'in <.localized_link href="/guides/server/network#outbound-ip-addresses">giden IP adreslerini</.localized_link> izin listesine eklediğinizden emin olun.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist ayrıca kendi kendine barındırılan GitHub Enterprise Server (GHES) örnekleriyle de entegre olur. GitHub entegrasyon kartında **Enterprise server** sekmesine geçin, GHES temel URL'nizi girin (örneğin `https://github.example.com`) ve yükle'ye tıklayın.

GitHub Uygulamaları tek bir GitHub örneğiyle sınırlı olduğundan, Tuist github.com Uygulamasını GHES'inizde yeniden kullanamaz; bunun yerine yükle düğmesi sizi GitHub'ın [Uygulama bildirim akışı](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) üzerinden geçirir: GHES, yöneticinizi örnekte yeni bir Tuist Uygulaması kaydetmeye yönlendirir ve ardından yeni Uygulamanın kimlik bilgilerini Tuist'e geri iletir. Tuist bu kimlik bilgilerini kurulum başına şifrelenmiş olarak saklar ve bundan sonra her API çağrısında, webhook imzasında ve depolarınıza yapılan bağlantılarda kullanır.

Ekstra Tuist sunucu yapılandırmasına gerek yoktur; bildirim akışı her şeyi otomatik olarak oluşturur ve sağlar.

#### Uygulama izinleri ve webhook olayları {#github-app-permissions}

Tuist, PR yorumları ve paket boyutu kontrolleri için aşağıdaki **depo izinlerini** gerektirir:

| İzin | Erişim | Kullanım amacı |
|---|---|---|
| Meta veri (`metadata`) | Yalnızca okuma | Temel depo meta verileri; GitHub tarafından her Uygulama için gereklidir |
| Çekme istekleri (`pull_requests`) | Okuma ve yazma | Çekme isteklerini okuma (baş commit SHA dahil) ve PR yorumlarını listeleme, gönderme ve güncelleme |
| Kontroller (`checks`) | Okuma ve yazma | Paket boyutu geç/kalma kontrolleri dahil olmak üzere kontrol çalıştırmaları oluşturma ve güncelleme |

Tuist, paket boyutu kontrol eylemlerini işlemek için `check_run` webhook olayını kullanır. Bildirim akışı bu aboneliği otomatik olarak yapılandırır.

Kendi kendine barındırılan bir Tuist sunucusuyla github.com üzerinde manuel Uygulama kurulumu için bkz. <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">kendi kendine barındırma kılavuzu</.localized_link>.

#### Ayrı tarayıcı ve API URL'leri {#separate-browser-and-api-urls}

Mühendisler GitHub Enterprise'a dahili bir ana makine adı üzerinden erişirken üçüncü taraf hizmetler harici bir proxy kullanıyorsa, yükle'ye tıklamadan önce her iki adresi de yapılandırın:

| Alan | Örnek | Kullanan |
|---|---|---|
| **Sunucu URL'si** | `https://github.internal.company.com` | Uygulama kaydı ve kurulumu için tarayıcınız ve Tuist'ten GitHub'a bağlantılar |
| **API URL'si** | `https://github-proxy.company.com/api/v3` | Tuist sunucuları; bildirim kodu değişimi, erişim jetonları, depo erişimi, PR yorumları ve kontroller için |

API URL'si, `/api/v3` veya proxy'nizin sunduğu eşdeğer yol dahil olmak üzere tam REST API temel URL'sidir. Tuist, açık bir API URL'sine `/api/v3` eklemez. Tek bir ana makine adı hem tarayıcınız hem de Tuist için çalışıyorsa boş bırakın; mevcut bağlantılar `<Server URL>/api/v3` kullanmaya devam eder.

Her iki adres de **aynı GitHub Enterprise örneğine** yönlendirilmelidir. Tarayıcınız yalnızca Sunucu URL'sine ulaşmalıdır, API proxy'sine değil. Tuist'in sunucuları yalnızca API URL'sine ulaşmalıdır, dahili tarayıcı ana makine adına değil.

Harici proxy için:

- Tuist sunucuları tarafından güvenilen bir sertifika ile HTTPS kullanın ve genel DNS, genel IP adreslerine çözümlemelidir. API URL'si geçersiz kılmaları, Tuist'in özel IP/SSRF korumalarını atlamaz. Geçersiz kılma, GitHub Enterprise örneğinizi hedeflemelidir, `github.com` veya bir `*.github.com` uç noktasını değil.
- Her Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">giden IP adresini</.localized_link> izin listesine ekleyin.
- Tuist'in kullandığı REST API uç noktalarını iletin; bunlar arasında `POST /api/v3/app-manifests/{code}/conversions`, `POST /api/v3/app/installations/{installation_id}/access_tokens` ve yorumlar ile kontroller için depo API uç noktaları bulunur. Bunlar GitHub'ın yukarı akış yollarıdır; proxy'niz farklı bir önek sunuyorsa bunları çevirin.
- İstekleri GitHub'a HTTP yönlendirmeleri veya etkileşimli oturum açma sayfası olmadan iletin. Tuist, Enterprise API yönlendirmelerini otomatik olarak takip etmez, bu nedenle genel IP kontrollerini atlayamazlar. Bildirim dönüştürme uç noktası, Tuist Uygulamanın kimlik bilgilerine sahip olmadan önce kurulum sırasında erişilebilir olmalıdır. GitHub Actions günlük indirmeleri bir istisnadır: Tuist imzalı arşiv yönlendirmelerini yalnızca HTTPS üzerinden takip eder, her hedefi kontrol eder ve bir genel IP'ye sabitler ve kurulum jetonunu iletmez.

GitHub, dahili ana makine adını kullanarak sayfalama bağlantıları döndürebilir. Tuist, yapılandırılmış GitHub örneğinden gelen bağlantıları API URL'sine yeniden tabanlar ve proxy'nizin yol önekini korur; alakasız kaynaklara yönelik bağlantılar reddedilir.

Ayrıca, GitHub webhooğu teslimatlarını `https://tuist.dev/webhooks/github` adresine (veya kendi kendine barındırılan Tuist sunucunuzda `/webhooks/github`) yapabilmelidir. Mühendislerin tarayıcı geri çağırmalarını tamamlamak için Tuist'e dönebilmesi gerekir. API URL'si bu hedeflerden hiçbirini değiştirmez.

Kuruluş yöneticileri, entegrasyon kartındaki **API URL'sini Kaydet** seçeneğini kullanarak mevcut bir Enterprise entegrasyonundaki API URL'sini değiştirebilir veya temizleyebilir. Uygulamayı yeniden kurmaya veya projeyi yeniden bağlamaya gerek yoktur. Temizlemek, `<Server URL>/api/v3` değerini geri yükler. Kaydetmek, URL biçimini doğrular, proxy bağlantısını değil. Kurulum aramaları önbelleğe alındığından webhook işleme yeni bir adresi kullanmak için bir dakikaya kadar sürebilir; zaten devam eden istekler önceki adresi kullanmaya devam edebilir.

> [!NOTE]
> **Yalnızca barındırılan Tuist sunucusunda Enterprise planı**
>
> Barındırılan Tuist sunucusunda (`https://tuist.dev`), GitHub Enterprise Server entegrasyonu yalnızca **Enterprise** planındaki kuruluşlar için kullanılabilir. Kendi kendine barındırılan Tuist dağıtımları bunu herhangi bir planda kullanabilir.

## Çekme/birleştirme isteği yorumları {#pull-merge-request-comments}

GitHub uygulaması, en son <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">önizlemelere</.localized_link> veya <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">testlere</.localized_link> bağlantılar dahil olmak üzere PR özeti içeren bir Tuist çalışma raporu gönderir:

Tuist, sonuçlar geldikçe tek bir yorumu günceller. Gradle derlemeleri, her kök proje ve istenen görev kümesi için ayrı ayrı görünür; aynı görevlerin yeniden çalıştırılması, o çağrının önceki sonucunun yerine geçer. Tam derleme geçmişi Tuist'te kullanılabilir durumda kalır.

Yorumlar varsayılan olarak etkindir ve mevcut entegrasyonlar için raporlamayı korur. Bir proje için bunları kapatmak veya yeniden açmak üzere **Proje Ayarları → Entegrasyonlar** bölümünü açın ve **GitHub → Çalışma raporu yorumları** seçeneğini değiştirin. Her projenin kendi ayarı vardır; depo bağlantıları kuruluş ayarlarında yönetilmeye devam eder.

Yorumları devre dışı bırakmak, derleme veya test yüklemelerini, GitHub Actions iş özetlerini, depo bağlantılarını veya diğer GitHub entegrasyon özelliklerini devre dışı bırakmaz. Mevcut yorumlar silinmez.

![Çekme isteği yorumunu gösteren bir görüntü](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **Gereksinimler**
>
> Yorum yalnızca CI çalıştırmalarınız <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulamasından geçmiş</.localized_link> olduğunda gönderilir.

> [!NOTE]
> **`GITHUB_REF`**
>
> Bir PR commit'i üzerinde tetiklenmeyen, ancak örneğin bir GitHub yorumu üzerinde tetiklenen özel bir iş akışınız varsa, `GITHUB_REF` değişkeninin `refs/pull/<PR_NUMBER>/merge` veya `refs/pull/<PR_NUMBER>/head` olarak ayarlandığından emin olmanız gerekebilir.
>
> İlgili komutu, örneğin `tuist share`, ön ekli `GITHUB_REF` ortam değişkeniyle çalıştırabilirsiniz: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions iş özeti {#github-actions-job-summary}

Tuist CLI ve Gradle eklentisi, test ve derleme sonuçlarını GitHub Actions'daki [iş özetine](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/) yazar. Özet, kararsız testler ve paket boyutu farkları gibi daha zengin içgörülerin bulunduğu Tuist'teki tam rapora bağlantı verir.

Gradle için, başarıyla yüklenen her derleme veya test raporu kendi özetini ekler ve `gradle/actions/setup-gradle` gibi araçlar tarafından yazılan diğer içerikleri korur. Bu, iş özeti desteği içeren bir eklenti sürümü gerektirir; eski Gradle eklenti sürümleri yalnızca GitHub Uygulamasının PR yorumu aracılığıyla rapor verir. İş özetleri için GitHub Uygulamasının bağlı olması gerekmez ve **Çalışma raporu yorumları**nı devre dışı bırakmak bunları etkilemez.

Bir GitHub Actions özet hedefi mevcut olduğunda, Gradle çıkmadan önce yüklemeleri ve özetleri bekler, hatta `uploadInBackground` etkin olsa bile. GitHub, iş akışı adımı tamamlandığında özeti yakalar.

![Tuist çalışma raporunu GitHub Actions iş özetinde gösteren bir görüntü](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

Bu, özellikle [birleştirme kuyrukları](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) ile kullanıldığında faydalıdır. Bir birleştirme kuyruğu çalıştırması bir çekme isteğine bağlı değildir, bu nedenle yorum gönderilmez, ancak iş özeti yine de sonuçları gösterir.

> [!NOTE]
> **Gereksinimler**
>
> İş özetleri başarılı bir rapor yüklemesi gerektirir. Barındırılan Tuist sunucusunda, CI çalıştırmalarınızın <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulamasından geçmiş</.localized_link> olması gerekir. Kendi kendine barındırılan örnekler, ağ tarafından güvenilen rapor yayınlama etkinleştirildiğinde kimlik bilgisi gerektirmeyen raporları da kabul edebilir.
