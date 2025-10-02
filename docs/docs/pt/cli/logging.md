---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# Registo {#logging}

O CLI regista mensagens internamente para o ajudar a diagnosticar problemas.

## Diagnosticar problemas utilizando registos {#diagnose-issues-using-logs}

Se a invocação de um comando não produzir os resultados pretendidos, é possível
diagnosticar o problema inspeccionando os registos. A CLI encaminha os logs para
[OSLog](https://developer.apple.com/documentation/os/oslog) e para o sistema de
ficheiros.

Em cada execução, cria um ficheiro de registo em
`$XDG_STATE_HOME/tuist/logs/{uuid}.log` onde `$XDG_STATE_HOME` assume o valor
`~/.local/state` se a variável de ambiente não estiver definida.

Por predefinição, o CLI apresenta o caminho dos registos quando a execução é
encerrada inesperadamente. Se não o fizer, pode encontrar os registos no caminho
mencionado acima (ou seja, o ficheiro de registo mais recente).

> [IMPORTANTE] As informações sensíveis não são editadas, pelo que deve ter
> cuidado ao partilhar registos.

### Integração contínua {#diagnose-issues-using-logs-ci}

Na CI, onde os ambientes são descartáveis, pode querer configurar o seu pipeline
de CI para exportar os registos do Tuist. A exportação de artefatos é um recurso
comum entre os serviços de CI, e a configuração depende do serviço que você usa.
Por exemplo, em GitHub Actions, você pode usar a ação `actions/upload-artifact`
para carregar os logs como um artefato:

```yaml
name: Node CI

on: [push]

env:
  XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```
