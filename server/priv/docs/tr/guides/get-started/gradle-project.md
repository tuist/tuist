---
{
  "title": "Gradle projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Bir Gradle projesini Tuist'e bağlayarak ortak bir uzak derleme önbelleği, CI genelinde derleme ve test içgörüsü, paket boyutu takibi ve önizleme bağlantıları elde edin."
}
---
# Gradle projesi {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

Mevcut bir Gradle projesini Tuist’e yönlendirmek için bu yolu izleyin. `dev.tuist` Gradle eklentisi, Gradle’ın yerel derleme önbelleğini Tuist’in uzak önbelleğine bağlar ve tek bir `./gradlew` komutunu değiştirmeden derleme ve test verilerini panoya yükler.

Aşağıdaki her bölüm, bugün eksik olanla başlar ve ardından bu açığı kapatan özelliği adım adım açıklar.

## Ön koşullar

- Bir `settings.gradle.kts` (veya `settings.gradle`) içeren bir Gradle projesi.
- <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzü</.localized_link>.

## Projeyi bağlama

Gradle projesinin kök dizininden `tuist init` komutunu çalıştırın. **Gradle projesini entegre et** seçeneğini belirleyin, ardından tarayıcıda kimlik doğrulaması yapın ve projenin sahibi olması gereken hesabı seçin.

```bash
tuist init
```

Bunu bir kodlama aracısı veya betik üzerinden yürütüyorsanız, önce `tuist auth login` komutunu çalıştırın (tarayıcı akışı Enter tuşuna basmanızı bekler), ardından etkileşimsiz formu kullanın:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist, depo köküne proje tanıtıcısıyla birlikte bir `tuist.toml` yazar ve bir `plugins { ... }` bloğu çıktılar. Bunu `settings.gradle.kts` dosyasının en üstüne yapıştırın:

<!-- @snippet: ../_gradle-plugin-block -->

`./gradlew help` ile temel kontrol yapın. Gradle hatasız yüklenmelidir. Eklentiyi bulamıyorsa, bloğun `build.gradle.kts` içinde değil, `settings.gradle.kts` içinde olduğundan emin olun.

Aşağıdakilerin tümü isteğe bağlıdır ve birbirinden bağımsızdır.

## Uzak derleme önbelleği

Gradle’ın yerel derleme önbelleği, görev çıktılarını onları üreten makinede saklar. Aynı dal üzerindeki iki geliştirici, önbelleğe kendi `~/.gradle` dizinleri üzerinden erişir, birbirlerinin dizinlerine değil; CI ise her işte taze, boş bir önbellekle karşılaşır.

Tuist uzak önbelleği, Gradle’ın makineler arasında zaten kullandığı aynı anahtar/değer protokolünü genişletir. Bir görevin çıktıları, onu ilk çalıştıran makinede yüklenir ve aynı girdilerle karşılaşan diğer herkes tarafından indirilir. `gradle.properties` içinde etkinleştirin:

```properties
org.gradle.caching=true
```

Ardından iki ortamda derleme yapın:

```bash
./gradlew clean build --build-cache --info
```

Önbelleklenebilir görevler ikinci çalıştırmada `FROM-CACHE` bildirir. Zaman içindeki isabet oranlarını görmek için panoda **Önbellek** bölümünü açın.

## Derleme içgörüler

Gradle, bir derlemenin sonunda görev sürelerini yayınlar ve `--profile` ile derleme başına bir HTML raporu yazar. Hiçbiri çalıştırmalar arasında toplama yapmaz. Bir dizi commit boyunca yavaşlayan bir görev, herhangi bir tek derlemenin raporunda her zamanki gibi görünür.

`dev.tuist` eklentisi uygulandığında, her derleme için görev sürelerini otomatik olarak panoya yükler. Ekstra yapılandırma gerekmez. Eğilimi görmek için sonraki `./gradlew build` komutundan sonra panoda **Derlemeler** bölümünü açın.

## Test içgörüler

Gradle’ın test raporları derleme başına `build/reports/tests/` altında bulunur. On CI çalıştırması boyunca aralıklı olarak başarısız olan bir test, herhangi bir raporda bir kez başarısız olmuş stabil bir test gibi görünür.

Test içgörüler, her `./gradlew test` çalıştırması için her görevin sonucunu ve süresini kaydeder ve sonuçları çalıştırmalar arasında ilişkilendirir. Kararsız testler, yavaş testler ve hatalar panonun **Testler** sekmesinde görünür. Kararsızlıklar biriktiğinde, birleşmeleri engellememeleri için bunları panodan karantinaya alın.

Eklenti ayrıca, bir derlemenin getirdiği test durumlarını yeniden çalıştıran ve kararsız oldukları kanıtlandığında işaretleyen bir **stres testi modu** destekler. Bunu `settings.gradle.kts` içindeki `tuist` uzantısına ekleyin:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Paket içgörüler

Android Gradle Plugin, üretilen `.aab` boyutunu derleme çıktısında bildirir. Bu sayı dal ile birlikte kaybolur ve sürümler arasındaki boyutları karşılamak manuel bir muhasebe işidir. Play Console aynı sayıları bildirir, ancak yalnızca yapıt yüklendikten sonra.

Paket içgörüler, her `.aab` (önerilen) veya `.apk` için kurulum ve indirme boyutlarını kaydeder ve dal başına eşik aşıldığında PR kontrolünü başarısız hale getirebilir. Bunu CI sürecinize derleme adımından hemen sonra ekleyin:

```bash
tuist inspect bundle App.aab
```

Eğilimi görmek ve eşikleri yapılandırmak için panoda **Paket içgörüler → Android** bölümünü açın.

## Ön izlemeler

Play Console’un dahili test kanalı, her paylaşımda inceleme ve yayılma gecikmesi ekler. Ham bir `.apk` dosyasını Slack veya e-posta üzerinden göndermek daha hızlıdır ancak belirli bir mesajın hangi derlemeye atıfta bulunduğunu takip etmeyi zorlaştırır.

Eklenti, ayrı bir CLI yüklemesi olmadan doğrudan bir uygulama varyantı oluşturup yayınlayabilir:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Bir `tuistShare<Variant>` görevi istemek, o çağrıyı yayına alır; normal derlemeler asla ön izleme yüklemez. Desteklenen APK’lar, imzalama ve kurulum için <.localized_link href="/guides/features/previews/gradle">Gradle ön izlemeleri</.localized_link> bölümüne bakın.

## Ekibi dahil edin

Önbellek isabetleri, içgörüler ve stres testi, projeye bağlı kişi sayısı arttıkça katlanarak değer kazanır. Takım arkadaşlarınızı panodaki hesap ayarlarından organizasyona davet edin ve kayıt sürecinin kişi başı `tuist auth login` yerine tek tıkla tamamlanması için <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> (Google, Okta, Microsoft) kurulumunu yapın.

CI için kişisel giriş kullanmayın. CI sağlayıcınızın OIDC kimliğiyle kimlik doğrulaması yapın veya panoda **CI** ön ayarıyla bir hesap jetonu oluşturun ve bunu `TUIST_TOKEN` olarak ayarlayın. Ayrıntılar için <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle eklentisi kimlik doğrulaması</.localized_link> bölümüne bakın.

## Tam eklenti referansı

Burada ele alınan her şey, bir Gradle projesinde Tuist’ten değer elde etmek için gereken minimumdur. `tuist` uzantı bloğu, `stressNewTests` modu ve CI kimlik doğrulaması için yapılandırma seçenekleri [Gradle eklentisini yükleme](https://tuist.dev/en/docs/guides/install-gradle-plugin) referansında yer alır.
