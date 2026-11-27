---
{
  "title": "Gradle eklentisini yükle",
  "titleTemplate": ":title · Kılavuzlar · Tuist",
  "description": "Tuist'in Gradle eklentisini projenize nasıl yükleyip yapılandıracağınızı öğrenin."
}
---
# Gradle eklentisini yükleyin {#install-the-gradle-plugin}

Tuist, Gradle projenizle entegre olan ve <.localized_link href="/guides/features/cache/gradle-cache">uzak derleme önbellekleme</.localized_link> ile <.localized_link href="/guides/features/build-insights/gradle">derleme içgörüler</.localized_link> gibi özellikleri etkinleştiren bir Gradle eklentisi sağlar. Bu kılavuz, eklentinin kurulumu ve yapılandırılması sürecinde size rehberlik eder.

Eklenti için Gradle 8.12.1 veya sonraki bir sürüm gereklidir.

## 1. Tuist'i başlatın {#initialize-tuist}

Aşağıdaki komutu Gradle proje kök dizininizde çalıştırın:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

Komut, kimlik doğrulama, bir Tuist projesi oluşturma veya seçme ve Gradle projeniz için yapılandırma oluşturma adımlarında size rehberlik edecektir.

## 2. Eklentiyi uygulayın {#apply-the-plugin}

`tuist init` komutunu çalıştırdıktan sonra, komut çıktısında belirtildiği üzere Tuist eklentisini `settings.gradle.kts` dosyanıza eklemeniz gerekir:

<!-- @snippet: ./_gradle-plugin-block -->

## 3. Ekibinizi ve sürekli entegrasyonu doğrulayın {#authenticate}

`tuist init` sizi yerel olarak doğrularken, takım arkadaşlarınızın ve <.localized_link href="/guides/integrations/continuous-integration">sürekli entegrasyon</.localized_link> ortamlarının ayrı ayrı kimlik doğrulaması yapması gerekir.

Her takım arkadaşı, makinelerindeki Tuist özelliklerine erişim sağlamak için aşağıdakini çalıştırmalıdır:

```bash
tuist auth login
```

Kendi sunucunuzda barındırılan veya yerel bir Tuist sunucusu kullanırken, `tuist.toml` içinde yapılandırılan aynı temel URL'yi iletin:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

Ana bilgisayar adı yazımını tutarlı tutun. Örneğin, `localhost` için kaydedilen bir oturum açma bilgisi, `127.0.0.1` için kaydedilenden ayrıdır.

Otomatik çalışanlar için, ortamınızda kimlik doğrulamayı yapılandırmak üzere <.localized_link href="/guides/server/authentication#continuous-integration">sürekli entegrasyon kimlik doğrulama kılavuzunu</.localized_link> takip edin.

## Yapılandırma önbelleği ve Yalıtılmış Projeler {#configuration-cache-and-isolated-projects}

Eklenti, Gradle'ın yapılandırma önbelleğini ve [Yalıtılmış Projeleri](https://docs.gradle.org/current/userguide/isolated_projects.html) destekler. Eklentiyi `settings.gradle.kts` içinde tutun; her alt projeye ayrı ayrı uygulamanız gerekmez.

Tuist bu özelliklerin hiçbirini otomatik olarak etkinleştirmez. Opt-in yapmak için `gradle.properties` dosyasına aşağıdakileri ekleyin:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

Derleme betikleriniz ve diğer eklentileriniz de bu özellikleri desteklemelidir. Gradle, yapılandırma önbelleğini depolarken uyumluluk sorunlarını bildirir.

## Ön izlemeleri yayınlayın {#publish-previews}

Android uygulama modülleri için eklenti `tuistShare<Variant>` görevlerini kaydeder:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Görev, tek bir imzalı APK'yı derler ve doğrular, ardından mevcut Tuist kimlik doğrulamanızla bunu yayınlar. Görevi çağırmak opt-in anlamına gelir: normal `assemble`, `build` ve test görevleri ön izlemeleri yayınlamaz. CLI yükleme adımı gerekmez. Uygunluk, önbellek yeniden oynatma ve hata davranışı için <.localized_link href="/guides/features/previews/gradle">Gradle ön izlemelerine</.localized_link> bakın.

