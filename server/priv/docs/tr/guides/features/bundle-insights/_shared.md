## Etiketler {#tags}

Derleme varyantlarını, ortamları veya yayın kanallarını ayırt etmek için bir paket yüklerken etiket ekleyin. Paket etiketleri, Yapı İçgörüler etiketleriyle aynı kuralı izler:

```bash
tuist inspect bundle App.ipa --tags paid production
```

CI'da ayrıca virgülle ayrılmış etiketleri `TUIST_BUNDLE_TAGS` ile ayarlayabilirsiniz:

```bash
TUIST_BUNDLE_TAGS="paid,production" tuist inspect bundle App.ipa
```

Açık `--tags`, ortam değişkeninin etiketlerinin yerine geçer. Etiketler harf, rakam, kısa çizgi ve alt çizgi içerebilir; paket başına en fazla 10 etiket ve etiket başına 50 karakter olabilir. Aynı seçenekler Android paketleri için de geçerlidir. `--json` yalnızca yereldir ve etiketleri veya paketi yüklemez.

Etiketler, paket adlarının yanında ve paket ayrıntılarında görünür. Panonun **Etiketler** filtresini kullanın ve paket listesinde dahil etmek veya hariç tutmak için bir etiket girin. Eşleşme tam ve büyük/küçük harfe duyarlıdır; filtre işleçleri **içerir** ve **içermez** olarak etiketlenmiş olsa bile: `paid`, `paid-extra` ile eşleşmez. CLI üzerinden filtrelemek için:

```bash
tuist bundle list --tags paid production
```

CLI, API (`?tags=paid,production`) ve MCP `list_bundles` aracı (`tags: ["paid", "production"]`), belirtilen **tüm** etiketleri içeren paketleri döndürür. API yüklemeleri `bundle.custom_metadata.tags` kabul eder; liste ve ayrıntı yanıtları `custom_metadata.tags` döndürür. Etiketsiz mevcut paketler önceki gibi kullanılabilir durumda kalır. Etiketler paket listesini filtreler; boyut grafiklerini veya otomatik karşılaştırma ve eşik baz çizgilerini değiştirmez.

Mevcut istemciler, etiketsiz paketleri yüklemeye ve okumaya devam edebilir. Güncellenmiş istemciler, `custom_metadata` öğesini atlayan eski sunuculardan gelen yanıtları da okuyabilir. Etiketleri depolamak ve filtrelemek, paket etiketlerini destekleyen bir sunucu sürümü gerektirir: eski sunucular yükleme meta verilerini yoksayar ve etiket filtrelerini reddeder. Etiket sağlanmadığında güncellenmiş istemciler hem yükleme meta verilerini hem de etiket sorgu parametrelerini atlar.

## Paket boyutlarını anlama {#understanding-sizes}

Analiz edilen her paket için Tuist iki değer bildirir:

- **Kurulum boyutu**: uygulama bir cihaza kurulduktan sonra kapladığı alan.
- **İndirme boyutu**: kullanıcıların indirdiği sıkıştırılmış boyut. Apple paketleri için bu yalnızca `.ipa` (arşivin boyutu) için bildirilir; `.xcarchive` veya `.app` girdileri için mevcut değildir.

Boyutlar bayt cinsinden saklanır ve ondalık kural kullanılarak görüntülenir; burada 1 MB 1.000.000 bayt ve 1 GB 1.000.000.000 bayttır — Apple'ın depolama ve uygulama boyutlarını bildirmek için kullandığı aynı kural (bkz. [Apple cihazlarında depolama kapasitesinin nasıl ölçüldüğü](https://support.apple.com/en-us/102119)). 733.446.863 baytlık bir kurulum boyutu 733,4 MB olarak gösterilir.

## Sürekli entegrasyon {#continuous-integration}

Paket boyutunu zaman içinde izlemek için paketi CI üzerinde analiz edin. Önce CI'nızın <.localized_link href="/guides/server/authentication#continuous-integration">kimliğini doğruladığınızdan</.localized_link> emin olun.

Tuist'in paketi hangi projeye raporlayacağını bilmesi gerekir. Projeyi henüz bağlamadıysanız `tuist init` komutunu çalıştırın veya tanıtıcıyı kendiniz tanımlayın:

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Gradle projeleri gibi Swift manifestosu olmayan projeler için <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link> kullanın. Her iki dosya da mevcut olduğunda `Tuist.swift` önceliklidir.

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

Kurulum tamamlandıktan sonra paket boyutunuzun zaman içinde nasıl değiştiğini görebilirsiniz:

