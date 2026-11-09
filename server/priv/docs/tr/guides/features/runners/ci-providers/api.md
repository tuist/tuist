---
{
  "title": "API",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Kendi Git altyapınız veya orkestratörünüzden Tuist Çalıştırıcılarında işleri çalıştırın: tek bir API isteğiyle iş oluşturun ve webhook'larla takip edin."
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

Kendi çalıştırıcı protokolü olmayan Git forjları, birleştirme kuyrukları ve ajan orkestratörleri işleri doğrudan Tuist Runners üzerinde çalıştırabilir. Tek bir istekle bir iş oluşturursunuz; seçtiğiniz <.localized_link href="/guides/features/runners/profiles">profil</.localized_link>e sahip bir Tuist makinesi commit'i çeker ve betiğinizi çalıştırır, ardından Tuist sonucu webhook uç noktanıza bildirir.

## Bir iş çalıştırma {#run-a-job}

1. **Bir hesap belirteci oluşturun** ve `account:runners:write` kapsamını kullanın:

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **İşi oluşturun.** Tipik bir çağrı yapan bunu push hook'undan yapar ve makinenin depoyu klonlamasına izin veren kısa ömürlü bir belirteç kullanır:

   ```bash
   curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs \
     -H "Authorization: Bearer $TUIST_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "profile": "tuist-macos",
       "repository_url": "https://git.example.com/acme/app.git",
       "clone_token": "<short-lived token>",
       "commit_sha": "4f1c2d0e9b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d",
       "ref": "refs/heads/main",
       "name": "test",
       "script": "mise install\nmise run test",
       "secrets": { "SIGNING_KEY": "..." },
       "timeout_minutes": 30,
       "idempotency_key": "acme/app:4f1c2d0e:test"
     }'
   ```

   Yanıt, `workflow_job_id` içeren iştir. Tuist kontrol panelinizin **Runners** bölümünde hemen görünür ve profildeki bir makine boş kaldığında başlar. Sıcak makineler genellikle saniyeler içinde başlatır.

3. **İşi takip edin.** Bir <.localized_link href="/guides/integrations/webhooks">webhook uç noktasını</.localized_link> `runner_job.started` ve `runner_job.completed` olaylarına abone edin. Tamamlanan olay, işin `conclusion` değerini taşır: `success`, `failure` veya `cancelled`. Ayrıca `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` sorgulayabilir ve günlüğü `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs` adresinden okuyabilirsiniz.

## Bir git forjunu entegre etme {#integrate-a-git-forge}

Çalıştırıcı protokolü olmayan bir forj, forjun kendisine ait bir hizmet veya hook'larından çağırdığı bir fonksiyon olabilen küçük bir köprü üzerinden bağlanır:

1. **Push sırasında**, forjun push hook'u köprüye ulaşır. Köprü hook'u doğrular, commit'in hangi kontrolleri gerektirdiğine karar verir ve işin zaman aşımından sonra sona erecek şekilde depo için salt okunur bir klonlama belirteci oluşturur.
2. **Her kontrol için**, köprü `idempotency_key` değerini `<repository>:<commit>:<check>` olarak ayarlayarak bir iş oluşturur; böylece yeniden gönderilen bir hook yeni bir şey oluşturmaz. Dönen `workflow_job_id` değerini saklar ve kontrolü forjda beklemede olarak işaretleyebilir.
3. **`runner_job.started` ve `runner_job.completed` durumunda**, köprü uç noktanın gizli anahtarıyla `Tuist-Signature` başlığını doğrular, kontrolü `workflow_job_id` veya `idempotency_key` ile bulur ve forjun commit durumunu `conclusion` ile günceller. Durumu Tuist kontrol panelindeki iş sayfasına bağlayabilir.
4. **Bir push bir commit'in yerine geçtiğinde**, köprü eski commit için oluşturduğu işleri iptal eder.

## İşin nasıl çalıştığı {#how-the-job-runs}

Makine, `commit_sha` değerini `repository_url` üzerinden HTTPS ile alır. Sunucu bir commit'i SHA'sı ile sunmadığında, bunun yerine commit'i içermesi gereken `ref` değerini alır. Varsa sağladığınız `clone_token`, yalnızca deponun host'una `Authorization: Bearer <token>` olarak gönderilir. Betiğinize veya iş günlüğüne asla ulaşmaz.

Betiğiniz, checkout'un kök dizininde, giriş kabuğunda Bash ile `set -eo pipefail` kullanarak çalışır. Betik sıfırdan farklı bir durumla çıktığında veya varsayılanı 60 olan ve en fazla 360'a kadar çıkabilen `timeout_minutes` süresini aştığında iş başarısız olur. `env` ve `secrets` değerlerinin yanı sıra betik `CI=true`, `TUIST_JOB_ID`, `TUIST_JOB_NAME`, `TUIST_JOB_REPOSITORY_URL`, `TUIST_JOB_REF` ve `TUIST_JOB_COMMIT_SHA` değişkenlerini görür. `secrets` değerleri iş günlüğünde maskelenir.

## Yeniden denemeler ve idempotens {#idempotency}

Her işe, ne için olduğunu belirten bir `idempotency_key` verin, örneğin `<repository>:<commit>:<check>`. Hesabınızda zaten kullanılan bir anahtarla yapılan istek, mevcut işi 201 yerine 200 durumuyla döndürür ve yeni bir şey oluşturmaz. Bu, push hook'unuzun yinelenen iş riski olmadan isteği bir yeniden deneme kuyruğuna iletmesine olanak tanır.

Webhook teslimatları, uç noktanız 2xx durumuyla yanıt verene kadar yeniden denenir, bu nedenle bir olay birden fazla kez gelebilir. Yinelenmeleri önlemek için zarfın `id` değerini veya olay türüyle birlikte işin `workflow_job_id` değerini kullanın.

## Bir işi iptal etme {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

Hiçbir makinenin başlatmadığı bir iş anında iptal edilir. Çalışan bir iş birkaç saniye içinde durur ve tamamlanan olayı `cancelled` olarak bildirir. 24 saat içinde hiçbir makinenin başlatmadığı bir iş otomatik olarak iptal edilir.

## Önbellekleme ve güven {#trust}

Depoya push yapabilen herkes bir işin ne çalıştırdığını değiştirebilir, bu nedenle API işleri güvenilmez olarak değerlendirilir: hesabınızın paylaşılan <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimlerini</.localized_link> veya önbellek imzalama yetkisini almazlar. Bir işin gizli anahtarları, betiği ve klonlama belirteci şifrelenmiş olarak saklanır ve iş tamamlandığında silinir.
