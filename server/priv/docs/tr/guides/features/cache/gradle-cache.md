---
{
  "title": "Gradle derleme önbelleği: CI ve ekibiniz için uzak bir önbellek kurun",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist eklentisi ve org.gradle.caching=true ile Gradle uzak derleme önbelleğini kurarak CI ve geliştiricilerin görevleri yeniden çalıştırmak yerine görev çıktılarını yeniden kullanmasını sağlayın."
}
---
# Gradle derleme önbelleği {#gradle-cache}

Tuist bir Gradle uzak derleme önbelleğidir: Gradle eklentisi, [Gradle'ın yerleşik derleme önbelleğini](https://docs.gradle.org/current/userguide/build_cache.html) paylaşımlı bir sunucuya bağlar; böylece CI ve her geliştirici makinesi görevleri yeniden çalıştırmak yerine görev çıktılarını yeniden kullanır. Bir görevin çıktıları zaten önbellekteyse Gradle yürütmeyi atlar ve sonucu Tuist'ten çeker; bu da ekibiniz ve CI ortamlarında derleme süresinden tasarruf sağlar. Tuist'in Gradle derlemelerine eklediği diğer özellikler (derleme içgörüler ve test içgörüler gibi) için bkz. [Tuist ile Gradle](https://tuist.dev/build-systems/gradle); Develocity ile karşılaştırıyorsanız bkz. [Develocity vs Tuist](https://tuist.dev/compare/develocity). Gradle'ın yerel ve uzak derleme önbelleklerinin güncellik kontrollerinden ve yapılandırma önbelleğinden nasıl farklı olduğunu öğrenmek için bkz. <.localized_link href="/references/concepts/build-cache#gradle">Derleme önbelleği nedir?</.localized_link>. Yavaş bir derlemenin hangi bölümünü önbelleğin ortadan kaldırdığını ve projede öncelikle neyi düzeltmeniz gerektiğini görmek için bkz. [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds).

<.localized_link href="/guides/install-gradle-plugin">Tuist Gradle eklentisi</.localized_link> kurulduktan sonra, Gradle'ın derleme önbelleğini `gradle.properties` dosyanızda da etkinleştirmeniz gerekir:

```properties
org.gradle.caching=true
```

Bu olmadan Gradle, derleme önbelleği alt sistemini etkinleştirmez — uzak önbellek yapılandırılmış olsa bile — ve tüm görevler önbelleğe isabet etmeden veya önbelleği doldurmadan yürütülür. Etkinleştirildiğinde Gradle, Tuist'i uzak derleme önbelleği olarak kullanır; önbellek isabetlerinde önbelleğe alınmış görev çıktılarını indirir ve görev yürütmesinden sonra bunları yükler.

## Önbellek yükleme politikası {#cache-upload-policy}

Varsayılan olarak eklenti, yapıtları hem uzak önbelleğe indirir hem de onları oraya yükler. Yüklemeleri `buildCache` bloğundaki `push` seçeneğiyle kontrol edebilirsiniz:

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

Yaygın bir yaklaşım, yapıtları yalnızca tekrarlanabilir derlemelerin yapıldığı CI'dan göndermek ve yerel ortamları salt okunur tutmaktır:

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

Bu kurulumla yerel derlemeler, yükleme yapmadan önbelleğe alınmış yapıtlardan yararlanırken CI derlemeleri önbelleği ekip geri kalanı için doldurur.

## Sürekli entegrasyon {#continuous-integration}

CI ortamları için <.localized_link href="/guides/server/authentication#continuous-integration">Kimlik Doğrulama kılavuzu</.localized_link>ndaki yöntemlerden birini kullanarak kimlik doğrulaması yapın. Sağlayıcıya özel CI örnekleri için <.localized_link href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzuna</.localized_link> bakın.

### Yerel derleme önbelleğini devre dışı bırakma {#disabling-the-local-build-cache}

Gradle hem yerel hem de uzak bir derleme önbelleğini korur. Yerel derleme önbelleği, görev çıktılarını diskte `~/.gradle/caches/build-cache-1` altında saklar.

Tuist uzak derleme önbelleği olarak yapılandırıldığında, CI'da yerel derleme önbelleğini devre dışı bırakmanız önerilir. Bu, CI çalıştırıcılarında gereksiz yapıtların depolanmasını önler ve derlemelerin her zaman ekip geri kalanı için yeni girdilerle uzak önbelleği doldurmasını sağlar.

CI'da Gradle'ın yerel derleme önbelleğini `settings.gradle.kts` içinde devre dışı bırakın:

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

Bu, yerel derleme önbelleğini yerel geliştirme için kullanılabilir tutarken CI'da devre dışı bırakır; CI'da yapıt paylaşımını Tuist'in uzak önbelleği yönetir.

## Yapılandırma referansı {#configuration-reference}

`buildCache` bloğu şunları destekler:

| Seçenek | Tür | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | Uzak derleme önbelleğinin etkin olup olmadığı. |
| `push` | `Boolean` | `true` | Görev çıktılarının uzak önbelleğe yüklenip yüklenmeyeceği. |
| `allowInsecureProtocol` | `Boolean` | `false` | Güvenli olmayan HTTP bağlantılarına izin verilip verilmeyeceği. |
