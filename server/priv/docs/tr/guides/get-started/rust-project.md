---
{
  "title": "Rust projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Rust projenizi Tuist’e bağlayarak derlemeleri ve testleri (doctestler dahil) izleyin ve kararsız testleri bulun."
}
---
# Rust projesi {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## Önkoşullar

- Cargo ile derlenen bir Rust projesi.
- Tuist CLI ve bir Tuist hesabı.

Tuist, mevcut Cargo projenizle çalışır. Bir Rust bağımlılığı eklemenize veya projenizin derlenme şeklini değiştirmenize gerek yoktur.

## Projeyi bağlayın

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> ve Rust'ı yükleyin. Derleme sistemi olarak **Cargo (Rust)** seçili şekilde panoda bir proje oluşturun. Ardından projeyi çalışma alanının kök dizinindeki `Cargo.toml` dosyasına ekleyin:

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo, `metadata` tablolarını yoksayar, bu nedenle bu durum projenizin derlenme şeklini değiştirmez. `[workspace]` tablosu bulunmayan tek bir kasa için bunun yerine `[package.metadata.tuist]` kullanın. Tablo, `tuist.toml` dosyasıyla aynı ayarları kabul eder; örneğin depoda başka derleme sistemleri için de projeler bulunduğunda bunu alternatif olarak kullanabilirsiniz. Her ikisi de mevcutsa `tuist.toml` önceliklidir.

`tuist auth login` ile giriş yapın, ardından alıştığınız Cargo komutlarını Tuist üzerinden çalıştırın. CI ortamında, CI sağlayıcınızın OIDC kimliğiyle kimlik doğrulaması yapın veya `TUIST_TOKEN` değerini bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonuna</.localized_link> ayarlayın. Yapılandırma dosyası eklemek yerine `TUIST_PROJECT` değerini de ayarlayabilir ve kendi barındırdığınız bir sunucu kullanıyorsanız `TUIST_URL` değerini belirtebilirsiniz.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Cargo'ya normalde ilettiğiniz aynı argümanları kullanın; özellikler, araç zincirleri ve test filtreleri dahildir. Tuist bir rapor yükleyemese bile Cargo alışıldık çıktısını ve çıkış kodunu korur.

## Cargo yazmaya devam edin

[mise'nin komut sarmalayıcıları](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) etkinleştirilmişken bunu `mise.toml` dosyasına ekleyin:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Sarmalayıcıyı ekledikten sonra `mise reshim` komutunu çalıştırın. Ardından `cargo build`, `cargo check` ve `cargo test` komutlarını her zamanki gibi kullanabilirsiniz. Mise bunları sizin adınıza Tuist üzerinden çalıştırır.

> [!TIP] Coding agents
> Bu, kodlama ajanlarıyla çalışırken faydalıdır: `tuist` ön ekini eklemeleri hatırlatılmadan `cargo build` ve `cargo test` komutlarını çalıştırmaya devam edebilirler.

## Derleme önbelleği

`tuist cargo build`, uygun derlemeleri, bağımlılıkları ve derleme betiği çalıştırmalarını yerel olarak ve Kura'nın uzak önbelleği aracılığıyla otomatik olarak önbelleğe alır. Ek bir araç veya önbellek yapılandırması gerekmez. Önbellek deneyseldir, Apple silicon Mac'lerde niteliklendirilmiştir ve henüz her derlemeyi kapsamaz. Desteklenen derlemeler, kimlik doğrulama ve yeniden kullanımı doğrulama hakkında bilgi için <.localized_link href="/guides/features/cache/rust">Rust önbelleği</.localized_link> sayfasına bakın.

## Derleme içgörüler

Derlemelerinizin ne kadar sürdüğünü görmek ve yerel derlemeleri CI ile karşılaştırmak için panoda **Derlemeler** bölümünü açın. En uzun süren kasaları bulmak ve uyarılarını ile hatalarını incelemek için bir derleme seçin.

Derleyici zamanlamaları kasalar içindir, tek tek kaynak dosyalar için değil. Derleme raporunu okuma hakkında daha fazla bilgi için <.localized_link href="/guides/features/build-insights/rust">Rust Derleme İçgörüler</.localized_link> sayfasına bakın.

## Test içgörüler

Testlerinizi her zamanki gibi çalıştırın:

```sh
tuist cargo test --workspace
```

Başarılı, başarısız ve yok sayılan testleri, dokümantasyon testleri dahil olmak üzere görmek için panoda **Testler** bölümünü açın. Cargo test paketi sürelerini bildirir, ancak kararlı libtest test başına zamanlamaları göstermez.

Yalnızca dokümantasyon testlerini çalıştırmak için:

```sh
tuist cargo test --doc
```

Daha fazla bilgi için <.localized_link href="/guides/features/test-insights/rust">Rust Test İçgörüler</.localized_link> ve <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Kararsız Testler</.localized_link> sayfalarını okuyun.

## Ticari markalar {#trademarks}

Rust ve Cargo, Rust Foundation'ın ticari markalarıdır. Tuist, Rust Projesi veya Rust Foundation ile bağlantılı değildir ya da onlar tarafından onaylanmamıştır. Bu kılavuzlardaki Rust logosu © Rust Foundation'a aittir, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) lisansı altında kullanılır ve sayfa temasına uygun tek bir renkte gösterilir.