![Paket boyutu grafiği](/images/guides/features/bundle-size/bundle-size-graph.png)

## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git forge entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">Tuist projenizi</.localized_link> bir Git forge ile entegre edin: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> veya <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.

Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlandığında, `tuist inspect bundle` komutunu her çalıştırdığınızda Tuist doğrudan çekme/birleştirme isteklerinize bir yorum gönderir:

![İncelenen paketlerle GitHub uygulaması yorumu](/images/guides/features/bundle-size/github-app-with-bundles.png)

## Boyut eşikleri {#size-thresholds}

> [!WARNING]
> **Git forge entegrasyonu gerekli**
>
> Boyut eşiklerini kullanmak için [Tuist GitHub Uygulamasını](https://github.com/apps/tuist) projenize bağlayın. Bunu projenizin entegrasyonlar sayfasından yapabilirsiniz.

Boyut eşikleri, paket boyutu yapılandırılmış bir yüzdeye veya mutlak boyuta göre bir baz dalına kıyasla arttığında çekme isteklerini engellemenize olanak tanır. Bir eşik ihlal edildiğinde, Tuist PR commit'inde bir GitHub Check Run oluşturur ve boyut artışı çözülene kadar birleştirmeyi engeller:

![Paket boyutu eşiğinin aşıldığını gösteren PR durum kontrolü](/images/guides/features/bundle-size/github-pr-check-status.png)

Kontrol çalışması baz boyutu, mevcut boyutu ve yapılandırılan birimdeki değişikliği gösterir. Artış kasıtlıysa, **Kabul et** düğmesine tıklayarak bunu doğrudan GitHub arayüzünden kabul edebilirsiniz:

![Eşik ihlalini gösteren GitHub kontrol çalışması](/images/guides/features/bundle-size/github-check-run-threshold.png)

### Yapılandırma {#size-thresholds-configuration}

Eşikleri yapılandırmak için projenizin **Ayarlar > Paketler** sekmesine gidin:

![Paket boyutu eşikleri ayarları](/images/guides/features/bundle-size/bundle-size-thresholds.png)

**Kurulum boyutu** veya **İndirme boyutu** seçin, ardından bir **Eşik türü** belirleyin:

- **Yüzde (%)**: büyümeyi baz boyuta göre sınırlayın. `0.47` gibi kesirli yüzdeler desteklenir. Mevcut yüzde eşikleri yapılandırılmış değerlerini ve davranışlarını korur.
- **Mutlak boyut (MB)**: büyümeyi baz boyuttan bağımsız sabit bir miktarla sınırlayın. 1,5 MB'a kadar büyüme izin vermek için `1.5` girin. MB ondalık birimler kullanır: 1 MB = 1.000.000 bayt. Değerler pozitif bir tam bayt sayısına karşılık gelmelidir.

![Mutlak paket boyutu büyüme eşiği yapılandırması](/images/guides/features/bundle-size/absolute-size-threshold.png)

Her iki tür de yapılandırılmış **Baz dal** üzerindeki en son paketle karşılaştırma yapar; aynı ada, aynı paket türüne (örneğin `.app` veya `.ipa`) ve en az bir ortak platforma sahip olmalıdır, bu nedenle bir simülatör `.app` yalnızca simülatör `.app` yüklemeleriyle karşılaştırılır. İsteğe bağlı **Paket adı**, kuralı o pakete sınırlar. Bir kontrol yalnızca büyüme sınırı **aştığında** başarısız olur; eşit büyüme, değişmeyen boyutlar ve azalmalar başarılı sayılır. Eşleşen bir baz veya seçilen metrik için kaydedilmiş bir boyut yoksa kural atlanır. Mutlak sınırlar için sıfır boyutlu bir baz desteklenir; yüzde sınırları ise yüzde büyümesi tanımsız olduğu için onu atmaya devam eder.

### Kabul edebilecek kişileri kısıtlama {#size-thresholds-approvals}

Varsayılan olarak depoya yazma erişimi olan herkes boyut artışını kabul edebilir, çünkü GitHub düğmeyi bu kişilere gösterir. Kapsamı daraltmak için **Ayarlar > Paketler** altında **Kimler kabul edebilir** ayarını yapın:

- **Herkes**: varsayılan. Depoya yazma erişimi olan herkes.
- **Seçili GitHub kullanıcıları**: yalnızca eklediğiniz GitHub kullanıcı adları.

Listede olmayan biri kontrolün başarısız kalmasına neden olur ve açıklama gösterilir; düğme ise onu kullanabilecek kişi için görünür durumda kalır.
