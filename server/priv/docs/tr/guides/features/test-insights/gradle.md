---
{
  "title": "Gradle Test Analizleri",
  "titleTemplate": ":title · Test Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Gradle test analizlerini Tuist panosunda takip edin."
}
---
# Gradle test içgörüleri {#gradle-test-insights}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/gradle-project">Bir Gradle projesiyle başlayın</.localized_link> bölümünde açıklandığı gibi `dev.tuist` Gradle eklentisi uygulanmış olmalıdır.

Tuist’in Gradle eklentisi, her test görevi çalıştırmasından sonra test sonuçlarını otomatik olarak yükler; böylece test performansını ve kararsız testleri doğrudan Tuist panosunda görebilirsiniz.

Eklenti uygulandığında test içgörüleri otomatik olarak toplanır. Ek yapılandırmaya gerek yoktur.

Test içgörülerinize Tuist panosundan erişebilir ve zaman içindeki değişimlerini takip edebilirsiniz:

![Test içgörülerini içeren pano](/images/guides/features/build-insights/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Eklenti, tüm Gradle `Test` görevlerinden sonuçları toplar; bunlar şunları içerir:
- Tekil test senaryolarının geçme/kalma durumu ve süresi
- Test paketi ve sınıf yapısı
- Çalıştırmalar arasında kararsız testlerin tespiti

## Yükleme davranışını yapılandırma {#configure-upload-behavior}

Varsayılan olarak:
- Test sonuçları yerel derlemeler için arka planda yüklenir.
- Test sonuçları, kısa ömürlü ajanlarda telemetri kaybını önlemek amacıyla CI çalıştırmaları için ön planda yüklenir.

Bu davranışı, `settings.gradle.kts` dosyanızdaki `tuist` bloğunda `uploadInBackground` kullanarak geçersiz kılabilirsiniz:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git geçmişi {#git-history}

CI ortamında eklenti, bir test çalıştırmasını raporlarken checkout’un commit geçmişini de yükler: commit SHA’leri, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request’in temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgi, Tuist’e hangi commit’lerin varsayılan dalınıza geldiğini söyler; örneğin birleştirme kuyruğunun test ettiği commit’ler. Eklenti, checkout’ta zaten bulunan geçmişi okur ve checkout temel dala sahip değilse uzaktan en son commit’ini ister (`git ls-remote`). Geçmiş çekmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Uzak sunucuyla iletişim kurmadan yalnızca checkout’u okur. |
