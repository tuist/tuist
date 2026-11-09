---
{
  "title": "Xcode projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Proje oluşturmayı benimsemeden, Xcode derleme önbelleği, derleme ve test analizleri, paket boyutu takibi ve önizleme bağlantıları için mevcut bir Xcode projesini Tuist'e bağlayın."
}
---
# Xcode projesi {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

`.xcodeproj` veya `.xcworkspace` dosyalarınızı olduğu gibi korumak ve proje oluşturma özelliğini benimsemeden Tuist’in yeteneklerinden yararlanmak istiyorsanız bu yolu izleyin. Aşağıdaki her bölüm, bugün eksik olan şeyle başlar ve ardından bu boşluğu dolduran özelliği adım adım açıklar.

## Ön Koşullar

- **Xcode 26 veya üzeri** yüklü macOS (derleme önbelleği ve modern içgörüler buna bağlıdır).
- <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzü</.localized_link>.

## Projeyi Bağla

Depo kök dizininde `tuist init` çalıştırın. Tuist çalışma alanınızı algıladığında **`<YourApp>` Entegre Et** seçeneğini belirleyin, ardından tarayıcıda kimlik doğrulaması yapın ve projenin sahibi olacak hesabı seçin. Tuist, kök dizine projenin tanıtıcısını sabitleyen bir `Tuist.swift` yazar; böylece ekip arkadaşlarınız ve CI aynı bağlantıyı paylaşır. Bu dosyayı commit edin.

Bunu bir kodlama aracısı veya betik üzerinden yürütüyorsanız, önce `tuist auth login` çalıştırın (tarayıcı akışı Enter tuşuna basmanızı bekler), ardından etkileşimsiz formu kullanın:

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

Aşağıdakilerin tümü isteğe bağlı ve bağımsızdır.

## Xcode Derleme Önbelleği

Xcode 26, dosya bazlı bir derleme önbelleği ile birlikte gelir ancak bu önbelleğin deposu makinenin `DerivedData` klasörü içinde bulunur. Temiz bir derleme bu önbelleği yerel olarak doldurur; ekip arkadaşlarınız ve CI çalıştırıcıları bu depoyu göremediği için sıfırdan yeniden derleme yapar.

`tuist setup cache`, Xcode’un derleme önbelleğini paylaşılan Tuist önbellek ağına yönlendirir. Herhangi bir geliştirici makinesinde veya CI çalıştırmasında gerçekleşen bir önbellek isabeti, aynı revizyonu derleyen diğer tüm makinelerin de bundan faydalanmasını sağlar.

```bash
tuist setup cache
```

Komut, Xcode’un paylaşılan önbelleği kullanması için gereken derleme ayarlarını yazdırır. Projenizi düzenlemez; bu nedenle ayarları projenizin derleme ayarlarına veya bir `.xcconfig` dosyasına ekleyin. Detaylar için bkz. <.localized_link href="/guides/features/cache/xcode-cache#configure-xcode-build-settings">Xcode derleme ayarlarını yapılandırma</.localized_link>.

Xcode’da derleme yapın, ardından aynı revizyonu ikinci bir makinede veya bir CI çalıştırıcısında derleyin. İkinci derleme çok daha kısa sürede tamamlanır ve Xcode’un derleme raporu derleme önbelleği isabetlerini gösterir.

## Derleme İçgörüleri

Xcode, hedef bazlı derleme sürelerini günlükte ve derleme raporunda kaydeder. Ancak bu veriler çalıştırmalar veya makineler arasında toplanmaz. Bir PR’a düşen derleme süresi gerilemesi genellikle yalnızca CI’nin genel olarak yavaşlaması olarak ortaya çıkar; hangi hedefin buna neden olduğu veya ne zaman başladığı konusunda net bir sinyal verilmez.

Derleme içgörüleri, her derlemenin süresini ve aşama zamanlamalarını kaydeder; böylece eğilim panoda görünür hale gelir. Şemanıza eklenen tek satırlık bir post-action ile bunu sağlayabilirsiniz:

