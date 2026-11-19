## Etiketler {#tags}

Derleme varyantlarını, ortamları veya dağıtım kanallarını ayırt etmek için bir paket yüklerken etiket ekleyin. Paket etiketleri, Derleme Analizleri etiketleriyle aynı kuralı izler:

```bash
tuist inspect bundle App.ipa --tags paid production
```

CI'da ayrıca virgülle ayrılmış etiketleri `TUIST_BUNDLE_TAGS` ile ayarlayabilirsiniz:

```bash
TUIST_BUNDLE_TAGS="paid,production" tuist inspect bundle App.ipa
```

Açık `--tags`, ortam değişkeninin etiketlerinin yerine geçer. Etiketler harf, rakam, tire ve alt çizgi içerebilir; paket başına en fazla 10 etiket ve etiket başına 50 karakter desteklenir. Aynı seçenekler Android paketleri için de geçerlidir. `--json` yalnızca yereldir ve etiketleri veya paketi yüklemez.

Etiketler paket adlarının yanında ve paket ayrıntılarında görünür. Kontrol panelindeki **Etiketler** filtresini kullanın ve paketi listeye dahil etmek veya hariç tutmak için bir etiket girin. Eşleşme tam ve büyük/küçük harfe duyarlıdır; filtre operatörleri **içerir** ve **içermez** olarak etiketlenmiş olsa da: `paid`, `paid-extra` ile eşleşmez. CLI'dan filtrelemek için:

```bash
tuist bundle list --tags paid production
```

CLI, API (`?tags=paid,production`) ve MCP `list_bundles` aracı (`tags: ["paid", "production"]`), belirtilen **tüm** etiketleri içeren paketleri döndürür. API yüklemeleri `bundle.custom_metadata.tags` kabul eder; liste ve ayrıntı yanıtları `custom_metadata.tags` döndürür. Etiketsiz mevcut paketler eskisi gibi kullanılabilir durumda kalır. Etiketler paket listesini filtreler; boyut grafiklerini veya otomatik karşılaştırma ve eşik baz çizgilerini değiştirmez.

Mevcut istemciler etiketsiz paketleri yüklemeye ve okumaya devam edebilir. Güncellenmiş istemciler, `custom_metadata` içermeyen eski sunuculardan gelen yanıtları da okuyabilir. Etiketlerin depolanması ve filtrelenmesi, paket etiketlerini destekleyen bir sunucu sürümü gerektirir: eski sunucular yükleme meta verilerini yoksayar ve etiket filtrelerini reddeder. Etiket sağlanmadığında güncellenmiş istemciler hem yükleme meta verilerini hem de etiket sorgu parametrelerini atlar.

## Paket boyutlarını anlama {#understanding-sizes}

Analiz edilen her paket için Tuist iki değer bildirir:

- **Kurulum boyutu**: Uygulama cihaza yüklendiğinde kapladığı alan.
- **İndirme boyutu**: Kullanıcıların indirdiği sıkıştırılmış boyut. Apple paketleri için bu yalnızca `.ipa` (arşiv boyutu) için bildirilir; `.xcarchive` veya `.app` girdileri için mevcut değildir.

Boyutlar bayt cinsinden saklanır ve ondalık kural kullanılarak görüntülenir; burada 1 MB 1.000.000 bayt ve 1 GB 1.000.000.000 bayttır — Apple'ın depolama ve uygulama boyutlarını bildirmek için kullandığı aynı kural (bkz. [Apple cihazlarında depolama kapasitesi nasıl ölçülür](https://support.apple.com/en-us/102119)). 733.446.863 baytlık bir kurulum boyutu 733,4 MB olarak gösterilir.

## Sürekli entegrasyon {#continuous-integration}

Paket boyutunu zaman içinde izlemek için paketi CI'da analiz edin. Önce CI'nızın <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulamasının yapıldığından</.localized_link> emin olun.

Tuist'in paketi hangi projeye raporlayacağını bilmesi gerekir. Projeyi henüz bağlamadıysanız `tuist init` çalıştırın veya tanıtıcıyı kendiniz belirtin:

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Gradle projeleri gibi Swift manifestosu olmayan projeler için <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link> kullanın. Her iki dosya da mevcutsa `Tuist.swift` öncelik kazanır.

Örnek bir GitHub Actions iş akışı:

::: code-group
```yaml [Apple]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
```yaml [Android]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        # .aab is recommended over .apk for more accurate size analysis
        run: tuist inspect bundle App.aab
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
<!-- -->
:::

Kurulum tamamlandığında, paket boyutunuzun zaman içinde nasıl değiştiğini görebilirsiniz:

