---
{
  "title": "Gradle Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Gradle test analizlerini Tuist kontrol panelinde takip edin."
}
---
# Gradle test içgörüleri {#gradle-test-insights}

> [!IMPORTANT]
> **Gereksinimler**
>
> - `dev.tuist` Gradle eklentisi uygulanmış olmalıdır; ayrıntılar için <.localized_link href="/guides/get-started/gradle-project">Gradle projesiyle başlayın</.localized_link> bölümüne bakın.

Tuist'in Gradle eklentisi, her test görevi çalıştırmasından sonra test sonuçlarını otomatik olarak yükler ve Tuist panosunda test performansı ile kararsız testler hakkında doğrudan görünürlük sağlar.

Eklenti uygulandığında test içgörüleri otomatik olarak toplanır. Ek yapılandırma gerekmez.

Test içgörülerinize Tuist panosundan erişebilir ve zaman içindeki değişimini görebilirsiniz:

![Test içgörülerini içeren pano](/images/guides/features/build-insights/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Eklenti, tüm Gradle `Test` görevlerinden sonuçları toplar; bunlar şunları içerir:
- Tekil test senaryolarının geçme/kalma durumu ve süresi
- Test paketi ve sınıf yapısı
- Çalıştırmalar arasında kararsız test algılama

Testlerinizin hangi kodu yürüttüğünü de yüklemek için <.localized_link href="/guides/features/test-code-coverage/gradle">kod kapsamı</.localized_link> özelliğini açın.

## Yükleme davranışını yapılandırın {#configure-upload-behavior}

Varsayılan olarak:
- Test sonuçları yerel derlemeler için arka planda yüklenir.
- Test sonuçları, kısa ömürlü ajanlarda telemetri kaybını önlemek için CI çalıştırmalarında ön planda yüklenir.

Bu davranışı, `settings.gradle.kts` dosyanızdaki `tuist` bloğunda `uploadInBackground` kullanarak geçersiz kılabilirsiniz:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git geçmişi {#git-history}

CI üzerinde, eklenti bir test çalıştırmasını raporlarken checkout'un commit geçmişini de yükler: commit SHA'ları, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request'inin temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgi, Tuist'e hangi commit'lerin varsayılan dalınıza geldiğini söyler; örneğin bir birleştirme kuyruğunun test ettiği commit'ler. Eklenti, checkout'un zaten sahip olduğu geçmişi okur ve checkout temel dala sahip değilse uzaktan en son commit'i ister (`git ls-remote`). Geçmişi çekmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Yalnızca checkout'u okur, uzak sunucuyla iletişim kurmaz. |
