---
{
  "title": "Seçici test",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Seçici Test ile yalnızca son değişikliklerinizden etkilenen testleri çalıştırın, böylece sürekli entegrasyon geri bildirimi saniyeler içinde sunar."
}
---
# Seçici test {#selective-testing}

Projeler büyüdükçe, her push işleminde tüm testleri çalıştırmak sürdürülebilir olmaktan çıkar. Tuist Seçici Test, son başarılı çalışmadan bu yana değişenlerden etkilenen testleri yalnızca çalıştırarak ve <.localized_link href="/guides/features/projects/hashing">hashing algoritması</.localized_link>nı kullanarak test süresini büyük ölçüde azaltır. Parçalama ve yavaş testleri düzeltme gibi test süresini kısaltmanın diğer yolları için [Yavaş testler](https://tuist.dev/solutions/slow-tests) sayfasına bakın.

## Desteklenen derleme sistemleri {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

Diğer derleme sistemleri için destek planlanmaktadır.
