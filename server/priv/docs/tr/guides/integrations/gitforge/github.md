---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Geliştirilmiş iş akışları için Tuist'i GitHub ile nasıl entegre edeceğinizi öğrenin."
}
---
# GitHub entegrasyonu {#github}

Git depoları, mevcut yazılım projelerinin büyük çoğunluğunun merkezinde yer alır. Tuist içgörülerini doğrudan pull request'lerinizde sunmak ve varsayılan dalınızı senkronize etmek gibi bazı yapılandırmaları sizin için kolaylaştırmak amacıyla GitHub ile entegre oluyoruz.

## Kurulum {#setup}

Kuruluşunuzun `Integrations` sekmesinden Tuist GitHub uygulamasını yüklemeniz gerekecektir: ![Entegrasyonlar sekmesini gösteren bir görsel](/images/guides/integrations/gitforge/github/integrations.png)

Uygulamayı doğrudan GitHub üzerinden de yükleyebilirsiniz. Gerekirse Tuist'e giriş yapın, Tuist'in kurulum erişiminizi doğrulayabilmesi için GitHub Uygulamasına yetki verin ve bağlanılacak Tuist kuruluşunu seçin. Uygulamanın yüklendiği GitHub kuruluşuna (veya kişisel GitHub hesabına) sahip olmalısınız. Yalnızca yönettiğiniz Tuist kuruluşları ve kişisel Tuist hesabınız kullanılabilir. Yalnızca bir hesap mevcutsa, Tuist seçiciyi göstermeden otomatik olarak bağlanır. Tuist üzerinden başladığınızda kuruluş zaten seçili olur ve bu adım atlanır.

Bundan sonra, GitHub deponuz ile Tuist projeniz arasında bir proje bağlantısı ekleyebilirsiniz:

![Proje bağlantısının eklenmesini gösteren bir görsel](/images/guides/integrations/gitforge/github/add-project-connection.png)

Uygulama yüklendikten sonra, panoya gerek kalmadan da bir projeyi bağlayabilirsiniz:

- **CLI:** `tuist project repository connect owner/name` ve bağlantıyı kaldırmak için `tuist project repository disconnect`.
- **REST API:** `PUT` üzerinde `DELETE` ve `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** `connect_project_repository` ve `disconnect_project_repository` araçları.

Depo, GitHub Uygulaması kurulumunun erişebileceği bir depo olmalı ve proje, deponun varsayılan dalını benimsemelidir. Hesap jetonlarının `project:admin:write` kapsamına ihtiyacı vardır.

> [!TIP]
> **IP beyaz listeye ekleme**
>
> GitHub kuruluşunuz [IP izin listeleri](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) kullanıyorsa veya GitHub örneğiniz bir güvenlik duvarının arkasındaysa, entegrasyonun deponuzla iletişim kurabilmesi için Tuist'in <.localized_link href="/guides/server/network#outbound-ip-addresses">giden IP adreslerini</.localized_link> beyaz listeye eklediğinizden emin olun.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist ayrıca kendi kendine barındırılan GitHub Enterprise Server (GHES) örnekleriyle de entegre olur. GitHub entegrasyon kartında **Enterprise server** sekmesine geçin, GHES temel URL'nizi girin (örneğin `https://github.example.com`) ve yükle'ye tıklayın.

GitHub Uygulamaları tek bir GitHub örneğiyle sınırlı olduğundan, Tuist github.com Uygulamasını GHES'inizde yeniden kullanamaz; bunun yerine, yükle düğmesi sizi GitHub'ın [Uygulama bildirim akışı](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) üzerinden götürür: GHES, yöneticinizi örnek üzerinde yeni bir Tuist Uygulaması kaydetmeye yönlendirir ve ardından yeni Uygulamanın kimlik bilgilerini Tuist'e geri iletir. Tuist bu kimlik bilgilerini kurulum başına şifrelenmiş olarak saklar ve bundan sonraki her API çağrısında, webhook imzasında ve depolarınıza yönelik bağlantılarda kullanır.

Ekstra bir Tuist sunucu yapılandırmasına gerek yoktur; bildirim akışı her şeyi otomatik olarak oluşturur ve sağlar.

#### Uygulama izinleri ve webhook olayları {#github-app-permissions}

Tuist, PR yorumları ve paket boyutu kontrolleri için aşağıdaki **depo izinlerini** gerektirir:

| İzin | Erişim | Kullanım amacı |
|---|---|---|
| Meta veriler (`metadata`) | Yalnızca okuma | Temel depo meta verileri; GitHub tarafından her Uygulama için zorunludur |
| Pull request'ler (`pull_requests`) | Okuma ve yazma | Pull request'leri, head commit SHA dahil olmak üzere okuma ve PR yorumlarını listeleme, gönderme ve güncelleme |
| Kontroller (`checks`) | Okuma ve yazma | Paket boyutu geç/kalma kontrolleri dahil olmak üzere kontrol çalıştırmaları oluşturma ve güncelleme |

