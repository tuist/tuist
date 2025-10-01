---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Criar um novo projeto {#criar um novo projeto}

A maneira mais simples de iniciar um novo projeto com o Tuist é usar o comando
`tuist init`. Este comando inicia uma CLI interactiva que o orienta na
configuração do seu projeto. Quando solicitado, certifique-se de selecionar a
opção para criar um "projeto gerado".

Você pode então <LocalizedLink href="/guides/features/projects/editing">editar o
projeto</LocalizedLink> executando `tuist edit`, e o Xcode abrirá um projeto
onde você pode editar o projeto. Um dos arquivos que são gerados é o
`Project.swift`, que contém a definição do seu projeto. Se estiver familiarizado
com o Swift Package Manager, pense nele como o `Package.swift`, mas com a
linguagem dos projetos do Xcode.

::: grupo de códigos
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```
:::

> [!NOTE] Nós intencionalmente mantemos a lista de modelos disponíveis curta
> para minimizar a sobrecarga de manutenção. Se você quiser criar um projeto que
> não represente uma aplicação, por exemplo, um framework, você pode usar `tuist
> init` como ponto de partida e então modificar o projeto gerado para atender às
> suas necessidades.

## Criar manualmente um projeto {#manually-creating-a-project}

Em alternativa, pode criar o projeto manualmente. Recomendamos que o faça apenas
se já estiver familiarizado com o Tuist e os seus conceitos. A primeira coisa
que terá de fazer é criar diretórios adicionais para a estrutura do projeto:

```bash
mkdir MyFramework
cd MyFramework
```

Em seguida, crie um ficheiro `Tuist.swift`, que configurará o Tuist e será
utilizado pelo Tuist para determinar o diretório raiz do projeto, e um
`Project.swift`, onde o seu projeto será declarado:

::: grupo de códigos
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
:::

> [IMPORTANTE] O Tuist utiliza o diretório `Tuist/` para determinar a raiz do
> seu projeto e, a partir daí, procura outros ficheiros de manifesto que estejam
> a abranger os diretórios. Recomendamos a criação desses ficheiros com o editor
> da sua preferência e, a partir daí, pode utilizar `tuist edit` para editar o
> projeto com o Xcode.
