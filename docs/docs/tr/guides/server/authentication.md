---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Kimlik Doğrulama {#authentication}

Sunucuyla etkileşim kurmak için CLI'nın [taşıyıcı kimlik
doğrulaması](https://swagger.io/docs/specification/authentication/bearer-authentication/)
kullanarak istekleri doğrulaması gerekir. CLI, kullanıcı, hesap veya OIDC jetonu
kullanarak kimlik doğrulamayı destekler.

## Kullanıcı olarak {#as-a-user}

CLI'yi yerel olarak makinenizde kullanırken, kullanıcı olarak kimlik doğrulaması
yapmanızı öneririz. Kullanıcı olarak kimlik doğrulaması yapmak için aşağıdaki
komutu çalıştırmanız gerekir:

```bash
tuist auth login
```

Komut sizi web tabanlı bir kimlik doğrulama akışına yönlendirecektir. Kimlik
doğrulaması yaptıktan sonra, CLI uzun ömürlü bir yenileme jetonu ve kısa ömürlü
bir erişim jetonunu `~/.config/tuist/credentials` altında depolayacaktır.
Dizindeki her dosya, kimlik doğrulaması yaptığınız etki alanını temsil eder ve
varsayılan olarak `tuist.dev.json` olmalıdır. Bu dizinde depolanan bilgiler
hassastır, bu nedenle **güvenli bir şekilde sakladığınızdan emin olun**.

CLI, sunucuya istek gönderirken kimlik bilgilerini otomatik olarak arar. Erişim
belirtecinin süresi dolmuşsa, CLI yenileme belirtecini kullanarak yeni bir
erişim belirteci alır.

## OIDC belirteçleri {#oidc-tokens}

OpenID Connect (OIDC) destekleyen CI ortamları için Tuist, uzun süreli gizli
bilgileri yönetmenize gerek kalmadan otomatik olarak kimlik doğrulaması
yapabilir. Desteklenen bir CI ortamında çalışırken, CLI otomatik olarak OIDC
token sağlayıcısını algılar ve CI tarafından sağlanan token'ı Tuist erişim
token'ıyla değiştirir.

### Desteklenen CI sağlayıcıları {#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### OIDC kimlik doğrulamasını ayarlama {#setting-up-oidc-authentication}

1. **Deponuzu Tuist'e bağlayın**: GitHub deponuzu Tuist projenize bağlamak için
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub entegrasyon
   kılavuzunu</LocalizedLink> izleyin.

2. **`tuist auth login` komutunu çalıştırın**: CI iş akışınızda, kimlik
   doğrulama gerektiren herhangi bir komuttan önce `tuist auth login` komutunu
   çalıştırın. CLI, CI ortamını otomatik olarak algılar ve OIDC kullanarak
   kimlik doğrulamasını gerçekleştirir.

Sağlayıcıya özgü yapılandırma örnekleri için
<LocalizedLink href="/guides/integrations/continuous-integration">Sürekli
Entegrasyon kılavuzuna</LocalizedLink> bakın.

### OIDC belirteci kapsamları {#oidc-token-scopes}

OIDC belirteçlerine, depoya bağlı tüm projelere erişim sağlayan `ci` kapsam
grubu verilir. `ci` kapsamının neleri içerdiği hakkında ayrıntılı bilgi için
[Kapsam grupları](#scope-groups) bölümüne bakın.

::: tip SECURITY BENEFITS
<!-- -->
OIDC kimlik doğrulama, uzun ömürlü tokenlerden daha güvenlidir çünkü:
- Döndürmek veya yönetmek için hiçbir sır yok
- Belirteçler kısa ömürlüdür ve tek tek iş akışı çalıştırmalarıyla sınırlıdır.
- Kimlik doğrulama, depo kimliğinizle bağlantılıdır.
<!-- -->
:::

## Hesap jetonları {#account-tokens}

OIDC'yi desteklemeyen CI ortamları için veya izinler üzerinde ayrıntılı kontrol
gerektiren durumlarda, hesap belirteçlerini kullanabilirsiniz. Hesap
belirteçleri, belirtecin hangi kapsamlara ve projelere erişebileceğini tam
olarak belirlemenizi sağlar.

### Hesap jetonu oluşturma {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

Komut aşağıdaki seçenekleri kabul eder:

| Seçenek      | Açıklama                                                                                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--scopes`   | Gerekli. Token'a izin verilecek kapsamların virgülle ayrılmış listesi.                                                                                       |
| `--name`     | Gerekli. Token için benzersiz bir tanımlayıcı (1-32 karakter, yalnızca alfasayısal, tire ve alt çizgi).                                                      |
| `--expires`  | İsteğe bağlı. Jetonun ne zaman sona ereceği. `30d` (gün), `6m` (ay) veya `1y` (yıl) gibi bir format kullanın. Belirtilmezse, jetonun süresi asla sona ermez. |
| `--projeler` | Token'ı belirli proje tanıtıcılarıyla sınırlandırın. Belirtilmediği takdirde token tüm projelere erişebilir.                                                 |

### Kullanılabilir kapsamlar {#available-scopes}

| Kapsam                    | Açıklama                                   |
| ------------------------- | ------------------------------------------ |
| `hesap:üyeler:okuma`      | Hesap üyelerini okuyun                     |
| `hesap:üyeler:yazma`      | Hesap üyelerini yönetme                    |
| `hesap:Kayıt:okuma`       | Swift package kayıt defterinden okuyun     |
| `hesap:Kayıt:yazma`       | Swift package kayıt defterine yayınlayın   |
| `proje:önizlemeler:okuma` | Önizlemeleri indirin                       |
| `project:previews:write`  | Önizlemeleri yükleyin                      |
| `project:admin:read`      | Proje ayarlarını okuyun                    |
| `project:admin:write`     | Proje ayarlarını yönetme                   |
| `project:cache:read`      | Önbelleğe alınmış ikili dosyaları indirin  |
| `project:cache:write`     | Önbelleğe alınmış ikili dosyaları yükleyin |
| `project:bundles:read`    | Paketleri görüntüle                        |
| `project:bundles:write`   | Paketleri yükleyin                         |
| `project:tests:read`      | Test sonuçlarını okuyun                    |
| `proje:testler:yazma`     | Test sonuçlarını yükleyin                  |
| `project:builds:read`     | Yapı analizlerini okuyun                   |
| `project:builds:write`    | Derleme analizlerini yükle                 |
| `project:runs:read`       | Komut okuma çalıştırma                     |
| `project:runs:write`      | Komut oluşturma ve güncelleme işlemleri    |

### Kapsam grupları {#scope-groups}

Kapsam grupları, tek bir tanımlayıcıyla birden fazla ilgili kapsamı atamak için
kullanışlı bir yol sağlar. Bir kapsam grubu kullandığınızda, içerdiği tüm
bireysel kapsamları içerecek şekilde otomatik olarak genişler.

| Kapsam Grubu | Dahil Edilen Kapsamlar                                                                                                                        |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`         | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### Sürekli Entegrasyon (CI) {#continuous-integration-ci}

OIDC'yi desteklemeyen CI ortamları için, CI iş akışlarınızı doğrulamak üzere
`ci` kapsam grubu ile bir hesap belirteci oluşturabilirsiniz:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

Bu, tipik CI işlemleri (önbellek, önizlemeler, paketler, testler, derlemeler ve
çalıştırmalar) için gerekli tüm kapsamları içeren bir belirteç oluşturur.
Oluşturulan belirteci CI ortamınızda gizli bir bilgi olarak saklayın ve
`TUIST_TOKEN` ortam değişkeni olarak ayarlayın.

### Hesap jetonlarını yönetme {#managing-account-tokens}

Bir hesabın tüm belirteçlerini listelemek için:

```bash
tuist account tokens list my-account
```

Adına göre bir jetonu iptal etmek için:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### Hesap jetonlarını kullanma {#using-account-tokens}

Hesap belirteçlerinin `TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
Gerektiğinde hesap jetonlarını kullanın:
- OIDC'yi desteklemeyen CI ortamlarında kimlik doğrulama
- Token'ın gerçekleştirebileceği işlemler üzerinde ince ayar kontrolü
- Bir hesap içindeki birden fazla projeye erişebilen bir belirteç
- Otomatik olarak süresi dolan zaman sınırlı belirteçler
<!-- -->
:::
