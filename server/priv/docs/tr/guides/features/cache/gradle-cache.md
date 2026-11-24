---
{
  "title": "Gradle önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Gradle derleme önbelleği yapıtlarını ekibiniz ve CI arasında paylaşın."
}
---
# Gradle önbelleği {#gradle-cache}

Tuist, derleme yapıtlarını uzaktan paylaşmak için [Gradle'ın yerleşik derleme önbelleği](https://docs.gradle.org/current/userguide/build_cache.html) ile entegre olan bir Gradle eklentisi sağlar. Bir görevin çıktıları zaten önbellekteyse, Gradle yürütmeyi atlar ve sonucu Tuist'in uzak önbelleğinden çeker; bu sayede ekibiniz ve CI ortamlarında derleme süresi tasarruf edilir. Gradle'ın yerel ve uzak derleme önbelleklerinin güncellik kontrollerinden ve yapılandırma önbelleğinden nasıl farklı olduğunu öğrenmek için bkz. <.localized_link href="/references/concepts/build-cache#gradle">Derleme önbelleği nedir?</.localized_link>. Yavaş bir derlemenin hangi bölümünün önbellekle ortadan kalktığını ve projede öncelikle neyin düzeltilmesi gerektiğini görmek için bkz. [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds).

<.localized_link href="/guides/install-gradle-plugin">Tuist Gradle eklentisi</.localized_link> kurulduktan sonra, `gradle.properties` dosyanızda Gradle'ın derleme önbelleğini de etkinleştirmeniz gerekir:

```properties
org.gradle.caching=true
```

Bu olmadan, Gradle derleme önbelleği alt sistemini etkinleştirmez — uzak bir önbellek yapılandırılmış olsa bile — ve tüm görevler önbelleğe isabet etmeden veya önbelleği doldurmadan yürütülür. Etkinleştirildiğinde, Gradle Tuist'i uzak derleme önbelleği olarak kullanır; önbellek isabetlerinde önbelleğe alınmış görev çıktılarını indirir ve görev yürütmesinden sonra bunları yükler.

## Önbellek yükleme politikası {#cache-upload-policy}

Varsayılan olarak, eklenti hem yapıtları uzak önbellekten indirir hem de oraya yükler. Yüklemeleri `buildCache` bloğundaki `push` seçeneğiyle kontrol edebilirsiniz:

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

Yaygın bir yaklaşım, yapıtları yalnızca tekrarlanabilir derlemelerin yapıldığı CI ortamından göndermek ve yerel ortamları salt okunur tutmaktır:

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

Bu kurulumla, yerel derlemeler yükleme yapmadan önbelleğe alınmış yapıtlardan yararlanır; CI derlemeleri ise ekibin geri kalanı için önbelleği doldurur.

## Sürekli entegrasyon {#continuous-integration}

CI ortamları için, <.localized_link href="/guides/server/authentication#continuous-integration">Kimlik Doğrulama kılavuzu</.localized_link>ndaki yöntemlerden birini kullanarak kimlik doğrulaması yapın. Sağlayıcıya özel CI örnekleri için <.localized_link href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzuna</.localized_link> bakın.

### Yerel derleme önbelleğini devre dışı bırakma {#disabling-the-local-build-cache}

Gradle hem yerel hem de uzak bir derleme önbelleğini yönetir. Yerel derleme önbelleği, görev çıktılarını diskte `~/.gradle/caches/build-cache-1` altında saklar.

Tuist uzak derleme önbelleği olarak yapılandırıldığında, CI üzerinde yerel derleme önbelleğini devre dışı bırakmanız önerilir. Bu, CI çalıştırıcılarında gereksiz yapıtların depolanmasını önler ve derlemelerin her zaman ekibin geri kalanı için yeni girdilerle uzak önbelleği doldurmasını sağlar.

CI üzerinde Gradle'ın yerel derleme önbelleğini `settings.gradle.kts` içinde devre dışı bırakın:

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

Bu, yerel geliştirme için yerel derleme önbelleğini kullanılabilir tutarken CI üzerinde devre dışı bırakır; burada Tuist'in uzak önbelleği yapıt paylaşımını üstlenir.

## Yapılandırma referansı {#configuration-reference}

`buildCache` bloğu şunları destekler:

| Seçenek | Tür | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | Uzak derleme önbelleğinin etkin olup olmadığı. |
| `push` | `Boolean` | `true` | Görev çıktılarının uzak önbelleğe yüklenip yüklenmeyeceği. |
| `allowInsecureProtocol` | `Boolean` | `false` | Güvenli olmayan HTTP bağlantılarına izin verilip verilmeyeceği. |
