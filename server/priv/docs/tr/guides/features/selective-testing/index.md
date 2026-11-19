---
{
  "title": "Seçici test",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Seçici Test ile yalnızca son değişikliklerinizden etkilenen testleri çalıştırın, böylece sürekli entegrasyon geri bildirimi saniyeler içinde sunar."
}
---
# Seçici test {#selective-testing}

Projeler büyüdükçe, her push işlemi için tüm testleri çalıştırmak sürdürülebilir olmaktan çıkar. Tuist Seçici Test, son başarılı çalışmadan bu yana değişenlerden etkilenen testleri yalnızca çalıştırarak test süresini büyük ölçüde azaltır; bunu <.localized_link href="/guides/features/projects/hashing">karma algoritması</.localized_link> kullanarak yapar. Test süresini kısaltmanın diğer yolları, örneğin parçalara ayırma ve yavaş testleri düzeltme için bkz. [Yavaş testler](https://tuist.dev/solutions/slow-tests).

## Desteklenen derleme sistemleri {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

Diğer derleme sistemleri için destek planlanmaktadır.
