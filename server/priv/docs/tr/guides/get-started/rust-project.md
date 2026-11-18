---
{
  "title": "Rust projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Rust projenizi Tuist'e bağlayarak derlemeleri ve testleri (doctestler dahil) izleyin ve kararsız testleri bulun."
}
---
# Rust projesi {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## Ön Koşullar

- Cargo ile derlenen bir Rust projesi.
- Tuist CLI ve bir Tuist hesabı.

Tuist, mevcut Cargo projenizle çalışır. Bir Rust bağımlılığı eklemenize veya projenizin derlenme şeklini değiştirmenize gerek yoktur.

## Projeyi bağlayın

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> ve Rust'ı yükleyin. Derleme sistemi olarak **Cargo (Rust)** seçili şekilde panoda bir proje oluşturun. Ardından projeyi çalışma alanının kök `Cargo.toml` dosyasına ekleyin:

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo, `metadata` tablolarını yoksayar, bu nedenle bu durum projenizin derlenme şeklini değiştirmez. `[workspace]` tablosu olmayan tek bir kasa için bunun yerine `[package.metadata.tuist]` kullanın. Tablo, bir `tuist.toml` dosyasıyla aynı ayarları kabul eder; örneğin depo başka derleme sistemleri için de projeler içeriyorsa bunun yerine bunu kullanabilirsiniz. Her ikisi de varsa `tuist.toml` önceliklidir.

`tuist auth login` ile giriş yapın, ardından alıştığınız Cargo komutlarını Tuist üzerinden çalıştırın. CI ortamında, CI sağlayıcınızın OIDC kimliğiyle kimlik doğrulaması yapın veya `TUIST_TOKEN` değerini bir <.localized_link href="/guides/server/authentication#account-tokens">hesap belirteci</.localized_link> olarak ayarlayın. Bir yapılandırma dosyası eklemek yerine `TUIST_PROJECT` değerini de ayarlayabilir ve kendi kendine barındırılan bir sunucu kullanıyorsanız `TUIST_URL` değerini belirleyebilirsiniz.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Cargo'ya normalde ilettiğiniz aynı argümanları kullanın; özellikler, araç zincirleri ve test filtreleri dahil. Tuist bir rapor yükleyemese bile Cargo alışılmış çıktısını ve çıkış kodunu korur.

## Cargo yazmaya devam edin

[mise'nin komut sarmalayıcıları](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) etkinleştirilmişken bunu `mise.toml` dosyasına ekleyin:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Sarmalayıcıyı ekledikten sonra `mise reshim` komutunu çalıştırın. Ardından `cargo build`, `cargo check` ve `cargo test` komutlarını her zamanki gibi kullanabilirsiniz. Mise bunları sizin için Tuist üzerinden çalıştırır.

> [!TIP] Coding agents
> Kodlama ajanlarıyla çalışırken bu yararlıdır: `tuist` ön ekini eklemeleri hatırlatılmadan `cargo build` ve `cargo test` komutlarını çalıştırmaya devam edebilirler.

## Derleme önbelleği

`tuist cargo build`, uygun derlemeleri, bağımlılıkları ve derleme betiği çalıştırmalarını yerel olarak ve Kura'nın uzak önbelleği aracılığıyla otomatik olarak önbelleğe alır. Ek bir araç veya önbellek yapılandırmasına gerek yoktur. Önbellek deneyseldir, Apple silikonlu Mac'lerde doğrulanmıştır ve henüz her derlemeyi kapsamaz. Desteklenen derlemeler, kimlik doğrulama ve yeniden kullanımı nasıl doğrulayacağınız hakkında bilgi için <.localized_link href="/guides/features/cache/rust">Rust önbelleği</.localized_link> sayfasına bakın.

## Derleme içgörüler

Derlemelerinizin ne kadar sürdüğünü görmek ve yerel derlemeleri CI ile karşılaştırmak için panoda **Derlemeler** bölümünü açın. Derlenmesi en uzun süren kasaları bulmak ve uyarılarını ile hatalarını incelemek için bir derleme seçin.

Derleyici zamanlamaları kasalar içindir, tek tek kaynak dosyalar için değil. Bir derleme raporunu okuma hakkında daha fazla bilgi için <.localized_link href="/guides/features/build-insights/rust">Rust Derleme İçgörüler</.localized_link> sayfasına bakın.

## Test içgörüler

Testlerinizi her zamanki gibi çalıştırın:

```sh
tuist cargo test --workspace
```

Başarılı, başarısız ve yoksayılan testleri, doctest'ler dahil olmak üzere görmek için panoda **Testler** bölümünü açın. Cargo test paketi sürelerini bildirir, ancak kararlı libtest test başına zamanlamaları göstermez.

Yalnızca doctest'leri çalıştırmak için:

```sh
tuist cargo test --doc
```

Daha fazla bilgi için <.localized_link href="/guides/features/test-insights/rust">Rust Test İçgörüler</.localized_link> ve <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Kararsız Testler</.localized_link> sayfalarını okuyun.

## Ticari Markalar {#trademarks}

Rust ve Cargo, Rust Vakfı'nın ticari markalarıdır. Tuist, Rust Projesi veya Rust Vakfı ile bağlantılı değildir veya onlar tarafından onaylanmamıştır. Bu kılavuzlardaki Rust logosu © Rust Vakfı'na aittir, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) lisansı altında kullanılır ve sayfa temasına uygun tek bir renkte gösterilir.
