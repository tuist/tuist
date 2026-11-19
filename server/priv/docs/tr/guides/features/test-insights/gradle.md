---
{
  "title": "Gradle Test İçgörileri",
  "titleTemplate": ":title · Test İçgörileri · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Gradle test analizlerini Tuist panosunda takip edin."
}
---
# Gradle test içgörüler {#gradle-test-insights}

> [!IMPORTANT]
> **Gereksinimler**
>
> - `dev.tuist` Gradle eklentisinin uygulanması; bkz. <.localized_link href="/guides/get-started/gradle-project">Gradle projesiyle başlayın</.localized_link>.

Tuist’in Gradle eklentisi, her test görevi çalıştırmasından sonra test sonuçlarını otomatik olarak yükler ve Tuist panosunda doğrudan test performansı ile kararsız testler hakkında görünürlük sağlar.

Eklenti uygulandığında test içgörüler otomatik olarak toplanır. Ek yapılandırma gerekmez.

Test içgörülerinize Tuist panosundan erişebilir ve zaman içinde nasıl değiştiğini görebilirsiniz:

![Test içgörülü pano](/images/guides/features/build-insights/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Eklenti, tüm Gradle `Test` görevlerinden sonuçları toplar; bunlar şunları içerir:
- Tekil test senaryosu geçme/kalma durumu ve süresi
- Test paketi ve sınıf yapısı
- Çalıştırmalar arasında kararsız test algılama

Testlerinizin hangi kodu çalıştırdığını da yüklemek için <.localized_link href="/guides/features/test-code-coverage/gradle">kod kapsamı</.localized_link>nı açın.

## Yükleme davranışını yapılandır {#configure-upload-behavior}

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

CI’da eklenti, bir test çalıştırmasını raporlarken checkout’un commit geçmişini de yükler: commit SHA’leri, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request’in temel dalının bulunduğu dallar. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgi, Tuist’e varsayılan dalınıza hangi commit’lerin geldiğini söyler; örneğin bir birleştirme kuyruğunun test ettiği commit’ler. Eklenti, checkout’ta zaten bulunan geçmişi okur ve checkout temel dala sahip değilse uzaktan en son commit’i ister (`git ls-remote`). Kod kapsamı dışında geçmiş çekilmez. Kod kapsamı etkin olduğunda, bir pull request’in nerede dallandığını bulmak ve Tuist’in zaten sahip olduğu commit’lere ulaşmak için dosya içerikleri olmadan sığ checkout derinleştirilir; böylece bir commit, üzerinde durduğu ebeveyni olmadan asla yüklenmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Uzak sunucuyla iletişim kurmadan yalnızca checkout’u okur. |