Tuist, paket boyutu kontrol eylemlerini işlemek için `check_run` webhook olayını kullanır. Bildirim akışı bu aboneliği otomatik olarak yapılandırır.

Kendi kendine barındırılan bir Tuist sunucusuyla github.com üzerinde manuel Uygulama kurulumu için <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">kendi kendine barındırma kılavuzuna</.localized_link> bakın.

#### Ayrı tarayıcı ve API URL'leri {#separate-browser-and-api-urls}

Mühendisler GitHub Enterprise'a dahili bir ana makine adı üzerinden erişirken üçüncü taraf hizmetler harici bir proxy kullanıyorsa, yükle'ye tıklamadan önce her iki adresi de yapılandırın:

| Alan | Örnek | Kullanan |
|---|---|---|
| **Sunucu URL'si** | `https://github.internal.company.com` | Uygulama kaydı ve kurulumu için tarayıcınız ve Tuist'ten GitHub'a bağlantılar |
| **API URL'si** | `https://github-proxy.company.com/api/v3` | Tuist sunucuları; bildirim kodu değişimi, erişim jetonları, depo erişimi, PR yorumları ve kontroller için |

API URL'si, `/api/v3` veya proxy'niz tarafından sunulan eşdeğer yol dahil olmak üzere tam REST API temel URL'sidir. Tuist, açık bir API URL'sine `/api/v3` eklemez. Tek bir ana makine adı hem tarayıcınız hem de Tuist için çalışıyorsa boş bırakın; mevcut bağlantılar `<Server URL>/api/v3` kullanmaya devam eder.

Her iki adres de **aynı GitHub Enterprise örneğine** yönlendirilmelidir. Tarayıcınızın yalnızca Sunucu URL'sine ulaşması gerekir, API proxy'sine değil. Tuist sunucularının yalnızca API URL'sine ulaşması gerekir, dahili tarayıcı ana makine adına değil.

Harici proxy için:

- HTTPS kullanın; sertifika Tuist sunucuları tarafından güvenilir olmalı ve genel DNS, genel IP adreslerine çözümlenmelidir. API URL'si geçersiz kılmaları, Tuist'in özel IP/SSRF korumalarını atlamaz. Geçersiz kılma, `github.com` veya bir `*.github.com` uç noktası yerine Enterprise örneğinizi hedeflemelidir.
- Her Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">giden IP adresini</.localized_link> izin listesine ekleyin.
- Tuist'in kullandığı REST API uç noktalarını, `POST /api/v3/app-manifests/{code}/conversions`, `POST /api/v3/app/installations/{installation_id}/access_tokens` ve yorumlar ile kontroller için depo API uç noktalarını iletin. Bunlar GitHub'ın yukarı akış yollarıdır; proxy'niz farklı bir önek sunuyorsa bunları çevirin.
- İstekleri GitHub'a HTTP yönlendirmeleri veya etkileşimli oturum açma sayfası olmadan iletin. Tuist, Enterprise API yönlendirmelerini otomatik olarak takip etmez, bu nedenle genel IP kontrollerini atlayamazlar. Bildirim dönüştürme uç noktası, Tuist Uygulamanın kimlik bilgilerine sahip olmadan önce kurulum sırasında erişilebilir olmalıdır. GitHub Actions günlük indirmeleri bir istisnadır: Tuist imzalı arşiv yönlendirmelerini yalnızca HTTPS üzerinden takip eder, her hedefi kontrol eder ve bir genel IP'ye sabitler ve kurulum jetonunu iletmez.

GitHub, dahili ana makine adını kullanarak sayfalama bağlantıları döndürebilir. Tuist, yapılandırılmış GitHub örneğinden gelen bağlantıları API URL'sine yeniden tabanlar ve proxy'nizin yol önekini korur; ilgisiz kaynaklara yönelik bağlantılar reddedilir.

Ayrı olarak, GitHub webhooğu `https://tuist.dev/webhooks/github` adresine (veya kendi kendine barındırılan Tuist sunucunuzda `/webhooks/github`) teslim edebilmelidir. Mühendisler tarayıcı geri aramalarını tamamlamak için Tuist'e dönebilmelidir. API URL'si bu hedeflerin hiçbirini değiştirmez.

Kuruluş yöneticileri, entegrasyon kartındaki **API URL'sini Kaydet** seçeneğini kullanarak mevcut bir Enterprise entegrasyonundaki API URL'sini değiştirebilir veya temizleyebilir. Uygulamayı yeniden kurmaya veya projeyi yeniden bağlamaya gerek yoktur. Temizlemek, `<Server URL>/api/v3` değerini geri yükler. Kaydetmek, URL biçimini doğrular, proxy bağlantısını değil. Kurulum aramaları önbelleğe alındığından, webhook işleme değiştirilen bir adresi kullanmak için bir dakikaya kadar sürebilir; zaten devam eden istekler hala önceki adresi kullanabilir.

