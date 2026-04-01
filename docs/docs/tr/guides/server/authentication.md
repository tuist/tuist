---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Kimlik Doğrulama {#authentication}

Sunucuyla etkileşim kurmak için CLI'nin istekleri [bearer kimlik
doğrulaması](https://swagger.io/docs/specification/authentication/bearer-authentication/)
kullanarak doğrulaması gerekir. CLI, kullanıcı, hesap veya OIDC belirteci
kullanarak kimlik doğrulamasını destekler.

## Bir kullanıcı olarak {#as-a-user}

CLI'yi makinenizde yerel olarak kullanırken, kullanıcı olarak kimlik doğrulaması
yapmanızı öneririz. Kullanıcı olarak kimlik doğrulaması yapmak için aşağıdaki
komutu çalıştırmanız gerekir:

```bash
tuist auth login
```

Komut sizi web tabanlı bir kimlik doğrulama akışına yönlendirecektir. Kimlik
doğrulaması tamamlandığında, CLI `~/.config/tuist/credentials` altında uzun
ömürlü bir yenileme jetonu ve kısa ömürlü bir erişim jetonu depolayacaktır.
Dizindeki her dosya, kimlik doğrulamasını yaptığınız etki alanını temsil eder;
bu, varsayılan olarak `tuist.dev.json` olmalıdır. Bu dizinde depolanan bilgiler
hassastır, bu nedenle **bunları güvenli bir şekilde sakladığınızdan emin olun**.

CLI, sunucuya istek gönderirken kimlik bilgilerini otomatik olarak arar. Erişim
jetonunun süresi dolmuşsa, CLI yenileme jetonunu kullanarak yeni bir erişim
jetonu alır.

## OIDC belirteçleri {#oidc-tokens}

OpenID Connect (OIDC) destekleyen CI ortamlarında, Tuist uzun süreli gizli
bilgileri yönetmenize gerek kalmadan otomatik olarak kimlik doğrulaması
yapabilir. Desteklenen bir CI ortamında çalıştırıldığında, CLI OIDC token
sağlayıcısını otomatik olarak algılar ve CI tarafından sağlanan tokeni bir Tuist
erişim tokeniyle değiştirir.

### Desteklenen CI sağlayıcıları {#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### OIDC kimlik doğrulamasını kurma {#setting-up-oidc-authentication}

1. **Deponuzu Tuist'e bağlayın**: GitHub deponuzu Tuist projenize bağlamak için
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub entegrasyon
   kılavuzunu</LocalizedLink> izleyin.

2. **`tuist auth login` komutunu çalıştırın**: CI iş akışınızda, kimlik
   doğrulama gerektiren herhangi bir komuttan önce `tuist auth login` komutunu
   çalıştırın. CLI, CI ortamını otomatik olarak algılayacak ve OIDC kullanarak
   kimlik doğrulaması yapacaktır.

Sağlayıcıya özgü yapılandırma örnekleri için
<LocalizedLink href="/guides/integrations/continuous-integration">Sürekli
Entegrasyon kılavuzuna</LocalizedLink> bakın.

### OIDC token kapsamları {#oidc-token-scopes}

OIDC belirteçlerine, depoya bağlı tüm projelere erişim sağlayan `ci` kapsam
grubu verilir. `ci` kapsamının neleri içerdiğine ilişkin ayrıntılar için [Kapsam
grupları](#scope-groups) bölümüne bakın.

::: tip SECURITY BENEFITS
<!-- -->
OIDC kimlik doğrulaması, uzun ömürlü jetonlardan daha güvenlidir çünkü:
- Döndürmek veya yönetmek için hiçbir sır yok
- Belirteçler kısa ömürlüdür ve tek tek iş akışı çalıştırmalarına özeldir
- Kimlik doğrulama, depo kimliğinizle bağlantılıdır
<!-- -->
:::

## Hesap belirteçleri {#account-tokens}

OIDC'yi desteklemeyen CI ortamları için veya izinler üzerinde ayrıntılı kontrol
gerektiren durumlarda hesap jetonlarını kullanabilirsiniz. Hesap jetonları,
jetonun hangi kapsamlara ve projelere erişebileceğini tam olarak belirlemenizi
sağlar.

### Hesap jetonu oluşturma {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

Komut aşağıdaki seçenekleri kabul eder:

| Seçenek          | Açıklama                                                                                                                                                    |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--kapsamlar`    | Gerekli. Jetonun verileceği kapsamların virgülle ayrılmış listesi.                                                                                          |
| `--name`         | Gerekli. Belirteç için benzersiz bir tanımlayıcı (1-32 karakter, yalnızca alfasayısal, tire ve alt çizgi).                                                  |
| `--süresi doldu` | İsteğe bağlı. Jetonun ne zaman sona ermesi gerektiği. `30d` (gün), `6m` (ay) veya `1y` (yıl) gibi biçimleri kullanın. Belirtilmezse, jeton asla sona ermez. |
| `--projeler`     | Token'ı belirli proje tanıtıcılarıyla sınırlayın. Belirtilmediği takdirde token tüm projelere erişebilir.                                                   |

### Kullanılabilir kapsamlar {#available-scopes}

| Kapsam                   | Açıklama                                   |
| ------------------------ | ------------------------------------------ |
| `account:members:read`   | Hesap üyelerini oku                        |
| `account:members:write`  | Hesap üyelerini yönet                      |
| `account:Kayıt:read`     | Swift package kayıt defterinden okuyun     |
| `account:Kayıt:write`    | Swift package kayıt defterine yayınlayın   |
| `project:previews:read`  | Önizlemeleri indirin                       |
| `project:previews:write` | Önizlemeleri yükleyin                      |
| `project:admin:read`     | Proje ayarlarını okuyun                    |
| `project:admin:write`    | Proje ayarlarını yönet                     |
| `project:cache:read`     | Önbelleğe alınmış ikili dosyaları indirin  |
| `project:cache:write`    | Önbelleğe alınmış ikili dosyaları yükleyin |
| `project:bundles:read`   | Paketleri görüntüle                        |
| `project:bundles:write`  | Paketleri yükleyin                         |
| `project:tests:read`     | Test sonuçlarını okuyun                    |
| `project:tests:write`    | Test sonuçlarını yükleyin                  |
| `project:builds:read`    | Derleme analizlerini okuyun                |
| `project:builds:write`   | Derleme analizlerini yükle                 |
| `project:runs:read`      | Read komutu çalışıyor                      |
| `project:runs:write`     | Komut çalıştırma oluşturma ve güncelleme   |

### Kapsam grupları {#scope-groups}

Kapsam grupları, tek bir tanımlayıcıyla birden fazla ilgili kapsamı atamak için
kullanışlı bir yol sağlar. Bir kapsam grubu kullandığınızda, grup otomatik
olarak genişleyerek içerdiği tüm bireysel kapsamları kapsar.

| Kapsam Grubu | Dahil Edilen Kapsamlar                                                                                                                        |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`         | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### Sürekli Entegrasyon {#continuous-integration}

OIDC'yi desteklemeyen CI ortamları için, CI iş akışlarınızı doğrulamak üzere
`ci` kapsam grubuna sahip bir hesap belirteci oluşturabilirsiniz:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

Bu, tipik CI işlemleri (önbellek, önizlemeler, paketler, testler, derlemeler ve
çalıştırmalar) için gerekli tüm kapsamları içeren bir belirteç oluşturur.
Oluşturulan belirteci CI ortamınızda bir gizli anahtar olarak saklayın ve bunu
`TUIST_TOKEN` ortam değişkeni olarak ayarlayın.

### Hesap belirteçlerini yönetme {#managing-account-tokens}

Bir hesabın tüm token'larını listelemek için:

```bash
tuist account tokens list my-account
```

Bir tokeni adına göre iptal etmek için:

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
Gerektiğinde hesap belirteçlerini kullanın:
- OIDC'yi desteklemeyen CI ortamlarında kimlik doğrulama
- Token'ın gerçekleştirebileceği işlemler üzerinde hassas kontrol
- Bir hesap içindeki birden fazla projeye erişebilen bir belirteç
- Otomatik olarak süresi dolan zaman sınırlı belirteçler
<!-- -->
:::