1. Xcode’da: **Product → Scheme → Edit Scheme…**
2. **Build → Post-actions** bölümünü genişletin, **+** düğmesine tıklayın ve **New Run Script Action** seçeneğini belirleyin.
3. **Provide build settings from** altında uygulama hedefinizi seçin.
4. Tuist’i nasıl yüklediğinize uygun olan satırı yapıştırın: ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode şema betikleri kabuğunuzun `PATH` değişkenini miras almaz; bu nedenle mise shim’i otomatik olarak bulunamaz. Yukarıdaki Mise satırı, mise’yi mutlak yoluyla çağırır ve projenizde sabitlenmiş sürümü seçmesi için yapılandırmayı `$SRCROOT` konumundan yüklemesini ister.
5. Bir kez derleme yapın. Derleme, saniyeler içinde panonun **Derlemeler** sekmesinde görünür.

## Test İçgörüleri

Xcode’un test günlüğü, test sonuçlarını her çalıştırma için ayrı ayrı listeler. Aslında ihtiyacınız olan çapraz-çalıştırma sinyallerini toplamaz: bir testin ne sıklıkla başarısız olduğu, geçen hafta ne kadar yavaşladığı veya yalnızca belirli simülatörlerde mi başarısız olduğu. On CI çalıştırması boyunca güvenilirlikten kararsızlığa kayan bir test, tek bir şanssız çalıştırma ile aynı görünür.

Test içgörüleri, her testin sonucunu ve süresini kaydeder ve sonuçları çalıştırmalar arasında ilişkilendirir. Yavaş testler, başarısızlıklar ve kararsız testler panonun **Testler** sekmesinde görünür.

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

## Paket İçgörüleri

Bir IPA’nın kurulum ve indirme boyutu, eklenen her varlık ve bağlanan her sembolle değişir. Xcode boyutları seri halinde değil, yalnızca talep üzerine **Product → Show Archive** menüsünde raporlar. Büyük bir varlık ekleyen bir PR, birleştirme kuyruğundaki diğer PR’lardan ayırt edilemez.

Paket içgörüleri, analiz edilen her derleme için kurulum ve indirme boyutlarını kaydeder ve dal başına eşik aşıldığında PR kontrolünü başarısız sayabilir. Bunu CI sürecinize derleme adımının hemen ardından ekleyin:

```bash
tuist inspect bundle App.ipa
```

Eğilimi görmek ve eşikleri yapılandırmak için panoda **Paket içgörüleri** bölümünü açın.

## Önizlemeler

TestFlight, her paylaşım için bir derleme ve inceleme döngüsü ekler. İmzalı bir `.ipa` doğrudan göndermek, alıcının UDID’sinin sağlama profilinde bulunmasını gerektirir. Yalnızca mevcut dalı denemek isteyen bir tasarımcı veya QA uzmanı için her iki yöntem de pratik değildir.

Önizlemeler, bir derlemeyi tek bir komutla simülatörde veya cihazda çalıştırılabilen paylaşılabilir bir bağlantıya dönüştürür:

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

Bağlantıyı gönderin. Alıcılar bunu `tuist run <url>` veya Tuist macOS uygulamasıyla çalıştırır.

## Ekibi de dahil edin

Önbellek ve içgörüler, projeye bağlı kişi sayısı arttıkça katlanarak büyür. Ekibinizi panodaki hesap ayarlarından organizasyona davet edin ve kayıt işleminin kişi başına `tuist auth login` yerine tek tıklama olmasını sağlamak için <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> (Google, Okta, Microsoft) kurulumunu yapın.

## Sonraki adım

Bu yaklaşım yetersiz kalırsa atılacak en büyük adım Tuist tarafından oluşturulan projelerdir. Bu gerçek bir değişikliktir (hedefler bir `.xcodeproj` yerine Swift manifest dosyalarında tanımlanır), ancak modül önbelleğini ve seçici testi kullanıma açan da budur. Süreç, <.localized_link href="/guides/get-started/generated-xcode-project">Oluşturulmuş Xcode projesi</.localized_link> kılavuzunda uçtan uca ele alınmıştır.