![Paket boyutu grafiği](/images/guides/features/bundle-size/bundle-size-graph.png)

## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git platformu entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">Tuist projenizi</.localized_link> bir Git platformuyla entegre edin: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> veya <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.

Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlantılı olduğunda, `tuist inspect bundle` çalıştırdığınızda Tuist doğrudan çekme/birleştirme isteklerinize bir yorum ekler:

![İncelenen paketlerle GitHub uygulaması yorumu](/images/guides/features/bundle-size/github-app-with-bundles.png)

## Boyut eşikleri {#size-thresholds}

> [!WARNING]
> **Git platformu entegrasyonu gerekli**
>
> Boyut eşiklerini kullanmak için [Tuist GitHub Uygulamasını](https://github.com/apps/tuist) projenize bağlayın. Bunu projenizin entegrasyonlar sayfasından yapabilirsiniz.

Boyut eşikleri, paket boyutu bir baz dalına göre yapılandırılmış yüzde veya mutlak boyutu aştığında çekme isteklerini engellemeye olanak tanır. Bir eşik ihlal edildiğinde, Tuist PR commit'inde bir GitHub Kontrol Çalıştırması oluşturur ve boyut artışı çözülene kadar birleştirmeyi engeller:

![Paket boyutu eşiğinin aşıldığını gösteren PR durum kontrolü](/images/guides/features/bundle-size/github-pr-check-status.png)

Kontrol çalıştırması baz boyutunu, mevcut boyutu ve yapılandırılan birimdeki değişimi gösterir. Artış kasıtlıysa, **Kabul Et** düğmesine tıklayarak bunu doğrudan GitHub arayüzünden kabul edebilirsiniz:

![Eşik ihlalini gösteren GitHub kontrol çalıştırması](/images/guides/features/bundle-size/github-check-run-threshold.png)

### Yapılandırma {#size-thresholds-configuration}

Eşikleri yapılandırmak için projenizin **Ayarlar > Paketler** sekmesine gidin:

![Paket boyutu eşikleri ayarları](/images/guides/features/bundle-size/bundle-size-thresholds.png)

**Kurulum boyutu** veya **İndirme boyutu** seçin, ardından bir **Eşik türü** belirleyin:

- **Yüzde (%)**: Büyümeyi baz boyuta göre sınırlayın. `0.47` gibi kesirli yüzdeler desteklenir. Mevcut yüzde eşikleri yapılandırılan değerlerini ve davranışlarını korur.
- **Mutlak boyut (MB)**: Büyümeyi baz boyuttan bağımsız sabit bir miktarla sınırlayın. 1,5 MB'a kadar büyümeye izin vermek için `1.5` girin. MB ondalık birimler kullanır: 1 MB = 1.000.000 bayt. Değerler pozitif bir tam bayt sayısına karşılık gelmelidir.

![Mutlak paket boyutu büyüme eşiği yapılandırması](/images/guides/features/bundle-size/absolute-size-threshold.png)

Her iki tür de, yapılandırılan **Baz dalı** üzerindeki aynı ada, aynı paket türüne (örneğin `.app` veya `.ipa`) ve en az bir ortak platforma sahip en son pakete göre karşılaştırma yapar; bu nedenle simülatör `.app` yalnızca simülatör `.app` yüklemeleriyle karşılaştırılır. İsteğe bağlı **Paket adı**, kuralı o paketle sınırlar. Bir kontrol yalnızca büyüme limiti **aştığında** başarısız olur; eşit büyüme, değişmeyen boyutlar ve azalmalar başarılı sayılır. Eşleşen bir baz veya seçilen metrik için kaydedilmiş bir boyut yoksa kural atlanır. Mutlak limitler için sıfır boyutlu bir baz desteklenir; yüzde büyümesi tanımsız olduğu için yüzde limitleri bunu atmaya devam eder.

### Kimin kabul edebileceğini kısıtlama {#size-thresholds-approvals}

Varsayılan olarak depoya yazma erişimi olan herkes boyut artışını kabul edebilir, çünkü GitHub düğmeyi bu kişilere gösterir. Kapsamı daraltmak için **Ayarlar > Paketler** altında **Kim kabul edebilir** ayarını yapın:

- **Herkes**: varsayılan. Depoya yazma erişimi olan herkes.
- **Seçili GitHub kullanıcıları**: yalnızca eklediğiniz GitHub kullanıcı adları.

Listede olmayan biri kontrolün başarısız kalmasına neden olur ve bir açıklama gösterilir; düğme ise onu kullanabilecek kişi için görünür durumda kalır.
