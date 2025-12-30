---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Kimlik Doğrulama {#authentication}

Sunucu ile etkileşime geçmek için CLI'nin [bearer
authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/)
kullanarak isteklerin kimliğini doğrulaması gerekir. CLI, kullanıcı olarak,
hesap olarak veya OIDC belirteci kullanarak kimlik doğrulamayı destekler.

## Bir kullanıcı olarak {#as-a-user}

CLI'yı makinenizde yerel olarak kullanırken, kullanıcı olarak kimlik doğrulaması
yapmanızı öneririz. Kullanıcı olarak kimlik doğrulaması yapmak için aşağıdaki
komutu çalıştırmanız gerekir:

```bash
tuist auth login
```

Komut sizi web tabanlı bir kimlik doğrulama akışına yönlendirecektir. Kimlik
doğrulaması yaptıktan sonra CLI, `~/.config/tuist/credentials` altında uzun
ömürlü bir yenileme belirteci ve kısa ömürlü bir erişim belirteci
depolayacaktır. Dizindeki her dosya, varsayılan olarak `tuist.dev.json` olması
gereken kimlik doğrulaması yaptığınız etki alanını temsil eder. Bu dizinde
saklanan bilgiler hassastır, bu nedenle **güvende tuttuğunuzdan emin olun**.

CLI, sunucuya istekte bulunurken kimlik bilgilerini otomatik olarak arayacaktır.
Erişim belirtecinin süresi dolmuşsa, CLI yeni bir erişim belirteci almak için
yenileme belirtecini kullanacaktır.

## OIDC belirteçleri {#oidc-tokens}

OpenID Connect'i (OIDC) destekleyen CI ortamları için Tuist, uzun ömürlü gizli
dizileri yönetmenize gerek kalmadan otomatik olarak kimlik doğrulaması
yapabilir. Desteklenen bir CI ortamında çalışırken, CLI otomatik olarak OIDC
token sağlayıcısını algılar ve CI tarafından sağlanan token'ı bir Tuist erişim
token'ı ile değiştirir.

### Desteklenen CI sağlayıcıları {#supported-ci-providers}

- GitHub Eylemleri
- CircleCI
- Bitrise

### OIDC kimlik doğrulamasını ayarlama {#setting-up-oidc-authentication}

1. **Deponuzu Tuist'e bağlayın**: GitHub deponuzu Tuist projenize bağlamak için
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub entegrasyon kılavuzunu</LocalizedLink> izleyin.

2. **tuist auth login`** komutunu çalıştırın: CI iş akışınızda, kimlik doğrulama
   gerektiren tüm komutlardan önce `tuist auth login` komutunu çalıştırın. CLI,
   CI ortamını otomatik olarak algılayacak ve OIDC kullanarak kimlik doğrulaması
   yapacaktır.

Sağlayıcıya özgü yapılandırma örnekleri için
<LocalizedLink href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzuna</LocalizedLink> bakın.

### OIDC belirteç kapsamları {#oidc-token-scopes}

OIDC belirteçlerine, depoya bağlı tüm projelere erişim sağlayan `ci` kapsam
grubu verilir. ` ci` kapsamının neleri içerdiği hakkında ayrıntılar için [Kapsam
grupları](#scope-groups) bölümüne bakın.

::: tip SECURITY BENEFITS
<!-- -->
OIDC kimlik doğrulaması uzun ömürlü belirteçlerden daha güvenlidir çünkü:
- Döndürülecek veya yönetilecek sır yok
- Belirteçler kısa ömürlüdür ve bireysel iş akışı çalıştırmalarına kapsamlıdır
- Kimlik doğrulama, depo kimliğinize bağlıdır
<!-- -->
:::

## Hesap belirteçleri {#account-tokens}

OIDC'yi desteklemeyen CI ortamları için veya izinler üzerinde ayrıntılı kontrole
ihtiyaç duyduğunuzda hesap belirteçlerini kullanabilirsiniz. Hesap belirteçleri,
belirtecin tam olarak hangi kapsamlara ve projelere erişebileceğini belirtmenize
olanak tanır.

### Hesap belirteci oluşturma {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

Komut aşağıdaki seçenekleri kabul eder:

| Opsiyon             | Açıklama                                                                                                                                                             |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--kapsamlar`       | Gerekli. Belirtecin verileceği kapsamların virgülle ayrılmış listesi.                                                                                                |
| `--name`            | Gerekli. Belirteç için benzersiz bir tanımlayıcı (1-32 karakter, yalnızca alfanümerik, tire ve alt çizgi).                                                           |
| `-- süresi doluyor` | İsteğe bağlı. Belirtecin süresinin ne zaman dolacağı. ` 30d` (gün), `6m` (ay) veya `1y` (yıl) gibi biçimleri kullanın. Belirtilmezse, belirtecin süresi asla dolmaz. |
| `--projeler`        | Belirteci belirli proje tanıtıcılarıyla sınırlayın. Belirtilmediği takdirde belirtecin tüm projelere erişimi vardır.                                                 |

