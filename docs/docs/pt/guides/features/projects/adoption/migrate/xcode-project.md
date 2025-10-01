---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Migrar um projeto Xcode {#migrate-an-xcode-project}

A menos que você <LocalizedLink href="/guides/start/new-project">crie um novo
projeto usando o Tuist</LocalizedLink>, caso em que tudo é configurado
automaticamente, você terá que definir seus projetos no Xcode usando as
primitivas do Tuist. O quão tedioso é este processo, depende da complexidade dos
seus projectos.

Como provavelmente sabe, os projectos Xcode podem tornar-se confusos e complexos
ao longo do tempo: grupos que não correspondem à estrutura de diretórios,
ficheiros que são partilhados entre alvos, ou referências de ficheiros que
apontam para ficheiros não existentes (para mencionar alguns). Toda essa
complexidade acumulada torna difícil para nós fornecer um comando que migre o
projeto de forma confiável.

Além disso, a migração manual é um excelente exercício para limpar e simplificar
os seus projectos. Não só os programadores do seu projeto ficarão gratos por
isso, mas também o Xcode, que os processará e indexará mais rapidamente. Depois
de ter adotado totalmente o Tuist, este irá garantir que os projectos são
definidos de forma consistente e que permanecem simples.

Com o objetivo de facilitar esse trabalho, damos-lhe algumas orientações com
base no feedback que recebemos dos utilizadores.

## Criar andaime de projeto {#create-project-scaffold}

Em primeiro lugar, crie um andaime para o seu projeto com os seguintes ficheiros
Tuist:

::: grupo de códigos

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
:::

`Project.swift` é o ficheiro de manifesto onde definirá o seu projeto, e
`Package.swift` é o ficheiro de manifesto onde definirá as suas dependências. O
arquivo `Tuist.swift` é onde você pode definir as configurações do Tuist com
escopo de projeto para o seu projeto.

> [!TIP] NOME DO PROJETO COM SUFIXO -TUIST Para evitar conflitos com o projeto
> Xcode existente, recomendamos adicionar o sufixo `-Tuist` ao nome do projeto.
> Pode retirá-lo depois de ter migrado completamente o seu projeto para o Tuist.

## Construir e testar o projeto Tuist em CI {#build-and-test-the-tuist-project-in-ci}

Para garantir que a migração de cada alteração é válida, recomendamos que
estenda a sua integração contínua para construir e testar o projeto gerado pelo
Tuist a partir do seu ficheiro de manifesto:

```bash
tuist install
tuist generate
tuist build -- ...{xcodebuild flags} # or tuist test
```

## Extraia as definições de construção do projeto para os ficheiros `.xcconfig` {#extract-the-project-build-settings-into-xcconfig-files}

Extraia as definições de compilação do projeto para um ficheiro `.xcconfig` para
tornar o projeto mais simples e mais fácil de migrar. Você pode usar o seguinte
comando para extrair as configurações de compilação do projeto para um arquivo
`.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Em seguida, actualize o ficheiro `Project.swift` para apontar para o ficheiro
`.xcconfig` que acabou de criar:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

Em seguida, estenda seu pipeline de integração contínua para executar o seguinte
comando para garantir que as alterações nas configurações de compilação sejam
feitas diretamente nos arquivos `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Extrair dependências de pacotes {#extract-package-dependencies}

Extraia todas as dependências do seu projeto para o ficheiro
`Tuist/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

> [!TIP] TIPOS DE PRODUTO Você pode sobrescrever o tipo de produto para um
> pacote específico adicionando-o ao dicionário `productTypes` na estrutura
> `PackageSettings`. Por padrão, o Tuist assume que todos os pacotes são
> frameworks estáticos.


## Determinar a ordem de migração {#determine-the-migration-order}

Recomendamos migrar os alvos do que é mais dependente para o menos. Pode
utilizar o seguinte comando para listar os alvos de um projeto, ordenados pelo
número de dependências:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Comece a migrar os alvos do topo da lista, uma vez que são os que mais dependem
deles.


## Migrar alvos {#migrate-targets}

Migre os destinos um por um. Recomendamos fazer um pull request para cada
destino para garantir que as alterações sejam revisadas e testadas antes de
serem mescladas.

### Extrair as definições de compilação alvo para os ficheiros `.xcconfig` {#extract-the-target-build-settings-into-xcconfig-files}

Tal como fez com as definições de compilação do projeto, extraia as definições
de compilação de destino para um ficheiro `.xcconfig` para tornar o destino mais
simples e mais fácil de migrar. Pode utilizar o seguinte comando para extrair as
definições de compilação do alvo para um ficheiro `.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Defina o alvo no ficheiro `Project.swift` {#define-the-target-in-the-projectswift-file}

Definir o alvo em `Project.targets`:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

> [!NOTA] TARGETS DE TESTE Se o alvo tiver um alvo de teste associado, deve
> defini-lo no ficheiro `Project.swift` repetindo também os mesmos passos.

### Validar a migração de destino {#validate-the-target-migration}

Execute `tuist build` e `tuist test` para garantir que o projeto seja construído
e os testes passem. Além disso, pode utilizar
[xcdiff](https://github.com/bloomberg/xcdiff) para comparar o projeto Xcode
gerado com o existente para garantir que as alterações estão corretas.

### Repetir {#repetir}

Repita até que todos os destinos sejam totalmente migrados. Quando terminar,
recomendamos que actualize os seus pipelines CI e CD para construir e testar o
projeto utilizando os comandos `tuist build` e `tuist test` para beneficiar da
velocidade e fiabilidade que o Tuist proporciona.

## Resolução de problemas {#troubleshooting}

### Erros de compilação devido a ficheiros em falta. {Erros de compilação devido a ficheiros em falta}

Se os arquivos associados aos alvos do seu projeto Xcode não estiverem todos
contidos em um diretório do sistema de arquivos que representa o alvo, você pode
acabar com um projeto que não compila. Certifique-se de que a lista de ficheiros
após gerar o projeto com o Tuist corresponde à lista de ficheiros no projeto
Xcode e aproveite a oportunidade para alinhar a estrutura de ficheiros com a
estrutura de destino.
