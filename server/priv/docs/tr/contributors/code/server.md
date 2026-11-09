---
{
  "title": "Sunucu",
  "titleTemplate": ":title · Kod · Katkıda Bulunanlar · Tuist",
  "description": "Tuist Sunucusu'na katkıda bulunun."
}
---
# Sunucu {#server}

Kaynak: [github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## Ne işe yarar {#what-it-is-for}

Sunucu; kimlik doğrulama, hesaplar ve projeler, önbellek depolama, analizler, önizlemeler, kayıt defteri ve entegrasyonlar (GitHub, Slack ve SSO) gibi Tuist’in sunucu tarafı özelliklerini çalıştırır. Postgres ve ClickHouse kullanan bir Phoenix/Elixir uygulamasıdır.

## Nasıl katkıda bulunulur {#how-to-contribute}

Sunucuya yapılan katkılar için KLA’nın imzalanması gerekir (`server/CLA.md`).

### Yerel kurulum {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

Tarayıcınızda `http://localhost:8080` adresini açın. Geliştirme ortamında, giriş sayfasında sizi önceden oluşturulmuş hesapla (`tuistrocks@tuist.dev` / `tuistrocks`) oturan **Test kullanıcısı olarak giriş yap** düğmesi bulunur.

> [!NOTE]
> Birinci taraf geliştiriciler, fnox aracılığıyla 1Password’ten geliştirme gizli anahtarlarını yükler — `mise run dev`, sunucuyu `fnox exec` içinde çalıştırır (bkz. `server/fnox.toml`). Harici katkıda bulunanların 1Password erişimine ihtiyacı yoktur; sunucu bunun olmadan yerel olarak çalışır. OAuth, Stripe ve diğer üçüncü taraf entegrasyonlar devre dışı bırakılır, ancak temel işlevsellik çalışır.

### Yerel Helm testi {#local-helm-testing}

[kind](https://kind.sigs.k8s.io/) ve dahil edilen mise görevlerini kullanarak tam yığını makinenizde ayağa kaldırabilirsiniz. Bu işlem Docker görüntülerini yerel olarak derler, bir kind kümesi oluşturur, grafiği yükler ve tüm hizmetlerin bağlantı noktalarını otomatik olarak yönlendirir:

```bash
# Deploy everything (builds images from source)
mise run helm:up --license "YOUR_LICENSE_KEY"

# Include the observability stack (Grafana, Prometheus, Loki, Tempo)
mise run helm:up --license "YOUR_LICENSE_KEY" --observability

# Check status
mise run helm:status

# Tear down
mise run helm:down
```

**Gereksinimler:** `docker`, `kind`, `helm` ve `kubectl`.

### Testler ve biçimlendirme {#tests-and-formatting}

- Testler: `mix test`
- Biçimlendirme: `mise run format`
