---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# Configuração dinâmica {#dynamic-configuration}

Existem determinados cenários em que pode ser necessário configurar
dinamicamente o projeto no momento da geração. Por exemplo, talvez seja
necessário alterar o nome do aplicativo, o identificador do pacote ou o destino
da implantação com base no ambiente em que o projeto está sendo gerado. O Tuist
oferece suporte a isso por meio de variáveis de ambiente, que podem ser
acessadas nos arquivos de manifesto.

## Configuração através de variáveis de ambiente {#configuration-through-environment-variables}

O Tuist permite passar a configuração através de variáveis de ambiente que podem
ser acedidas a partir dos ficheiros de manifesto. Por exemplo:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Se quiser passar várias variáveis de ambiente, basta separá-las com um espaço.
Por exemplo:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Ler as variáveis de ambiente a partir de manifestos {#reading-the-environment-variables-from-manifests}

As variáveis podem ser acedidas utilizando o tipo
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>.
Quaisquer variáveis que sigam a convenção `TUIST_XXX` definidas no ambiente ou
passadas ao Tuist aquando da execução de comandos serão acessíveis utilizando o
tipo `Environment`. O exemplo a seguir mostra como acessamos a variável
`TUIST_APP_NAME`:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

O acesso a variáveis devolve uma instância do tipo `Environment.Value?` que pode
assumir qualquer um dos seguintes valores:

| Caso              | Descrição                                                        |
| ----------------- | ---------------------------------------------------------------- |
| `.string(String)` | Utilizado quando a variável representa uma cadeia de caracteres. |

Também pode obter a variável string ou booleana `Environment` utilizando um dos
métodos auxiliares definidos abaixo. Estes métodos requerem a passagem de um
valor predefinido para garantir que o utilizador obtém sempre resultados
consistentes. Isto evita a necessidade de definir a função appName() definida
acima.

::: grupo de códigos

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
:::
