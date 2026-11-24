---
{
  "title": "Gradle Test Analizleri",
  "titleTemplate": ":title · Test Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Gradle test analizlerini Tuist kontrol panelinde takip edin."
}
---
# Gradle test içgörüleri {#gradle-test-insights}

> [!IMPORTANT]
> **Gereksinimler**
>
> - `dev.tuist` Gradle eklentisinin uygulanması; bkz. <.localized_link href="/guides/get-started/gradle-project">Gradle projesiyle başlayın</.localized_link>.

Tuist’in Gradle eklentisi, her test görevi çalıştırmasından sonra test sonuçlarını otomatik olarak yükler ve Tuist panosunda test performansı ile kararsız testler hakkında doğrudan görünürlük sağlar.

Eklenti uygulandığında test içgörüleri otomatik olarak toplanır. Ek yapılandırma gerekmez.

Test içgörülerinize Tuist panosundan erişebilir ve zaman içindeki değişimini görebilirsiniz:

![Test içgörülü pano](/images/guides/features/build-insights/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Eklenti, tüm Gradle `Test` görevlerinden sonuçları toplar; bunlar şunları içerir:
- Tekil test senaryosu geçme/kalma durumu ve süresi
- Test paketi ve sınıf yapısı
- Çalıştırmalar arasında kararsız test algılama

Testlerinizin hangi kodu yürüttüğünü de yüklemek için <.localized_link href="/guides/features/test-code-coverage/gradle">kod kapsamını</.localized_link> açın.

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

CI’da eklenti, bir test çalıştırmasını raporlarken checkout’un commit geçmişini de yükler: commit SHA’leri, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request’in taban dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgiler, Tuist’e varsayılan dalınıza hangi commit’lerin geldiğini söyler; örneğin birleştirme kuyruğunun test ettiği commit’ler. Eklenti, checkout’ta zaten bulunan geçmişi okur ve checkout taban dala sahip değilse en son commit’i uzak depodan ister (`git ls-remote`). Geçmişi çekmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Uzak depo ile iletişim kurmadan yalnızca checkout’u okur. |
