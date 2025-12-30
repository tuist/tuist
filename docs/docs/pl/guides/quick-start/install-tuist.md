---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Zainstaluj Tuist {#install-tuist}

Tuist CLI składa się z pliku wykonywalnego, dynamicznych frameworków i zestawu
zasobów (na przykład szablonów). Chociaż można ręcznie zbudować Tuist ze
[źródeł](https://github.com/tuist/tuist), **zalecamy użycie jednej z poniższych
metod instalacji, aby zapewnić prawidłową instalację.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

:: info
<!-- -->
Mise jest zalecaną alternatywą dla [Homebrew](https://brew.sh), jeśli jesteś
zespołem lub organizacją, która musi zapewnić deterministyczne wersje narzędzi w
różnych środowiskach.
<!-- -->
:::

Możesz zainstalować Tuist za pomocą jednego z poniższych poleceń:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Należy pamiętać, że w przeciwieństwie do narzędzi takich jak Homebrew, które
instalują i aktywują pojedynczą wersję narzędzia globalnie, **Mise wymaga
aktywacji wersji** globalnie lub w zakresie projektu. Odbywa się to poprzez
uruchomienie `mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

Możesz zainstalować Tuist używając [Homebrew](https://brew.sh) i [naszych
formuł](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: wskazówka WERYFIKACJA AUTENTYCZNOŚCI BINARII
<!-- -->
Możesz zweryfikować, czy pliki binarne Twojej instalacji zostały zbudowane przez
nas, uruchamiając następujące polecenie, które sprawdza, czy zespół certyfikatu
to `U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
