---
{
  "title": "Gradle projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Bir Gradle projesini Tuist'e bağlayarak ortak uzak derleme önbelleği, CI'da derleme ve test içgörüleri, paket boyutu takibi ve önizleme bağlantılarının avantajlarından yararlanın."
}
---
# Gradle projesi {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

Mevcut bir Gradle projesini Tuist’e yönlendirmek için bu yolu izleyin. `dev.tuist` Gradle eklentisi, Gradle’ın yerel derleme önbelleğini Tuist’in uzak önbelliğine bağlar ve tek bir `./gradlew` komutunu değiştirmeden derleme ve test verilerini panoya yükler.

Aşağıdaki her bölüm, bugün eksik olanla başlar ve ardından bu boşluğu dolduran özelliği adım adım anlatır.

## Ön koşullar

- Bir `settings.gradle.kts` (veya `settings.gradle`) içeren bir Gradle projesi.
- <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzü</.localized_link>.

## Projeyi bağlayın

Gradle projesinin kök dizininden `tuist init` komutunu çalıştırın. **Gradle projesini entegre et** seçeneğini belirleyin, ardından tarayıcıda kimlik doğrulaması yapın ve projeye sahip olması gereken hesabı seçin.

```bash
tuist init
```

Bunu bir kodlama aracından veya betikten yürütüyorsanız, önce `tuist auth login` komutunu çalıştırın (tarayıcı akışı Enter tuşuna basmanızı bekler), ardından etkileşimsiz formu kullanın:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist, depo köküne proje tanıtıcısını içeren bir `tuist.toml` yazar ve bir `plugins { ... }` bloğu çıktılar. Bunu `settings.gradle.kts` dosyasının en üstüne yapıştırın:

<!-- @snippet: ../_gradle-plugin-block -->

`./gradlew help` ile temel kontrol yapın. Gradle hatasız yüklenmelidir. Eklentiyi bulamazsa, bloğun `build.gradle.kts` içinde değil `settings.gradle.kts` içinde olduğundan emin olun.

Aşağıdakilerin tümü isteğe bağlı ve bağımsızdır.

## Uzak derleme önbelleği

Gradle’ın yerel derleme önbelleği, görev çıktılarını onları üreten makinede saklar. Aynı dal üzerindeki iki geliştirici, önbelleğe kendi `~/.gradle` dizinlerinden erişir, birbirininkinden değil; CI ise her işte taze, boş bir önbellekle karşılaşır.

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

Gradle, bir derlemenin sonunda görev zamanlamalarını yayımlar ve `--profile` ile derleme başına HTML raporu yazar. Hiçbiri çalıştırmalar arasında toplama yapmaz. Bir dizi commit boyunca yavaşlayan bir görev, herhangi bir tek derlemenin raporunda her zamanki gibi görünür.

`dev.tuist` eklentisi, eklenti uygulandıktan sonra her derleme için görev zamanlamalarını otomatik olarak panoya yükler. Ekstra yapılandırma gerekmez. Eğilimi görmek için sonraki `./gradlew build` komutundan sonra panoda **Derlemeler** bölümünü açın.

## Test içgörüler

Gradle’ın test raporları derleme başına `build/reports/tests/` altında bulunur. On CI çalıştırması boyunca aralıklı olarak başarısız olan bir test, herhangi bir raporda bir kez başarısız olmuş kararlı bir test gibi görünür.

Test içgörüler, her `./gradlew test` çalıştırması için her görevin sonucunu ve süresini kaydeder ve sonuçları çalıştırmalar arasında ilişkilendirir. Kararsız testler, yavaş testler ve hatalar panonun **Testler** sekmesinde görünür. Kararsızlık biriktiğinde, birleşmeleri engellememeleri için bunları panodan karantinaya alın.

Eklenti ayrıca, bir derlemenin tanıttığı test durumlarını yeniden çalıştıran ve kararsız oldukları kanıtlandığında işaretleyen bir **stres testi modunu** destekler. Bunu `settings.gradle.kts` içindeki `tuist` uzantısına ekleyin:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Kod kapsamı

JaCoCo, test görevi başına ve makine başına bir kapsam raporu yazar. Bir commit’in CI işlerinin raporlarını birleştiren veya bir dalın kapsamının artıp azaldığını gösteren hiçbir şey yoktur.

Eklenti, JVM ve Android birim testlerinizi JaCoCo ile ölçebilir ve kapsamı her test çalıştırmasıyla yükleyebilir. Tuist, bir commit’in çalıştırmalarını (parçalar dahil) tek bir rakamda birleştirir. `settings.gradle.kts` içindeki `tuist` uzantısında etkinleştirin:

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

Commit ve dosya başına görmek için panoda **Kod Kapsamı** bölümünü açın. CI üzerinde bir commit’i tamamlamak ve Robolectric kurulumu için <.localized_link href="/guides/features/test-code-coverage/gradle">Gradle kod kapsamı</.localized_link> sayfasına bakın.

## Paket içgörüler

Android Gradle Plugin, üretilen `.aab` boyutunu derleme çıktısında bildirir. Bu sayı dal ile birlikte kaybolur ve sürümler arasındaki boyutları karşılamak manuel bir muhasebe işidir. Play Console aynı sayıları bildirir, ancak yalnızca yapıt yüklendikten sonra.

Paket içgörüler, her `.aab` (önerilen) veya `.apk` için kurulum ve indirme boyutlarını kaydeder ve dal başına eşik aşıldığında PR kontrolünü başarısız hale getirebilir. Bunu derleme adımınızdan hemen sonra CI’nize ekleyin:

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

Bir `tuistShare<Variant>` görevi istemek, o çağrıyı yayınlamaya dahil eder; normal derlemeler asla ön izleme yüklemez. Desteklenen APK’lar, imzalama ve kurulum için <.localized_link href="/guides/features/previews/gradle">Gradle ön izlemeleri</.localized_link> sayfasına bakın.

## Ekibi de dahil edin

Önbellek isabetleri, içgörüler ve stres testi, projeye bağlı kişi sayısı arttıkça katlanarak değer kazanır. Panodaki hesap ayarlarından takım arkadaşlarınızı organizasyona davet edin ve kayıt sürecinin kişi başı `tuist auth login` yerine tek tıklama olması için <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> (Google, Okta, Microsoft) kurulumunu yapın.

CI için kişisel giriş kullanmayın. CI sağlayıcınızın OIDC kimliğiyle kimlik doğrulaması yapın veya panoda **CI** ön ayarıyla bir hesap jetonu oluşturun ve bunu `TUIST_TOKEN` olarak ayarlayın. Ayrıntılar için <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle eklenti kimlik doğrulaması</.localized_link> sayfasına bakın.

## Eklenti başvuru kılavuzu

Burada ele alınan her şey, Gradle projesinde Tuist’ten değer elde etmek için gereken asgari düzeydir. `tuist` eklenti bloğu yapılandırma seçenekleri, `stressNewTests` modu ve CI kimlik doğrulaması hakkında bilgi [Gradle eklentisini yükle](https://tuist.dev/en/docs/guides/install-gradle-plugin) başvuru kılavuzunda yer alır.
