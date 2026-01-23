---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Tuist'i yükleyin {#install-tuist}

Tuist CLI bir çalıştırılabilir dosyadan, dinamik çerçevelerden ve bir dizi
kaynaktan (örneğin şablonlar) oluşur. Tuist'i
[kaynaklar](https://github.com/tuist/tuist)'dan manuel olarak derleyebilmenize
rağmen, **geçerli bir kurulum sağlamak için aşağıdaki kurulum yöntemlerinden
birini kullanmanızı öneririz.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info
<!-- -->
Mise, farklı ortamlarda araçların deterministik sürümlerini sağlamak isteyen bir
ekip veya kuruluşsanız, [Homebrew](https://brew.sh) yerine kullanılması önerilen
bir alternatiftir.
<!-- -->
:::

Tuist'i aşağıdaki komutlardan herhangi birini kullanarak yükleyebilirsiniz:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Homebrew gibi araçların aksine, tek bir sürümü global olarak yükleyen ve
etkinleştiren **Mise,** sürümünün global olarak veya bir proje kapsamında
etkinleştirilmesini gerektirir. Bu, `mise use` komutunu çalıştırarak yapılır:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

Tuist'i [Homebrew](https://brew.sh) ve
[formüllerimiz](https://github.com/tuist/homebrew-tuist) kullanarak
yükleyebilirsiniz:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
Aşağıdaki komutu çalıştırarak, kurulumunuzun ikili dosyalarının tarafımızdan
oluşturulduğunu doğrulayabilirsiniz. Bu komut, sertifikanın ekibinin
`U6LC622NKF` olup olmadığını kontrol eder:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