## Yapılandırma referansı {#configuration-reference}

`settings.gradle.kts` içindeki `tuist` genişletme bloğunda aşağıdaki seçenekler kullanılabilir:

| Seçenek | Tür | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (isteğe bağlı) | `account/project` formatındaki proje tanımlayıcısı. Ayarlanmazsa, eklenti bunu `tuist.toml` dosyasından okur. |
| `url` | `String?` | `null` | Tuist sunucusunun temel URL'si. Ayarlanmazsa, varsayılan olarak `"https://tuist.dev"` veya `tuist.toml` içinde tanımlanan değer kullanılır. |
| `uploadInBackground` | `Boolean?` | `null` | Derleme ve test içgörülerinin arka planda yüklenip yüklenmeyeceği. `null` (varsayılan) olduğunda, yüklemeler yerel derlemeler için arka planda, sürekli entegrasyon çalışanlarında ise ön planda çalışır. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` veya `"enforce"`. Bir derlemenin eklediği test senaryolarını yeniden çalıştırır ve kararsız olduğu kanıtlananları işaretler; bkz. <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">yeni testlere stres testi uygulama</.localized_link>. Ayarlanmadığında kapalıdır. |
| `coverage.enabled` | `Boolean?` | `null` | JaCoCo ile test kapsamını ölçer ve her test çalıştırmasında yükler. Ayarlanmadığında kapalıdır. `TUIST_TEST_COVERAGE` ortam değişkeni bunu geçersiz kılar; bkz. <.localized_link href="/guides/features/test-code-coverage/gradle">Gradle kod kapsamı</.localized_link>. |

Bir `http://` URL'si kullanan yerel bir sunucu için, güvensiz protokole yalnızca o yerel yapılandırmada izin verin:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

Barındırılan veya diğer `https://` sunucuları için `allowInsecureProtocol` özelliğini etkinleştirmeyin.

> [!NOTE]
> **Tuist.toml**
>
> `project` (ve isteğe bağlı olarak `url`) yapılandırmanın önerilen yolu, proje kökünüzdeki bir `tuist.toml` dosyası aracılığıyladır. Bu sayede yapılandırma, Tuist komut satırı arayüzü ve Gradle eklentisi arasında paylaşılır. Gerekirse bu değerleri `settings.gradle.kts` içinde hala geçersiz kılabilirsiniz.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP vekil sunucusu {#http-proxy}

Ağınız giden trafiği bir HTTP vekil sunucusu üzerinden yönlendiriyorsa, <.localized_link href="/guides/integrations/http-proxy">HTTP vekil sunucusu kılavuzuna</.localized_link> bakın.

## Sonraki adımlar {#next-steps}

Eklenti yüklendikten ve yapılandırıldıktan sonra şunları etkinleştirebilirsiniz:

- Derleme yapıtlarını ekibiniz ve sürekli entegrasyon çalışanları arasında paylaşmak için <.localized_link href="/guides/features/cache/gradle-cache">Uzak derleme önbelleği</.localized_link>.
- Tuist panosunda görev sürelerini ve önbellek davranışını izlemek için <.localized_link href="/guides/features/build-insights/gradle">Derleme içgörüleri</.localized_link>.
- Test performansını izlemek ve kararsız testleri tespit etmek için <.localized_link href="/guides/features/test-insights/gradle">Test içgörüleri</.localized_link>.
- Kararsız testleri otomatik olarak tespit etmek, izlemek ve karantinaya almak için <.localized_link href="/guides/features/test-insights/flaky-tests">Kararsız testler</.localized_link>.
- Testlerinizin commit, proje ve dosya bazındaki kapsamını takip etmek için <.localized_link href="/guides/features/test-code-coverage/gradle">Kod kapsamı</.localized_link>.
