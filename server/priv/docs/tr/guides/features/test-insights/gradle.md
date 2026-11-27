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
> - `dev.tuist` Gradle eklentisi uygulanmış olmalıdır; ayrıntılar için bkz. <.localized_link href="/guides/get-started/gradle-project">Gradle projesiyle başlayın</.localized_link>.

Tuist’in Gradle eklentisi, her test görevi yürütmesinden sonra test sonuçlarını otomatik olarak yükler ve Tuist panosunda test performansı ile kararsız testler hakkında doğrudan görünürlük sağlar.

Eklenti uygulandığında test içgörüleri otomatik olarak toplanır. Ek yapılandırma gerekmez.

Test içgörülerinize Tuist panosundan erişebilir ve zaman içinde nasıl değiştiğini görebilirsiniz:

![Test içgörülü pano](/images/guides/features/build-insights/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Eklenti, tüm Gradle `Test` görevlerinden sonuçları toplar; bunlar şunları içerir:
- Tekil test senaryosu geçme/kalma durumu ve süresi
- Test paketi ve sınıf yapısı
- Çalıştırmalar arasında kararsız test tespiti

Testlerinizin hangi kodu yürüttüğünü de yüklemek için <.localized_link href="/guides/features/test-code-coverage/gradle">kod kapsamı</.localized_link>nı açın.

## Yükleme davranışını yapılandırma {#configure-upload-behavior}

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

CI’da eklenti, bir test çalıştırmasını raporladığında checkout’un commit geçmişini de yükler: commit SHA’leri, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request’in temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgiler, Tuist’e varsayılan dalınıza hangi commit’lerin geldiğini söyler; örneğin birleştirme kuyruğunun test ettiği commit’ler. Eklenti, checkout’un zaten sahip olduğu geçmişi okur ve checkout temel dala sahip olmadığında uzaktan en son commit’ini ister (`git ls-remote`). Kod kapsamı dışında geçmiş çekilmez. Kod kapsamı etkinse, sığ bir checkout dosya içerikleri olmadan derinleştirilir; böylece pull request’in nereden dallandığı bulunur ve Tuist’in zaten sahip olduğu commit’lere ulaşılır; bu sayede bir commit, üzerinde durduğu ebeveyni olmadan asla yüklenmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Yalnızca checkout’u okur, uzak sunucuya bağlanmaz. |
| `TUIST_GIT_BRANCH=<branch>` | Çalıştırmanın dalını adlandırır; CI sağlayıcısının ve checkout’un belirlediği bilgilerin önüne geçer. Tuist’in tanımadığı ve dal yerine bir commit checkout eden CI sistemlerinde bunu ayarlayın; aksi takdirde bu çalıştırmaların dalı olmaz. |
