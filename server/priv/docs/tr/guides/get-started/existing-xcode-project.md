---
{
  "title": "Xcode projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Mevcut bir Xcode projesini, proje oluşturma benimsemeden Xcode derleme önbelleği, derleme ve test içgörülerine erişim, paket boyutu takibi ve önizleme bağlantıları için Tuist'e bağlayın."
}
---
# Xcode projesi {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

`.xcodeproj` veya `.xcworkspace` dosyanızı olduğu gibi bırakmak ve proje oluşturmayı benimsemeden Tuist'in yeteneklerinden yararlanmak istediğinizde bu yolu izleyin. Aşağıdaki her bölüm, bugün nelerin eksik olduğunu açıklayarak başlar ve ardından bu açığı dolduran özelliği adım adım anlatır.

## Ön Koşullar

- **Xcode 26 veya üzeri** yüklü macOS (derleme önbelleği ve modern içgörüler buna bağlıdır).
- <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzü</.localized_link>.

## Projeyi Bağla

Depo kök dizininde `tuist init` çalıştırın. Tuist çalışma alanınızı algıladığında **`<YourApp>` Entegre Et** seçeneğini belirleyin, ardından tarayıcıda kimlik doğrulaması yapın ve projenin sahibi olması gereken hesabı seçin. Tuist, kök dizine projeyi sabitleyen bir `Tuist.swift` yazar; böylece ekip arkadaşlarınız ve CI aynı bağlantıyı paylaşır. Bu dosyayı commit edin.

Bunu bir kodlama aracısı veya betik üzerinden yürütüyorsanız, önce `tuist auth login` çalıştırın (tarayıcı akışı Enter tuşuna basmanızı bekler), ardından etkileşimsiz formu kullanın:

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

Aşağıdakilerin tümü isteğe bağlı ve bağımsızdır.

## Xcode derleme önbelleği

Xcode 26, dosya başına derleme önbelleği ile birlikte gelir, ancak deposu makinenin `DerivedData` içinde bulunur. Temiz bir derleme bunu yerel olarak doldurur; ekip arkadaşlarınız ve CI çalıştırıcıları bu depoyu görmedikleri için sıfırdan yeniden derleme yapar.

`tuist setup cache`, Xcode'un derleme önbelleğini paylaşılan Tuist önbellek ağına yönlendirir. Herhangi bir geliştirici makinesinde veya CI çalıştırmasında gerçekleşen bir isabet, aynı revizyonu derleyen diğer tüm makinelerin yararına olur.

```bash
tuist setup cache
```

Komut, Xcode'un paylaşılan önbelleği kullanması için gereken derleme ayarlarını yazdırır. Projenizi düzenlemez, bu nedenle bunları projenizin derleme ayarlarına veya `.xcconfig` dosyasına ekleyin; ayrıntılar için <.localized_link href="/guides/features/cache/xcode-cache#configure-xcode-build-settings">Xcode derleme ayarlarını yapılandırma</.localized_link> bölümüne bakın.

Xcode'da derleme yapın, ardından aynı revizyonu ikinci bir makinede veya bir CI çalıştırıcısında derleyin. İkinci derleme çok daha kısa sürede tamamlanır ve Xcode'un derleme raporu derleme önbelleği isabetlerini gösterir.

## Derleme içgörleri

Xcode, hedef başına derleme sürelerini günlükte ve derleme raporunda kaydeder. Bunlar çalıştırmalar veya makineler arasında toplanmaz. Bir PR'de ortaya çıkan derleme süresi gerilemesi genellikle yalnızca genel olarak daha yavaş bir CI olarak kendini gösterir; hangi hedefin buna neden olduğu veya ne zaman başladığı konusunda net bir sinyal vermez.

Derleme içgörileri, her derlemenin süresini ve aşama zamanlamalarını kaydeder, böylece eğilim panoda görünür hale gelir. Şemanıza tek satırlık bir post-action eklemeniz yeterlidir:

