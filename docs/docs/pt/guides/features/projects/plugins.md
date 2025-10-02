---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Plugins {#plugins}

Os plugins são uma ferramenta para partilhar e reutilizar artefactos Tuist em
vários projectos. São suportados os seguintes artefactos:

- <LocalizedLink href="/guides/features/projects/code-sharing">Ajudantes de
  descrição de projectos</LocalizedLink> em vários projectos.
- <LocalizedLink href="/guides/features/projects/templates">Modelos</LocalizedLink>
  em vários projectos.
- Tarefas em vários projectos.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Modelo de
  acessório de recurso</LocalizedLink> em vários projectos

Note que os plugins foram concebidos para serem uma forma simples de alargar a
funcionalidade do Tuist. Por conseguinte, existem **algumas limitações a
considerar**:

- Um plugin não pode depender de outro plugin.
- Um plugin não pode depender de pacotes Swift de terceiros
- Um plugin não pode utilizar ajudantes de descrição de projeto do projeto que
  utiliza o plugin.

Se necessitar de mais flexibilidade, considere sugerir uma funcionalidade para a
ferramenta ou criar a sua própria solução com base na estrutura de geração do
Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Tipos de plugins {#plugin-types}

### Plugin auxiliar de descrição de projeto {#project-description-helper-plugin}

Um plugin auxiliar de descrição de projeto é representado por um diretório que
contém um ficheiro de manifesto `Plugin.swift` que declara o nome do plugin e um
diretório `ProjectDescriptionHelpers` que contém os ficheiros Swift auxiliares.

::: grupo de códigos
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
:::

### Plug-in de modelos de acessório de recurso {#resource-accessor-templates-plugin}

Se precisar de partilhar
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">acessores
de recursos sintetizados</LocalizedLink>, pode utilizar este tipo de plugin. O
plugin é representado por um diretório que contém um ficheiro de manifesto
`Plugin.swift` que declara o nome do plugin e um diretório
`ResourceSynthesizers` que contém os ficheiros de modelo de acessores de
recursos.


::: grupo de códigos
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
:::

O nome do modelo é a versão [camel
case](https://en.wikipedia.org/wiki/Camel_case) do tipo de recurso:

| Tipo de recurso       | Nome do ficheiro de modelo |
| --------------------- | -------------------------- |
| Cordas                | Strings.stencil            |
| Activos               | Activos.stencil            |
| Listas de imóveis     | Plists.stencil             |
| Fontes                | Tipos de letra.stencil     |
| Dados principais      | CoreData.stencil           |
| Criador de interfaces | InterfaceBuilder.stencil   |
| JSON                  | JSON.stencil               |
| YAML                  | YAML.stencil               |

Ao definir os sintetizadores de recursos no projeto, pode especificar o nome do
plugin para utilizar os modelos do plugin:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Tarefa do plugin <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [Os plug-ins de tarefa estão obsoletos. Consulte [esta publicação do
> blogue](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) se
> estiver à procura de uma solução de automatização para o seu projeto.

As tarefas são `$PATH`-exposed executables que são invocáveis através do comando
`tuist` se seguirem a convenção de nomenclatura `tuist-<task-name>`. Em versões
anteriores, o Tuist fornecia algumas convenções e ferramentas fracas em `tuist
plugin` para `construir`, `executar`, `testar` e `arquivar` tarefas
representadas por executáveis em Pacotes Swift, mas descontinuámos esta
funcionalidade uma vez que aumenta a carga de manutenção e a complexidade da
ferramenta.</task-name>

Se estiver a utilizar o Tuist para distribuir tarefas, recomendamos que crie o
seu
- Pode continuar a utilizar o `ProjectAutomation.xcframework` distribuído com
  cada versão do Tuist para ter acesso ao gráfico do projeto a partir da sua
  lógica com `let graph = try Tuist.graph()`. O comando usa o processo do
  sistema para executar o comando `tuist` e retornar a representação na memória
  do gráfico do projeto.
- Para distribuir tarefas, recomendamos incluir um binário gordo que suporte
  `arm64` e `x86_64` nos lançamentos do GitHub, e usar
  [Mise](https://mise.jdx.dev) como uma ferramenta de instalação. Para instruir
  o Mise sobre como instalar sua ferramenta, você precisará de um repositório de
  plugins. Você pode usar
  [Tuist's](https://github.com/asdf-community/asdf-tuist) como referência.
- Se der um nome à sua ferramenta `tuist-{xxx}` e os utilizadores puderem
  instalá-la executando `mise install`, podem executá-la invocando-a diretamente
  ou através de `tuist xxx`.

> [!NOTE] O FUTURO DA AUTOMAÇÃO DE PROJETOS Planejamos consolidar os modelos de
> `ProjectAutomation` e `XcodeGraph` em um único framework compatível com
> versões anteriores que expõe a totalidade do gráfico do projeto para o
> usuário. Além disso, vamos extrair a lógica de geração para uma nova camada,
> `XcodeGraph` que também pode ser usado a partir do seu próprio CLI. Pense
> nisso como construir seu próprio Tuist.

## Utilizar plug-ins {#utilizar-plugins}

Para utilizar um plug-in, terá de o adicionar ao ficheiro de manifesto
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
do seu projeto:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Se pretender reutilizar um plug-in em projectos que se encontram em diferentes
repositórios, pode enviar o seu plug-in para um repositório Git e referenciá-lo
no ficheiro `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Depois de adicionar os plug-ins, `tuist install` vai buscar os plug-ins a um
diretório de cache global.

> [NOTA] SEM RESOLUÇÃO DE VERSÃO Como deve ter notado, não fornecemos resolução
> de versão para plugins. Recomendamos o uso de tags Git ou SHAs para garantir a
> reprodutibilidade.

> [PLUGINS DE AJUDAS À DESCRIÇÃO DO PROJECTO Ao utilizar um plugin de ajudas à
> descrição do projeto, o nome do módulo que contém as ajudas é o nome do plugin
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
