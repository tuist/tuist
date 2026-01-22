---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# Sunucu {#server}

Kaynak:
[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## Ne için kullanılır? {#what-it-is-for}

Sunucu, Tuist'in kimlik doğrulama, hesaplar ve projeler, önbellek depolama,
içgörüler, önizlemeler, Kayıt ve entegrasyonlar (GitHub, Slack ve SSO) gibi
sunucu tarafı özelliklerini destekler. Postgres ve ClickHouse ile Phoenix/Elixir
uygulamasıdır.

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB kullanımdan kaldırılmıştır ve yakında kaldırılacaktır. Şu anda,
yerel kurulum veya geçişler için buna ihtiyacınız varsa, [TimescaleDB kurulum
belgelerini](https://docs.timescale.com/self-hosted/latest/install/installation-macos/)
kullanın.
<!-- -->
:::

## Nasıl katkıda bulunabilirsiniz? {#how-to-contribute}

Sunucuya katkı yapmak için CLA (`server/CLA.md`) imzalanması gerekir.

### Yerel olarak ayarlayın {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Minimal secrets
export TUIST_SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

> [!NOT] Birinci taraf geliştiriciler, şifrelenmiş gizli bilgileri
> `priv/secrets/dev.key` adresinden yükler. Harici katkıda bulunanlar bu
> anahtara sahip olmayacaktır, ancak bu sorun değildir. Sunucu,
> `TUIST_SECRET_KEY_BASE` ile yerel olarak çalışmaya devam eder, ancak OAuth,
> Stripe ve diğer entegrasyonlar devre dışı kalır.

### Testler ve biçimlendirme {#tests-and-formatting}

- Testler: `mix test`
- Biçim: `mise run format`
