---
{
  "title": "Gradle Test Analizleri",
  "titleTemplate": ":title · Test Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Gradle test analizlerini Tuist panosunda takip edin."
}
---
# Gradle test içgörüler {#gradle-test-insights}

> [!IMPORTANT]
> **Gereksinimler**
>
> - `dev.tuist` Gradle eklentisinin uygulanması; bkz. <.localized_link href="/guides/get-started/gradle-project">Gradle projesiyle başlayın</.localized_link>.

Tuist'in Gradle eklentisi, her test görevi çalıştırmasından sonra test sonuçlarını otomatik olarak yükler ve Tuist panosunda test performansı ile kararsız testler hakkında doğrudan görünürlük sağlar.

Eklenti uygulandığında test içgörüleri otomatik olarak toplanır. Ek yapılandırma gerekmez.

Test içgörülerinize Tuist panosundan erişebilir ve zaman içindeki değişimlerini görebilirsiniz:

![Test içgörülü pano](/images/guides/features/build-insights/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Eklenti, tüm Gradle `Test` görevlerinden sonuçları toplar; bunlar şunları içerir:
- Tekil test senaryolarının geçme/kalma durumu ve süresi
- Test paketi ve sınıf yapısı
- Çalıştırmalar arasında kararsız testlerin tespiti

Testlerinizin hangi kodu yürüttüğünü de yüklemek için <.localized_link href="/guides/features/test-code-coverage/gradle">kod kapsamını</.localized_link> açın.

## Yükleme davranışını yapılandır {#configure-upload-behavior}

Varsayılan olarak:
- Yerel derlemeler için test sonuçları arka planda yüklenir.
- Kısa ömürlü ajanlarda telemetri kaybını önlemek amacıyla CI çalıştırmaları için test sonuçları ön planda yüklenir.

Bu davranışı, `settings.gradle.kts` dosyanızdaki `tuist` bloğunda `uploadInBackground` kullanarak geçersiz kılabilirsiniz:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git geçmişi {#git-history}

CI'da eklenti, bir test çalıştırmasını raporlarken checkout'un commit geçmişini de yükler: commit SHA'ları, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request'in temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgiler, Tuist'e varsayılan dalınıza hangi commit'lerin geldiğini söyler; örneğin birleştirme kuyruğunun test ettiği commit'ler. Eklenti, checkout'ta zaten bulunan geçmişi okur ve checkout temel dala sahip değilse en son commit'i uzak depodan ister (`git ls-remote`). Geçmişi çekmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Uzak depo ile iletişim kurmadan yalnızca checkout'u okur. |