### Mevcut kapsamlar {#available-scopes}

| Kapsam                   | Açıklama                                     |
| ------------------------ | -------------------------------------------- |
| `account:members:read`   | Hesap üyelerini okuyun                       |
| `hesap:üyeler:yaz`       | Hesap üyelerini yönetme                      |
| `account:registry:read`  | Swift paketi kayıt defterinden okuma         |
| `account:registry:write` | Swift paketi kayıt defterinde yayınlama      |
| `proje:önizleme:oku`     | Önizlemeleri indirin                         |
| `project:previews:write` | Önizlemeleri yükleyin                        |
| `project:admin:read`     | Proje ayarlarını okuma                       |
| `project:admin:write`    | Proje ayarlarını yönetme                     |
| `project:cache:read`     | Önbelleğe alınmış ikili dosyaları indirin    |
| `project:cache:write`    | Önbelleğe alınmış ikili dosyaları yükleme    |
| `project:bundles:read`   | Paketleri görüntüle                          |
| `project:bundles:write`  | Paketleri yükleyin                           |
| `project:tests:read`     | Test sonuçlarını okuyun                      |
| `project:tests:write`    | Test sonuçlarını yükleme                     |
| `project:builds:read`    | Yapı analizlerini okuyun                     |
| `project:builds:write`   | Yapı analizlerini yükle                      |
| `project:runs:read`      | Oku komutu çalışır                           |
| `project:runs:write`     | Komut çalıştırmaları oluşturma ve güncelleme |

### Kapsam grupları {#scope-groups}

Kapsam grupları, tek bir tanımlayıcı ile birden fazla ilgili kapsamı vermek için
uygun bir yol sağlar. Bir kapsam grubu kullandığınızda, otomatik olarak içerdiği
tüm bireysel kapsamları içerecek şekilde genişler.

| Kapsam Grubu | Dahil Edilen Dürbünler                                                                                                                        |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`         | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### Sürekli Entegrasyon (CI) {#continuous-integration-ci}

OIDC'yi desteklemeyen CI ortamlarında, CI iş akışlarınızın kimliğini doğrulamak
için `ci` kapsam grubuyla bir hesap belirteci oluşturabilirsiniz:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

Bu, tipik CI işlemleri (önbellek, önizlemeler, paketler, testler, derlemeler ve
çalıştırmalar) için gereken tüm kapsamlara sahip bir belirteç oluşturur.
Oluşturulan belirteci CI ortamınızda gizli olarak saklayın ve `TUIST_TOKEN`
ortam değişkeni olarak ayarlayın.

### Hesap belirteçlerini yönetme {#managing-account-tokens}

Bir hesaba ait tüm belirteçleri listelemek için:

```bash
tuist account tokens list my-account
```

Bir belirteci adıyla iptal etmek için:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### Hesap belirteçlerini kullanma {#using-account-tokens}

Hesap belirteçlerinin `TUIST_TOKEN` ortam değişkeni olarak tanımlanması
beklenir:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
İhtiyacınız olduğunda hesap jetonlarını kullanın:
- OIDC'yi desteklemeyen CI ortamlarında kimlik doğrulama
- Token'ın hangi işlemleri gerçekleştirebileceği üzerinde ince taneli kontrol
- Bir hesap içinde birden fazla projeye erişebilen bir token
- Otomatik olarak sona eren zaman sınırlı tokenlar
<!-- -->
:::
