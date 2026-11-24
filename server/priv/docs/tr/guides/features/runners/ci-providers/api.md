---
{
  "title": "API",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Kendi Git altyapınızdan veya düzenleyicinizden Tuist Çalıştırıcılarında işleri çalıştırın: tek bir API isteğiyle bir iş oluşturun ve webhook'larla takip edin."
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

Kendi çalıştırıcı protokolü olmayan Git forjları, birleştirme kuyrukları ve ajan orkestratörleri işleri doğrudan Tuist Runners üzerinde çalıştırabilir. Tek bir istekle bir iş oluşturursunuz; seçtiğiniz <.localized_link href="/guides/features/runners/profiles">profil</.localized_link>deki bir Tuist makinesi commit’i çeker ve betiğinizi çalıştırır, Tuist ise sonucu webhook uç noktanıza bildirir.

## Bir iş çalıştırın {#run-a-job}

1. **Hesap belirteci oluşturun**, `account:runners:write` kapsamıyla:

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **İşi oluşturun.** Tipik bir çağrı yapan bunu push hook’undan yapar ve makinenin depoyu klonlamasına olanak tanıyan kısa ömürlü bir belirteç kullanır:

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

   Yanıt, `workflow_job_id` içeren iştir. Tuist kontrol panelinizin **Runners** bölümünde hemen görünür ve profildeki bir makine boş kaldığında başlar. Isınmış makineler genellikle saniyeler içinde başlatır.

3. **İşi takip edin.** Bir <.localized_link href="/guides/integrations/webhooks">webhook uç noktasını</.localized_link> `runner_job.started` ve `runner_job.completed` olaylarına abone edin. Tamamlanma olayı işin `conclusion` değerini taşır: `success`, `failure` veya `cancelled`. Ayrıca `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` ile yoklama yapabilir ve günlüğü `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs` üzerinden okuyabilirsiniz.

## Git forjunu entegre edin {#integrate-a-git-forge}

Çalıştırıcı protokolü olmayan bir forj, küçük bir köprü üzerinden bağlanır; bu köprü forjun kendi hizmeti olabilir veya hook’larından çağırdığı bir işlev olabilir:

1. **Push sırasında**, forjun push hook’u köprüye ulaşır. Köprü hook’u doğrular, commit’in hangi kontrolleri gerektirdiğine karar verir ve işin zaman aşımından sonra sona erecek şekilde depo için salt okunur bir klonlama belirteci oluşturur.
2. **Her kontrol için**, köprü `idempotency_key` değerini `<repository>:<commit>:<check>` olarak ayarlayarak bir iş oluşturur; böylece yeniden teslim edilen bir hook yeni bir şey oluşturmaz. Dönen `workflow_job_id` değerini saklar ve forjda kontrolü beklemede olarak işaretleyebilir.
3. **`runner_job.started` ve `runner_job.completed` olaylarında**, köprü uç noktanın gizli anahtarıyla `Tuist-Signature` başlığını doğrular, `workflow_job_id` veya `idempotency_key` ile kontrolü bulur ve forjun commit durumunu `conclusion` ile günceller. Durumu Tuist kontrol panelindeki iş sayfasına bağlayabilir.
4. **Bir push bir commit’i geçersiz kıldığında**, köprü eski commit için oluşturduğu işleri iptal eder.

## İş nasıl çalışır {#how-the-job-runs}

Makine `commit_sha` değerini `repository_url` üzerinden HTTPS ile alır. Sunucu bir commit’i SHA’sına göre sunmadığında, bunun yerine commit’i içermesi gereken `ref` değerini alır. Sağlarsanız `clone_token`, yalnızca deponun sunucusuna `Authorization: Bearer <token>` olarak gönderilir. Betiğinize veya iş günlüğüne asla ulaşmaz.

Betiğiniz, checkout kök dizininden, giriş kabuğunda Bash ile `set -eo pipefail` bayrağıyla çalışır. Betik sıfırdan farklı bir durum koduyla çıktığında veya `timeout_minutes` süresini aştığında iş başarısız olur; varsayılan 60 dakikadır ve en fazla 360 dakikaya kadar çıkabilir. `env` ve `secrets` dışında betik `CI=true`, `TUIST_JOB_ID`, `TUIST_JOB_NAME`, `TUIST_JOB_REPOSITORY_URL`, `TUIST_JOB_REF` ve `TUIST_JOB_COMMIT_SHA` değişkenlerini görür. `secrets` değerleri iş günlüğünde maskelenir.

## Yeniden denemeler ve idempotens {#idempotency}

Her işe ne için olduğunu adlandıran bir `idempotency_key` verin, örneğin `<repository>:<commit>:<check>`. Hesabınızda zaten kullanılan bir anahtarla yapılan istek, mevcut işi 201 yerine 200 durumuyla döndürür ve yeni bir şey oluşturmaz. Bu, push hook’unuzun isteği yinelenen iş riski olmadan yeniden deneme kuyruğuna aktarmasına olanak tanır.

Webhook teslimatları, uç noktanız 2xx durumuyla yanıt verene kadar yeniden denenir; bu nedenle bir olay birden fazla kez gelebilir. Yinelenmeleri önlemek için zarfın `id` değerini veya olay türüyle birlikte işin `workflow_job_id` değerini kullanın.

## Bir işi iptal et {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

Hiçbir makinenin başlatmadığı bir iş hemen iptal edilir. Çalışan bir iş birkaç saniye içinde durur ve tamamlanma olayı `cancelled` olarak raporlar. 24 saat içinde hiçbir makinenin başlatmadığı bir iş otomatik olarak iptal edilir.

## Önbellekleme ve güven {#trust}

Depoya push yapabilen herkes bir işin ne çalıştırdığını değiştirebilir; bu nedenle API işleri güvenilmeyen olarak değerlendirilir: hesabınızın paylaşılan <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimlerini</.localized_link> veya önbellek imzalama iznini almazlar. Bir işin gizli anahtarları, betiği ve klonlama belirteci şifrelenmiş olarak saklanır ve iş tamamlandığında silinir.
