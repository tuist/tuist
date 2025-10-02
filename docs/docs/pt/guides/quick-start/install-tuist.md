---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Instalar o Tuist {#install-tuist}

A CLI do Tuist consiste em um executável, estruturas dinâmicas e um conjunto de
recursos (por exemplo, modelos). Embora seja possível construir manualmente o
Tuist a partir de [os fontes](https://github.com/tuist/tuist), **recomendamos o
uso de um dos seguintes métodos de instalação para garantir uma instalação
válida.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info Mise é uma alternativa recomendada ao [Homebrew](https://brew.sh) se
for uma equipa ou organização que precisa de assegurar versões determinísticas
de ferramentas em diferentes ambientes ::::

Pode instalar o Tuist através de qualquer um dos seguintes comandos:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Note que, ao contrário de ferramentas como Homebrew, que instalam e ativam uma
única versão da ferramenta globalmente, **Mise requer a ativação de uma versão**
globalmente ou com escopo para um projeto. Isso é feito executando `mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

Pode instalar o Tuist utilizando [Homebrew](https://brew.sh) e [as nossas
fórmulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: dica VERIFICAR A AUTENTICIDADE DOS BINÁRIOS Pode verificar que os binários
da sua instalação foram construídos por nós executando o seguinte comando, que
verifica se a equipa do certificado é `U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
:::
