---
{
  "title": "Rust projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Rust projenizi Tuist'e bağlayarak derlemeleri ve testleri (doctestler dahil) izleyin, kararsız testleri bulun."
}
---
# Rust projesi {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## Ön koşullar

- Cargo ile derlenen bir Rust projesi.
- Tuist CLI ve bir Tuist hesabı.

Tuist, mevcut Cargo projenizle çalışır. Bir Rust bağımlılığı eklemenize veya projenizin derlenme şeklini değiştirmenize gerek yoktur.

## Projeyi bağlayın

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> ve Rust'ı yükleyin. Panoda yapı sistemi olarak **Cargo (Rust)** seçili bir proje oluşturun. Depo kök dizininize bir `tuist.toml` dosyası ekleyin:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

`tuist auth login` ile giriş yapın, ardından alıştığınız Cargo komutlarını Tuist üzerinden çalıştırın. CI ortamında, CI sağlayıcınızın OIDC kimliğiyle kimlik doğrulaması yapın veya `TUIST_TOKEN` değerini bir <.localized_link href="/guides/server/authentication#account-tokens">hesap belirteci</.localized_link> olarak ayarlayın. Yapılandırma dosyası eklemek yerine `TUIST_PROJECT` değişkenini de ayarlayabilir ve kendi barındırdığınız bir sunucu kullanıyorsanız `TUIST_URL` değişkenini tanımlayabilirsiniz.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Cargo'ya normalde ilettiğiniz aynı argümanları kullanın; özellikler, araç zincirleri ve test filtreleri dahildir. Tuist bir rapor yükleyemese bile Cargo alışılmış çıktısını ve çıkış kodunu korur.

## Cargo yazmaya devam edin

[mise'nin komut sarmalayıcıları](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) etkinleştirildiğinde şunu `mise.toml` dosyasına ekleyin:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Sarmalayıcıyı ekledikten sonra `mise reshim` komutunu çalıştırın. Ardından `cargo build`, `cargo check` ve `cargo test` komutlarını her zamanki gibi kullanabilirsiniz. Mise bunları sizin için Tuist üzerinden çalıştırır.

> [!TIP] Coding agents
> Bu, kodlama ajanlarıyla çalışırken faydalıdır: `tuist` ön ekini eklemeleri hatırlatılmadan `cargo build` ve `cargo test` komutlarını çalıştırmaya devam edebilirler.

## Derleme önbelleği

`tuist cargo build`, uygun derlemeleri, bağımlılıkları ve derleme betiği çalıştırmalarını yerel olarak ve Kura'nın uzak önbelleği üzerinden otomatik olarak önbelleğe alır. Ek bir araç veya önbellek yapılandırmasına gerek yoktur. Önbellek deneyseldir, Apple silicon Mac'lerde doğrulanmıştır ve henüz her derlemeyi kapsamaz. Desteklenen derlemeler, kimlik doğrulama ve yeniden kullanımın nasıl doğrulanacağı hakkında bilgi için <.localized_link href="/guides/features/cache/rust">Rust önbelleği</.localized_link> sayfasına bakın.

## Derleme içgörüler

Panoda **Derlemeler** bölümünü açarak derlemelerinizin ne kadar sürdüğünü görün ve yerel derlemeleri CI ile karşılaştırın. En uzun süren crate'leri bulmak ve uyarılarını ve hatalarını incelemek için bir derleme seçin.

Derleyici zamanlamaları crate'ler içindir, tekil kaynak dosyalar için değil. Derleme raporunu okuma hakkında daha fazla bilgi için <.localized_link href="/guides/features/build-insights/rust">Rust Derleme İçgörüler</.localized_link> sayfasına bakın.

## Test içgörüler

Testlerinizi her zamanki gibi çalıştırın:

```sh
tuist cargo test --workspace
```

Panoda **Testler** bölümünü açarak geçen, başarısız olan ve yoksayılan testleri, doctest'ler dahil olmak üzere görüntüleyin. Cargo paket sürelerini bildirir, ancak kararlı libtest test başına zamanlamaları göstermez.

Yalnızca doctest'leri çalıştırmak için:

```sh
tuist cargo test --doc
```

Daha fazla bilgi için <.localized_link href="/guides/features/test-insights/rust">Rust Test İçgörüler</.localized_link> ve <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Kararsız Testler</.localized_link> sayfalarını okuyun.
