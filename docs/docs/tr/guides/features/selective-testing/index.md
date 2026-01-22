---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing to run only the tests that have changed."
}
---
# Seçmeli test {#selective-testing}

::: warning REQUIREMENTS
<!-- -->
- 1} tarafından oluşturulan bir projele</LocalizedLink>
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
  projesi</LocalizedLink>
<!-- -->
:::

Oluşturulmuş projele ile testleri seçerek çalıştırmak için `tuist test` komutunu
kullanın. Bu komut <LocalizedLink href="/guides/features/projects/hashing">
Xcode projenizi </LocalizedLink> önbelleği
<LocalizedLink href="/guides/features/cache#cache-warming">
ısıtmak</LocalizedLink> için yaptığı gibi hashler ve başarılı olduğunda,
gelecekteki çalıştırmalarda nelerin değiştiğini belirlemek için hashleri kalıcı
hale getirir.

Gelecekteki çalıştırmalarda `tuist test`, son başarılı test çalıştırmasından bu
yana yalnızca değişenleri çalıştırmak üzere testleri filtrelemek için hash'leri
şeffaf bir şekilde kullanır.

Örneğin, aşağıdaki bağımlılık grafiğini varsayalım:

- `FeatureA` testlere sahiptir `FeatureATests`, ve `Core'a bağlıdır`
- `FeatureB` testlere sahiptir `FeatureBTests`, ve `Core'a bağlıdır`
- `Core` testlere sahiptir `CoreTests`

`tuist test` bu şekilde davranacaktır:

| Eylem                  | Açıklama                                                            | Dahili durum                                                                                     |
| ---------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `tuist testi` çağrısı  | `CoreTests`, `FeatureATests` ve `FeatureBTests`                     | `FeatureATests`, `FeatureBTests` ve `CoreTests` hash'leri kalıcı hale getirilir                  |
| `ÖzellikA` güncellendi | Geliştirici, hedefin kodunu değiştirir.                             | Öncekiyle aynı                                                                                   |
| `tuist testi` çağrısı  | Hash değiştiği için `FeatureATests` adresindeki testleri çalıştırır | `FeatureATests` adresinin yeni hash'i kalıcı hale getirilir                                      |
| `Core` güncellendi     | Geliştirici, hedefin kodunu değiştirir.                             | Öncekiyle aynı                                                                                   |
| `tuist testi` çağrısı  | `CoreTests`, `FeatureATests` ve `FeatureBTests`                     | `FeatureATests` `FeatureBTests` ve `CoreTests` adreslerinin yeni hash'leri kalıcı hale getirilir |

`tuist test`, test paketinizi çalıştırırken derleme süresini iyileştirmek için
yerel veya uzak depolama alanınızdan çok sayıda ikili dosyayı kullanmak üzere
doğrudan ikili önbelleğe alma ile entegre olur. İkili önbellekleme ile seçmeli
test kombinasyonu, CI'nızda testleri çalıştırmak için gereken süreyi önemli
ölçüde azaltabilir.

## Kullanıcı Arayüzü Testleri {#ui-tests}

Tuist, UI testlerinin seçmeli test edilmesini destekler. Ancak, Tuist'in hedefi
önceden bilmesi gerekir. Yalnızca `hedef` parametresini belirtirseniz, Tuist UI
testlerini seçici olarak çalıştıracaktır, örneğin:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
