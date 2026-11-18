---
{
  "title": "Elixir Derleme İçgörüler",
  "titleTemplate": ":title · Derleme İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Elixir projenizin Mix ile derlenmesinin ne kadar sürdüğünü, uyarıları ve derlemelerinizi yavaşlatan dosyaları takip edin."
}
---
# Elixir derleme içgörüleri {#elixir-build-insights}

Tuist'in Hex paketi derleme analizlerini Tuist'e gönderebilir. Derleme süreleri, dosyalarınız arasındaki bağımlılık grafiği ve bunların zaman içindeki değişimi, derleme grafiğinizi optimize etmeniz ve derlemenin gerçekleştiği ortamda bulunan tüm çekirdeklerden en iyi şekilde yararlanmanız için ihtiyacınız olan bilgileri sağlar.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/elixir-project">Elixir ile başlayın</.localized_link> kılavuzunu tamamlayın

## Derlemelerinizi bildirin {#report-your-builds}

Paylaşılan kurulum, derleme entegrasyonunu yükler. Alıştığınız komutları kullanmaya devam edin:

```bash
mix compile
```

Entegrasyon `mix compile` ve başka bir görevin tetiklediği her derlemeyi kapsar; örneğin `mix test` veya `mix phx.server`. Yapılacak bir iş bulamayan bir derleme bildirilmez, bu nedenle pano yalnızca iş yapan derlemeleri listeler.

## Aktör talebini bildirin {#report-actor-claim}

Mix derleme ve test raporu istekleri, yalnızca açıkça bir etiket yapılandırdığınızda isteğe bağlı `x-tuist-actor-id` üstbilgisini içerir. `TUIST_ACTOR_ID` değerini kuruluş kapsamında bir etikete ayarlayın veya projenin `tuist` yapılandırmasına `actor_id: "developer-label"` ekleyin. Çözümleme önceliği sırasıyla ortam değişkenine, çalışma zamanı `:actor_id` seçeneklerine ve ardından proje yapılandırmasına verir. Varsayılan olarak hiçbir etiket gönderilmez ve paket işletim sistemi kullanıcı adlarını algılamaz. Sabit bir proje etiketi, o yapılandırmayı kullanan herkes için geçerlidir. Boş veya geçersiz geçersiz kılmalar, geri dönüş yapmak yerine talebi atlar; bu, kimlik bilgisi tabanlı doğrulanmış kimliği kaldırmaz. Özel bir proxy tanıdık olmayan üstbilgileri reddederse, `TUIST_ACTOR_ID=""` ile devre dışı bırakın.

Tanımlayıcılar, boşluk içermeyen yazdırılabilir ASCII karakterlerinden oluşan 1–128 bayt olmalıdır. Geçersiz geçersiz kılmalar, geri dönüş yapılmadan atlanır. Doğrulanmış bireysel kimlik bilgileri önceliklidir; diğer istemci tarafından bildirilen tanımlayıcılar **Doğrulanmamış** olarak görüntülenir, erişime asla yetki vermez ve kullanıcılarla otomatik olarak ilişkilendirilmez. Projenin raporlarını görüntüleyebilen herkes, proje herkese açık olduğunda genel izleyiciler dahil, bu tanımlayıcıları görebilir ve bunlar veri dışa aktarımlarına dahil edilir; bu nedenle gizli bilgiler eklemeyin. Eski sunucular isteğe bağlı üstbilgiyi yoksayar ve yeni sunucular bunu içermeyen eski istemcileri kabul eder. Tanımlayıcısı olmayan yeni ortak jeton raporları, yayıncı kuruluş yerine **Bilinmiyor** gösterir; geçmiş raporlar önceki atıflarını korur. Derleme ve test raporlama varsayılan olarak kimlik doğrulama gerektirir. Kendi kendine barındırılan kurulumlar, aşağıda açıklandığı gibi kimlik bilgisi gerektirmeyen raporlamayı açıkça etkinleştirebilir.

## Özel ağda kimlik bilgisi gerektirmeyen raporlama {#network-trusted-publishing}

Bir operatör örnekte `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` yapılandırdıktan ve <.localized_link href="/guides/server/self-host/server#network-trusted-access">kendi kendine barındırma kılavuzu</.localized_link>nda açıklandığı gibi yeniden başlattıktan sonra hedefinizi yapılandırın. SDK, kimlik bilgileri olmadığında örneğin kimlik bilgisi gerektirmeyen raporlamaya izin verip vermediğini otomatik olarak keşfeder. Örnek ayarı desteklenen her projeyi kapsar ve panoda bir geçiş anahtarı yoktur:

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

`mix tuist.compile` ve `mix tuist.test`, kimlik bilgileri gerçekten yoksa ve keşif sunucunun buna izin verdiğini onaylarsa, oturum açmadan yapılandırılmış raporlar yayınlar. İstemci bayrağı veya proje katılımı gerekmez. Mevcut kimlik bilgileri, sağlanan CI OIDC kimliği dahil, kullanılır veya reddedilir; imzasız raporlamaya düşürmek için asla yoksayılmaz. Yalnızca boşluk içeren bir `TUIST_TOKEN` hatadır. Boş bir `TUIST_TOKEN`, geçerli saklanan kimlik bilgilerine veya sağlanan OIDC'ye geri dönebilir ve eski saklanan kimlik bilgileri sağlanan OIDC'ye geri dönebilir; her iki yol da kimlik doğrulamalı kalır ve asla imzasız raporlamayı etkinleştirmez. Kullanılamaz kimlik bilgileri korunur ve kimlik doğrulamalı bir geri dönüş başarısız olduğunda hata verir. Kimlik bilgisi gerektirmeyen istemcileri yükseltmeden önce her sunucu kopyasını keşif yetenekli bir sürüme yükseltin; keşif özelliği olmayan eski sunucular, devre dışı bırakılmış örnekler ve keşif hataları hala kimlik doğrulama gerektirir.

