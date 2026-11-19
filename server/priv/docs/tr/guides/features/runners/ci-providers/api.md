---
{
  "title": "API",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Kendi Git altyapınız veya orkestratörünüzden Tuist Çalıştırıcılarında işleri çalıştırın: tek bir API isteğiyle bir iş oluşturun ve webhook'larla takip edin."
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

Kendi runner protokolü olmayan Git forjları, birleştirme kuyrukları ve ajan orkestratörleri işleri doğrudan Tuist Runner'larda çalıştırabilir. Tek bir istekle bir iş oluşturursunuz; seçtiğiniz <.localized_link href="/guides/features/runners/profiles">profil</.localized_link>e sahip bir Tuist makinesi commit'i çeker ve betiğinizi çalıştırır, ardından Tuist sonucu webhook uç noktanıza bildirir.

## Bir iş çalıştırın {#run-a-job}

1. **Bir hesap token'ı oluşturun** ve `account:runners:write` kapsamını verin:

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **İşi oluşturun.** Tipik bir çağrıcı bunu push hook'undan yapar; makinenin depoyu klonlamasına olanak tanıyan kısa ömürlü bir token kullanır:

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

   Yanıt, `workflow_job_id` içeren iştir. Tuist kontrol panelinizin **Runners** bölümünde hemen görünür ve profildeki bir makine boşaldığı anda başlar. Sıcak makineler genellikle saniyeler içinde başlatır.

3. **İşi takip edin.** Bir <.localized_link href="/guides/integrations/webhooks">webhook uç noktasını</.localized_link> `runner_job.started` ve `runner_job.completed` olaylarına abone edin. Tamamlanma olayı işin `conclusion` değerini taşır: `success`, `failure` veya `cancelled`. Ayrıca `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` ile yoklama yapabilir ve günlüğü `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs` adresinden okuyabilirsiniz.

## Bir git forjunu entegre edin {#integrate-a-git-forge}

Runner protokolü olmayan bir forj, küçük bir köprü üzerinden bağlanır; bu köprü forjün kendi hizmeti olabilir veya hook'larından çağırdığı bir fonksiyon olabilir:

1. **Push sırasında**, forjün push hook'u köprüye ulaşır. Köprü hook'u doğrular, commit'in hangi kontrolleri gerektirdiğine karar verir ve işin zaman aşımından sonra sona erecek şekilde depo için salt okunur bir klonlama token'ı basar.
2. **Her kontrol için**, köprü `idempotency_key` değerini `<repository>:<commit>:<check>` olarak ayarlayarak bir iş oluşturur; böylece yeniden gönderilen bir hook yeni bir şey oluşturmaz. Dönen `workflow_job_id` değerini saklar ve kontrolü forjde beklemede olarak işaretleyebilir.
3. **`runner_job.started` ve `runner_job.completed` durumunda**, köprü uç noktanın gizli anahtarıyla `Tuist-Signature` başlığını doğrular, kontrolü `workflow_job_id` veya `idempotency_key` ile bulur ve forjün commit durumunu `conclusion` ile günceller. Durumu Tuist kontrol panelindeki iş sayfasına bağlayabilir.
4. **Bir push bir commit'in yerine geçtiğinde**, köprü eski commit için oluşturduğu işleri iptal eder.

## İş nasıl çalışır {#how-the-job-runs}

Makine `commit_sha` değerini `repository_url` üzerinden HTTPS ile getirir. Sunucu bir commit'i SHA'sıyla sunmadığında, bunun yerine commit'i içermesi gereken `ref` değerini getirir. Varsa sağladığınız `clone_token`, yalnızca deponun host'una `Authorization: Bearer <token>` olarak gönderilir. Betiğinize veya iş günlüğüne asla ulaşmaz.

Betiğiniz, checkout kök dizininde, giriş kabuğunda Bash ile `set -eo pipefail` ayarıyla çalışır. Betik sıfırdan farklı bir durumla çıktığında veya `timeout_minutes` süresini aştığında iş başarısız olur; bu süre varsayılan olarak 60 dakikadır ve en fazla 360 dakikaya kadar çıkabilir. `env` ve `secrets` değerlerinin yanı sıra betik `CI=true`, `TUIST_JOB_ID`, `TUIST_JOB_NAME`, `TUIST_JOB_REPOSITORY_URL`, `TUIST_JOB_REF` ve `TUIST_JOB_COMMIT_SHA` değişkenlerini görür. `secrets` değerleri iş günlüğünde maskelenir.

## Yeniden denemeler ve idempotency {#idempotency}

Her işe, ne için olduğunu belirten bir `idempotency_key` verin; örneğin `<repository>:<commit>:<check>`. Hesabınızda zaten kullanılmış bir anahtarla yapılan istek, mevcut işi 201 yerine 200 durumuyla döndürür ve yeni bir şey oluşturmaz. Bu, push hook'unuzun isteği yinelenen iş riski olmadan bir yeniden deneme kuyruğuna aktarmasına olanak tanır.

Webhook teslimatları, uç noktanız 2xx durumuyla yanıt verene kadar yeniden denenir; bu nedenle bir olay birden fazla kez gelebilir. Yinelenmeleri önlemek için zarfın `id` değerini veya olay türüyle birlikte işin `workflow_job_id` değerini kullanın.

## Bir işi iptal edin {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

Henüz hiçbir makinenin başlatmadığı bir iş anında iptal edilir. Çalışan bir iş birkaç saniye içinde durur ve tamamlanma olayı `cancelled` olarak bildirilir. 24 saat içinde hiçbir makinenin başlatmadığı bir iş otomatik olarak iptal edilir.

## Önbellekleme ve güven {#trust}

Depoya push yapabilen herkes bir işin ne çalıştırdığını değiştirebilir, bu nedenle API işleri güvenilmez olarak değerlendirilir: hesabınızın paylaşılan <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimlerine</.localized_link> veya önbellek imzalama iznine erişemezler. Bir işin gizli anahtarları, betiği ve klonlama token'ı şifrelenmiş olarak saklanır ve iş tamamlandığında silinir.
