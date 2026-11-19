---
{
  "title": "Gradle önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Gradle derleme önbelleği yapıtlarını ekibiniz ve CI ile Tuist üzerinden paylaşın."
}
---
# Gradle önbelleği {#gradle-cache}

Tuist, derleme yapıtlarını uzaktan paylaşmak için [Gradle'ın yerleşik derleme önbelleği](https://docs.gradle.org/current/userguide/build_cache.html) ile entegre olan bir Gradle eklentisi sağlar. Bir görevin çıktıları zaten önbellekteyken, Gradle yürütmeyi atlar ve sonucu Tuist'in uzak önbelleğinden çeker; bu da ekibiniz ve CI ortamlarında derleme süresini kısaltır. Gradle'ın yerel ve uzak derleme önbelleklerinin güncellik kontrollerinden ve yapılandırma önbelleğinden nasıl farklı olduğunu öğrenmek için bkz. <.localized_link href="/references/concepts/build-cache#gradle">Derleme önbelleği nedir?</.localized_link>. Yavaş bir derlemenin hangi bölümünün önbellek tarafından ortadan kaldırıldığını ve projede öncelikle neyin düzeltilmesi gerektiğini öğrenmek için bkz. [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds).

<.localized_link href="/guides/install-gradle-plugin">Tuist Gradle eklentisi</.localized_link> yüklendikten sonra, `gradle.properties` dosyanızda Gradle'ın derleme önbelleğini de etkinleştirmeniz gerekir:

```properties
org.gradle.caching=true
```

Bu olmadan, Gradle derleme önbelleği alt sistemini — uzak bir önbellek yapılandırılmış olsa bile — etkinleştirmez ve tüm görevler önbelleğe isabet etmeden veya önbelleği doldurmadan yürütülür. Etkinleştirildiğinde, Gradle Tuist'i uzak derleme önbelleği olarak kullanır; önbellek isabetlerinde önbelleğe alınmış görev çıktılarını indirir ve görev yürütmesinden sonra bunları yükler.

## Önbellek yükleme politikası {#cache-upload-policy}

Varsayılan olarak, eklenti yapıtları hem indirir hem de uzak önbelleğe yükler. Yüklemeleri `buildCache` bloğundaki `push` seçeneğiyle kontrol edebilirsiniz:

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

Yaygın bir yaklaşım, yapıların tekrarlanabilir olduğu CI ortamından yalnızca orada yükleme yaparken yerel ortamları salt okunur tutmaktır:

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

Bu kurulumla, yerel derlemeler yükleme yapmadan önbelleğe alınmış yapıtlardan yararlanır; CI derlemeleri ise önbelleği ekibin geri kalanı için doldurur.

## Sürekli entegrasyon {#continuous-integration}

CI ortamları için, <.localized_link href="/guides/server/authentication#continuous-integration">Kimlik Doğrulama kılavuzu</.localized_link>'ndaki yöntemlerden birini kullanarak kimlik doğrulaması yapın. Sağlayıcıya özel CI örnekleri için <.localized_link href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzu</.localized_link>'na bakın.

### Yerel derleme önbelleğini devre dışı bırakma {#disabling-the-local-build-cache}

Gradle hem yerel hem de uzak bir derleme önbelleği tutar. Yerel derleme önbelleği, görev çıktılarını diskte `~/.gradle/caches/build-cache-1` altında saklar.

Tuist uzak derleme önbelleği olarak yapılandırıldığında, CI üzerinde yerel derleme önbelleğini devre dışı bırakmanız önerilir. Bu, CI çalıştırıcılarında gereksiz yapıtların depolanmasını önler ve derlemelerin ekibin geri kalanı için uzak önbelleği her zaman yeni girdilerle doldurmasını sağlar.

`settings.gradle.kts` içinde CI üzerinde Gradle'ın yerel derleme önbelleğini devre dışı bırakın:

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

Bu, yerel geliştirme için yerel derleme önbelleğini kullanılabilir tutarken CI üzerinde devre dışı bırakır; burada Tuist'in uzak önbelleği yapıt paylaşımını yönetir.

## Yapılandırma referansı {#configuration-reference}

`buildCache` bloğu şunları destekler:

| Seçenek | Tür | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | Uzak derleme önbelleğinin etkin olup olmadığı. |
| `push` | `Boolean` | `true` | Görev çıktılarının uzak önbelleğe yüklenip yüklenmeyeceği. |
| `allowInsecureProtocol` | `Boolean` | `false` | Güvenli olmayan HTTP bağlantılarına izin verilip verilmeyeceği. |