İmzasız çalıştırmalar telemetridir; güvenilir kararsızlık, karantina, kapsam veya seçici yürütme kanıtı değildir. Parça planlama, derleme arşivleri ve kapsam/yapıt uç noktaları hala kimlik bilgisi gerektirir. Yapılandırılmış aktör talebini atlamak için `TUIST_ACTOR_ID=""` değerini bağımsız olarak ayarlayın; doğrulanmış kimlik bilgisi kimliği etkilenmez.

## Neler izlenir {#what-is-tracked}

Paket her derleme için şunları toplar:
- Süresi, başarılı olup olmadığı ve çalıştığı Elixir, Erlang/OTP ve Mix ortamı
- Her uyarı ve hata, dosyası ve satırı ile birlikte
- Her dosyanın derlenmesinin ne kadar sürdüğü ve tanımladığı modüller
- Her dosyanın bağımlı olduğu dosyalar ve bunlara derleme zamanında mı yoksa yalnızca çalışma zamanında mı ihtiyaç duyduğu
- Derlemenin dosya derlemenin yanı sıra yaptığı işler; tür denetimi, diske yazma ve diğer Mix derleyicileri gibi
- Derleme sırasında makinenin işlemci, bellek, ağ ve disk kullanımı
- Dal ve commit ve sürekli entegrasyonda sağlayıcı ve çalıştırma

## Bir derlemeyi yavaşlatan şeyleri bulun {#find-what-slows-a-build-down}

Panoda **Derlemeler → Derleme Çalıştırmaları** bölümünden bir derleme açın. Derlemeler, tanılama sayıları ve bağımlılık önbelleği özetleri ayrıca `tuist build mix list` ve `tuist build mix show`, `GET /api/projects/{account_handle}/{project_handle}/mix/builds` ile `list_mix_builds` ve `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP araçları</.localized_link> aracılığıyla kullanılabilir.

**Genel Bakış** sekmesi derlemenin derlediği dosyaları listeler. Bunları modüle göre gruplayabilir, arayabilir ve şu şekilde sıralayabilirsiniz:
- **Derleme süresi**: kendi başına yavaş olan dosyaları bulmak için.
- **Derleme zamanı bağımlıları**: Bu dosya derlenene kadar derlenemeyen dosya sayısı. Çok sayıda bağımlısı olan yavaş bir dosya derlemenin geri kalanını bekletir ve değiştirildiğinde hepsinin yeniden derlenmesine neden olur.
- **Derleme zamanı bağımlılıkları**: Bu dosyanın beklediği dosya sayısı.

![Phoenix uygulamasının Mix derlemesine genel bakış](/images/guides/features/elixir/build.png)

**Zaman Çizelgesi** sekmesi aynı derlemeyi zaman içinde gösterir: hangi dosyaların paralel derlendiği, derlemenin tür denetimi yaptığı ve diske yazdığı yerler ve makinenin her anda durumu. Tek bir çubuk içeren bir aralık, derlemenin sahip olduğu çekirdekleri kullanamadığı bir aralıktır.

![Phoenix uygulamasının tam bir Mix derlemesinin zaman çizelgesi](/images/guides/features/elixir/build-timeline.png)

**Uyarılar** ve **Hatalar** sekmeleri derlemenin tanılama bilgilerini listeler.

## Özel meta veriler {#custom-metadata}

Farklı ekiplerden, donanımlardan veya iş akışlarından gelen çalıştırmaları ayırt etmek için Mix derlemelerine etiketler ve anahtar-değer verileri ekleyin. Her ikisi de her derlemenin ayrıntı sayfasında görünür.

Meta verileri ortam değişkenleriyle ayarlayın:

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

Meta verileri `mix.exs` içinde de yapılandırabilirsiniz:

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

Her iki kaynaktan gelen etiketler birleştirilir. Aynı anahtar her iki yerde de yapılandırıldığında, ortam değişkenindeki değer öncelik kazanır.

Etiketler yalnızca harf, rakam, tire ve alt çizgi içerebilir. Bir derleme en fazla 50 etikete sahip olabilir ve her etiket en fazla 50 karakter içerebilir. Bir derleme en fazla 20 anahtar-değer girdisine sahip olabilir; her anahtar en fazla 50 karakter, her değer ise en fazla 500 karakter içerebilir. Bunlar, Xcode derleme meta verileri için kullanılan sunucu tarafı limitlerle aynıdır. Paket, raporu göndermeden önce geçersiz etiketleri ve boyutu aşan veya boş meta veri girdilerini atlar, bu nedenle geçersiz yapılandırma derleme içgörüsü raporunun geri kalanının depolanmasını engelleyemez. Etiket kısıtlamasını karşılamayan değerler için anahtar-değer meta verilerini kullanın.

Özel meta veriler derlemelere eklenir, test çalıştırmalarına değil.

Özel meta veriler panoda proje üyeleri tarafından görülebilir. Kimlik bilgileri, erişim tokenları veya diğer hassas veriler için kullanmayın. Tuist, bu meta veriler dahil olmak üzere Mix derleme verilerini 90 gün boyunca saklar. Ayrıntılar için <.localized_link href="/guides/server/data-retention">veri saklama politikasına</.localized_link> bakın.

## Sorun giderme {#troubleshooting}

Raporlama, derlemenizin sonucunu asla değiştirmez: Rapor gönderilemezse derleme normal şekilde tamamlanır ve hiçbir şey yazdırılmaz. Bir raporun neden gönderilmediğini görmek için `TUIST_DEBUG=1` ayarlayın:

```bash
TUIST_DEBUG=1 mix compile --force
```
