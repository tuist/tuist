---
{
  "title": "Gradle projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Ortak uzak derleme önbelleği, CI genelinde derleme ve test içgörüleri, paket boyutu takibi ve önizleme bağlantıları için bir Gradle projesini Tuist'e bağlayın."
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

Aşağıdaki her bölüm, bugün eksik olanla başlar ve ardından bu boşluğu dolduran özelliği adım adım açıklar.

## Ön koşullar

- Bir `settings.gradle.kts` (veya `settings.gradle`) içeren bir Gradle projesi.
- <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzü</.localized_link>.

## Projeyi bağlayın

Gradle projesinin kök dizininden `tuist init` komutunu çalıştırın. **Integrate a Gradle project** seçeneğini belirleyin, ardından tarayıcıda kimlik doğrulaması yapın ve projenin sahibi olması gereken hesabı seçin.

```bash
tuist init
```

Bunu bir kodlama aracısı veya betik üzerinden yürütüyorsanız, önce `tuist auth login` komutunu çalıştırın (tarayıcı akışı Enter tuşuna basmanızı bekler), ardından etkileşimsiz formu kullanın:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist, depo köküne proje tanıtıcısıyla birlikte bir `tuist.toml` yazar ve bir `plugins { ... }` bloğu çıktılar. Bunu `settings.gradle.kts` dosyasının en üstüne yapıştırın:

<!-- @snippet: ../_gradle-plugin-block -->

`./gradlew help` ile temel kontrol yapın. Gradle hatasız yüklenmelidir. Eklentiyi bulamazsa, bloğun `build.gradle.kts` içinde değil `settings.gradle.kts` içinde olduğundan emin olun.

Aşağıdakilerin tümü isteğe bağlı ve bağımsızdır.

## Uzak derleme önbelleği

Gradle’ın yerel derleme önbelleği, görev çıktılarını onları üreten makinede saklar. Aynı dal üzerindeki iki geliştirici, önbelleği kendi `~/.gradle` dizinlerinde isabet eder, birbirinkinde değil; CI ise her işte taze, boş bir önbellekle karşılaşır.

Tuist uzak önbelleği, Gradle’ın makineler arasında zaten kullandığı aynı anahtar/değer protokolünü genişletir. Bir görevin çıktıları, onu ilk çalıştıran makinede yüklenir ve aynı girdilerle karşılaşan diğer herkes tarafından indirilir. `gradle.properties` içinde etkinleştirin:

```properties
org.gradle.caching=true
```

Ardından iki ortamda derleme yapın:

```bash
./gradlew clean build --build-cache --info
```

Önbelleklenebilir görevler ikinci çalıştırmada `FROM-CACHE` bildirir. Zaman içindeki isabet oranlarını görmek için panoda **Cache** bölümünü açın.

## Derleme içgörüsü

Gradle, bir derlemenin sonunda görev zamanlamalarını yayınlar ve `--profile` ile derleme başına bir HTML raporu yazar. Hiçbiri çalıştırmalar arasında toplama yapmaz. Bir dizi commit boyunca yavaşlayan bir görev, herhangi bir tek derlemenin raporunda her zamanki gibi görünür.

Eklenti uygulandıktan sonra `dev.tuist` eklentisi, her derleme için görev zamanlamalarını otomatik olarak panoya yükler. Ekstra yapılandırma gerekmez. Trendi görmek için sonraki `./gradlew build` işleminden sonra panoda **Builds** bölümünü açın.

## Test içgörüsü

Gradle’ın test raporları derleme başına `build/reports/tests/` altında bulunur. On CI çalıştırması boyunca aralıklı olarak başarısız olan bir test, herhangi bir raporda bir kez başarısız olmuş kararlı bir test gibi görünür.

Test içgörüsü, her `./gradlew test` çalıştırması için her görevin sonucunu ve süresini kaydeder ve sonuçları çalıştırmalar arasında ilişkilendirir. Kararsız testler, yavaş testler ve hatalar panonun **Tests** sekmesinde görünür. Kararsızlıklar biriktiğinde, birleşmeleri engellememeleri için bunları panodan karantinaya alın.

Eklenti ayrıca, bir derlemenin getirdiği test senaryolarını yeniden çalıştıran ve kararsız oldukları kanıtlandığında işaretleyen bir **stress-testing mode** destekler. Bunu `settings.gradle.kts` içindeki `tuist` uzantısına ekleyin:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Paket içgörüsü

Android Gradle Plugin, oluşturulan `.aab` boyutunu derleme çıktısında bildirir. Bu sayı dal ile birlikte kaybolur ve sürümler arasındaki boyutları karşılamak manuel bir muhasebe işidir. Play Console aynı sayıları bildirir, ancak yalnızca yapıt yüklendikten sonra.

Paket içgörüsü, her `.aab` (önerilen) veya `.apk` için kurulum ve indirme boyutlarını kaydeder ve dal başına eşik aşıldığında PR kontrolünü başarısız hale getirebilir. Bunu derleme adımınızın hemen ardından CI’nıza ekleyin:

```bash
tuist inspect bundle App.aab
```

Trendi görmek ve eşikleri yapılandırmak için panoda **Bundle insights → Android** bölümünü açın.

## Önizlemeler

Play Console’un dahili test kanalı, her paylaşımda inceleme ve yayılma gecikmesi ekler. Ham bir `.apk` dosyasını Slack veya e-posta üzerinden göndermek daha hızlıdır ancak belirli bir mesajın hangi derlemeye atıfta bulunduğunu takip etmeyi zorlaştırır.

Eklenti, ayrı bir CLI yüklemesi olmadan doğrudan bir uygulama varyantı oluşturup yayınlayabilir:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Bir `tuistShare<Variant>` görevi istemek, o çağrıyı yayınlamaya dahil eder; normal derlemeler asla önizleme yüklemez. Desteklenen APK’lar, imzalama ve kurulum için <.localized_link href="/guides/features/previews/gradle">Gradle previews</.localized_link> bölümüne bakın.

## Ekibi de dahil edin

Önbellek isabetleri, içgörüler ve stres testi, projeye bağlı kişi sayısı arttıkça katlanarak büyür. Takım arkadaşlarınızı panodaki hesap ayarlarından organizasyona davet edin ve kayıt sürecinin kişi başı `tuist auth login` yerine tek tıkla gerçekleşmesi için <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) kurulumunu yapın.

CI için kişisel bir giriş kullanmayın. CI sağlayıcınızın OIDC kimliğiyle kimlik doğrulaması yapın veya panoda **CI** ön ayarıyla bir hesap jetonu oluşturun ve bunu `TUIST_TOKEN` olarak ayarlayın. <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle plugin authentication</.localized_link> bölümüne bakın.

## Tam eklenti referansı

Burada ele alınan her şey, bir Gradle projesinde Tuist’ten değer elde etmek için gereken minimumdur. `tuist` uzantı bloğu, `stressNewTests` modu ve CI kimlik doğrulaması için yapılandırma seçenekleri [Install the Gradle plugin](https://tuist.dev/en/docs/guides/install-gradle-plugin) referansında yer alır.