> [!NOTE]
> **Yalnızca barındırılan Tuist sunucusunda Enterprise planı**
>
> Barındırılan Tuist sunucusunda (`https://tuist.dev`), GitHub Enterprise Server entegrasyonu yalnızca **Enterprise** planındaki kuruluşlar için kullanılabilir. Kendi kendine barındırılan Tuist dağıtımları bunu herhangi bir planda kullanabilir.

## Pull/merge isteği yorumları {#pull-merge-request-comments}

GitHub uygulaması, en son <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">önizlemelere</.localized_link> veya <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">testlere</.localized_link> bağlantılar dahil olmak üzere PR'nin bir özetini içeren bir Tuist çalışma raporu gönderir:

Tuist, sonuçlar geldikçe tek bir yorumu günceller. Gradle derlemeleri, her kök proje ve istenen görev kümesi için ayrı ayrı görünür; aynı görevlerin yeniden çalıştırılması, o çağrının önceki sonucunun yerini alır. Tam derleme geçmişi Tuist'te kullanılabilir durumda kalır.

Yorumlar varsayılan olarak etkindir, mevcut entegrasyonlar için raporlamayı korur. Bir proje için bunları kapatmak veya tekrar açmak üzere **Proje Ayarları → Entegrasyonlar** bölümünü açın ve **GitHub → Çalıştırma raporu yorumları** anahtarını değiştirin. Her projenin kendi ayarı vardır; depo bağlantıları kuruluş ayarlarında yönetilmeye devam eder.

Yorumları devre dışı bırakmak, derleme veya test yüklemelerini, GitHub Actions iş özetlerini, depo bağlantılarını veya diğer GitHub entegrasyon özelliklerini devre dışı bırakmaz. Mevcut yorumlar silinmez.

![Pull request yorumunu gösteren bir görüntü](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **Gereksinimler**
>
> Yorum yalnızca CI çalıştırmalarınız <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulaması yapılmış</.localized_link> olduğunda gönderilir.

> [!NOTE]
> **`GITHUB_REF`**
>
> Bir PR commit'inde tetiklenmeyen, ancak örneğin bir GitHub yorumunda tetiklenen özel bir iş akışınız varsa, `GITHUB_REF` değişkeninin `refs/pull/<PR_NUMBER>/merge` veya `refs/pull/<PR_NUMBER>/head` olarak ayarlandığından emin olmanız gerekebilir.
>
> İlgili komutu, örneğin `tuist share`, ön ekli `GITHUB_REF` ortam değişkeniyle çalıştırabilirsiniz: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions iş özeti {#github-actions-job-summary}

Tuist CLI ve Gradle eklentisi, test ve derleme sonuçlarını GitHub Actions'daki [iş özetine](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/) yazar. Özet, kararsız testler ve paket boyutu farkları gibi daha zengin içgörülerin mevcut olduğu Tuist'teki tam rapora bağlantı verir.

Gradle için, başarıyla yüklenen her derleme veya test raporu kendi özetini ekler ve `gradle/actions/setup-gradle` gibi araçlar tarafından yazılan diğer içeriği korur. Bu, iş özeti desteği içeren bir eklenti sürümü gerektirir; eski Gradle eklenti sürümleri yalnızca GitHub Uygulamasının PR yorumu aracılığıyla rapor verir. İş özetleri için GitHub Uygulamasının bağlı olması gerekmez ve **Çalıştırma raporu yorumları**nı devre dışı bırakmak bunları etkilemez.

Bir GitHub Actions özet hedefi mevcut olduğunda, Gradle çıkmadan önce yüklemeleri ve özetleri bekler, hatta `uploadInBackground` etkin olsa bile. GitHub, iş akışı adımı tamamlandığında özeti yakalar.

![GitHub Actions iş özetindeki Tuist çalışma raporunu gösteren bir görüntü](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

Bu, özellikle [birlleştirme kuyrukları](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) ile kullanıldığında faydalıdır. Bir birleştirme kuyruğu çalıştırması bir pull request'e bağlı değildir, bu nedenle yorum gönderilmez, ancak iş özeti yine de sonuçları gösterir.

> [!NOTE]
> **Gereksinimler**
>
> İş özetleri başarılı bir rapor yüklemesi gerektirir. Barındırılan Tuist sunucusunda, CI çalıştırmalarınız <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulaması yapılmış</.localized_link> olmalıdır. Kendi kendine barındırılan örnekler, ağa güvenilen rapor yayınlama etkinleştirildiğinde kimlik bilgisi gerektirmeyen raporları da kabul edebilir.