1. Xcode'da: **Product → Scheme → Edit Scheme…**
2. **Build → Post-actions** bölümünü genişletin, **+** düğmesine tıklayın ve **New Run Script Action** seçeneğini belirleyin.
3. **Provide build settings from** altında uygulama hedefinizi seçin.
4. Tuist'i nasıl yüklediğinize uygun olan satırı yapıştırın: ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode şema betikleri kabuğunuzun `PATH` değerini miras almaz, bu nedenle mise shim'i otomatik olarak bulunamaz. Yukarıdaki Mise satırı, mise'yi mutlak yoluyla çağırır ve projenizde sabitlenen sürümü seçmesi için yapılandırmayı `$SRCROOT` konumundan yüklemesini ister.
5. Bir kez derleyin. Derleme, saniyeler içinde panonun **Derlemeler** sekmesinde görünür.

## Test içgörleri

Xcode'un test günlüğü, test sonuçlarını her çalıştırmada tek tek listeler. Aslında ihtiyacınız olan çapraz-çalıştırma sinyalini toplamaz: bir testin ne sıklıkla başarısız olduğu, geçen hafta ne kadar yavaşladığı veya yalnızca belirli simülatörlerde mi başarısız olduğu. On CI çalıştırması boyunca güvenilirlikten kararsızlığa kayan bir test, tek bir şanssız çalıştırma ile aynı görünür.

Test içgörileri, her testin sonucunu ve süresini kaydeder ve sonuçları çalıştırmalar arasında ilişkilendirir. Yavaş testler, başarısızlıklar ve kararsız testler panonun **Testler** sekmesinde görünür.

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**.
3. Uygulama hedefinizden **Provide build settings from** seçeneğini belirleyin.
4. Yapıştırın: ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. Test eylemini bir kez çalıştırın. Sonuçlar panonun **Testler** sekmesinde görünür.

## Paket içgörleri

Bir IPA'nın kurulum ve indirme boyutu, eklenen her varlık ve bağlanan her sembolle değişir. Xcode boyutları seri halinde değil, talep üzerine **Product → Show Archive** içinde raporlar. Büyük bir varlık ekleyen bir PR, birleştirme kuyruğundaki diğer PR'lerden ayırt edilemez.

Paket içgörileri, analiz edilen her derleme için kurulum ve indirme boyutlarını kaydeder ve dal başına eşik aşıldığında PR kontrolünü başarısız hale getirebilir. Bunu CI sürecinize derleme adımından hemen sonra ekleyin:

```bash
tuist inspect bundle App.ipa
```

Eğilimi görmek ve eşikleri yapılandırmak için panoda **Paket içgörileri** bölümünü açın.

## Önizlemeler

TestFlight, her paylaşımda bir derleme ve inceleme döngüsü ekler. İmzalı bir `.ipa` doğrudan göndermek, alıcının UDID'sinin sağlama profilinde olmasını gerektirir. Hiçbiri, yalnızca mevcut dalı denemek isteyen bir tasarımcı veya QA uzmanı için kullanışlı değildir.

Önizlemeler, bir derlemeyi tek bir komutla simülatörde veya cihazda çalışan paylaşılabilir bir bağlantıya dönüştürür:

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

Bağlantıyı gönderin. Alıcılar bunu `tuist run <url>` veya Tuist macOS uygulamasıyla çalıştırır.

## Ekibi de dahil edin

Önbellek ve içgörülerin etkisi, projeye bağlı kişi sayısı arttıkça katlanarak büyür. Ekip arkadaşlarınızı panodaki hesap ayarlarından organizasyona davet edin ve <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> (Google, Okta, Microsoft) kurulumunu yapın; böylece yeni kullanıcı ekleme işlemi kişi başına `tuist auth login` yerine tek bir tıklama ile tamamlanır.

## Sonraki adım

Bu yaklaşım yetersiz kalırsa atılacak en büyük adım Tuist tarafından oluşturulan projelere geçmektir. Bu gerçek bir değişimdir (hedefler bir `.xcodeproj` yerine Swift manifest dosyalarında tanımlanır), ancak modül önbelleği ve seçici testin kilidini açan şey budur. Süreç, <.localized_link href="/guides/get-started/generated-xcode-project">Oluşturulan Xcode projesi</.localized_link> kılavuzunda uçtan uca ele alınmıştır.
