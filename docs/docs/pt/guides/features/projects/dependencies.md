---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# Dependências {#dependências}

Quando um projeto cresce, é comum dividi-lo em vários alvos para partilhar
código, definir limites e melhorar os tempos de construção. Múltiplos alvos
significam definir dependências entre eles, formando um gráfico de dependências
**** , que pode incluir também dependências externas.

## Gráficos codificados pelo XcodeProj {#xcodeprojcodified-graphs}

Devido ao design do Xcode e do XcodeProj, a manutenção de um gráfico de
dependência pode ser uma tarefa tediosa e propensa a erros. Aqui estão alguns
exemplos dos problemas que você pode encontrar:

- Como o sistema de compilação do Xcode gera todos os produtos do projeto no
  mesmo diretório em dados derivados, os alvos podem ser capazes de importar
  produtos que não deveriam. As compilações podem falhar na CI, onde as
  compilações limpas são mais comuns, ou mais tarde, quando uma configuração
  diferente é usada.
- As dependências dinâmicas transitivas de um alvo precisam de ser copiadas para
  qualquer um dos diretórios que fazem parte da definição de compilação
  `LD_RUNPATH_SEARCH_PATHS`. Se não estiverem, o alvo não será capaz de as
  encontrar em tempo de execução. Isto é fácil de pensar e configurar quando o
  gráfico é pequeno, mas torna-se um problema à medida que o gráfico cresce.
- Quando um alvo liga um
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
  estático, o alvo precisa de uma fase de construção adicional para que o Xcode
  processe o pacote e extraia o binário correto para a plataforma e arquitetura
  actuais. Esta fase de compilação não é adicionada automaticamente, e é fácil
  esquecer-se de a adicionar.

Os exemplos acima são apenas alguns, mas há muitos mais com que nos deparámos ao
longo dos anos. Imagine se precisasse de uma equipa de engenheiros para manter
um gráfico de dependências e garantir a sua validade. Ou, pior ainda, que as
complexidades fossem resolvidas no momento da construção por um sistema de
construção de código fechado que não pode controlar ou personalizar. Parece-lhe
familiar? Esta é a abordagem que a Apple tomou com o Xcode e o XcodeProj e que o
Swift Package Manager herdou.

Acreditamos firmemente que o gráfico de dependência deve ser **explícito** e
**estático** porque só assim pode ser **validado** e **optimizado**. Com o
Tuist, o utilizador concentra-se em descrever o que depende do quê, e nós
tratamos do resto. As complexidades e os detalhes de implementação são
abstraídos de si.

Nas secções seguintes, aprenderá a declarar dependências no seu projeto.

> [VALIDAÇÃO DO GRÁFICO O Tuist valida o gráfico ao gerar o projeto para
> garantir que não existem ciclos e que todas as dependências são válidas.
> Graças a isto, qualquer equipa pode participar na evolução do gráfico de
> dependências sem se preocupar com a sua quebra.

## Dependências locais {#local-dependencies}

Os alvos podem depender de outros alvos no mesmo e em diferentes projectos, e em
binários. Ao instanciar um `Target`, você pode passar o argumento `dependencies`
com qualquer uma das seguintes opções:

- `Target`: Declara uma dependência com um alvo dentro do mesmo projeto.
- `Projeto`: Declara uma dependência com um alvo num projeto diferente.
- `Framework`: Declara uma dependência com uma estrutura binária.
- `Biblioteca`: Declara uma dependência com uma biblioteca binária.
- `XCFramework`: Declara uma dependência com um XCFramework binário.
- `SDK`: Declara uma dependência com um SDK do sistema.
- `XCTest`: Declara uma dependência com o XCTest.

> [!NOTE] CONDIÇÕES DE DEPENDÊNCIA Todo tipo de dependência aceita uma opção
> `condition` para vincular condicionalmente a dependência com base na
> plataforma. Por padrão, ele liga a dependência para todas as plataformas que o
> alvo suporta.

## Dependências externas {#external-dependencies}

O Tuist também lhe permite declarar dependências externas no seu projeto.

### Pacotes Swift {#swift-packages}

Os Pacotes Swift são nossa maneira recomendada de declarar dependências em seu
projeto. Você pode integrá-los usando o mecanismo de integração padrão do Xcode
ou usando a integração baseada no XcodeProj do Tuist.

#### Integração do Tuist baseada no XcodeProj {#tuists-xcodeprojbased-integration}

A integração padrão do Xcode, embora seja a mais conveniente, não tem a
flexibilidade e o controle necessários para projetos médios e grandes. Para
superar isso, a Tuist oferece uma integração baseada no XcodeProj que permite
integrar pacotes Swift no seu projeto usando os alvos do XcodeProj. Graças a
isso, podemos não só dar mais controlo sobre a integração, mas também torná-la
compatível com fluxos de trabalho como
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> e
<LocalizedLink href="/guides/features/test/selective-testing">selective test
runs</LocalizedLink>.

A integração do XcodeProj é mais provável de levar mais tempo para suportar
novos recursos do Swift Package ou lidar com mais configurações de pacotes. No
entanto, a lógica de mapeamento entre os pacotes Swift e os alvos do XcodeProj é
de código aberto e pode ser contribuída pela comunidade. Isso é contrário à
integração padrão do Xcode, que é de código fechado e mantido pela Apple.

Para adicionar dependências externas, terá de criar um `Package.swift` ou em
`Tuist/` ou na raiz do projeto.

::: grupo de códigos
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
:::

> [!TIP] CONFIGURAÇÕES DE PACOTES A instância `PackageSettings` envolvida numa
> diretiva de compilador permite-lhe configurar a forma como os pacotes são
> integrados. Por exemplo, no exemplo acima, ela é usada para substituir o tipo
> de produto padrão usado para pacotes. Por defeito, não deve precisar dela.

O ficheiro `Package.swift` é apenas uma interface para declarar dependências
externas, nada mais. É por isso que você não define nenhum alvo ou produto no
pacote. Depois de ter as dependências definidas, você pode executar o seguinte
comando para resolver e puxar as dependências para o diretório
`Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Como deve ter reparado, adoptamos uma abordagem semelhante à do
[CocoaPods](https://cocoapods.org)', em que a resolução de dependências é o seu
próprio comando. Isto dá controlo aos utilizadores sobre quando querem que as
dependências sejam resolvidas e actualizadas, e permite abrir o projeto no Xcode
e tê-lo pronto a compilar. Esta é uma área onde acreditamos que a experiência do
desenvolvedor fornecida pela integração da Apple com o Swift Package Manager
degrada-se com o tempo à medida que o projeto cresce.

A partir dos alvos do seu projeto, pode então fazer referência a essas
dependências utilizando o tipo de dependência `TargetDependency.external`:

::: grupo de códigos
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
:::

> [NOTA] NENHUM ESQUEMA GERADO PARA PACOTES EXTERNOS Os esquemas **** não são
> criados automaticamente para projetos de Pacotes Swift para manter a lista de
> esquemas limpa. Você pode criá-los através da UI do Xcode.

#### Integração predefinida do Xcode {#xcodes-default-integration}

Se pretender utilizar o mecanismo de integração predefinido do Xcode, pode
passar a lista `packages` ao instanciar um projeto:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

E depois referenciá-los a partir dos seus objectivos:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Para macros Swift e plug-ins de ferramentas de construção, é necessário utilizar
os tipos `.macro` e `.plugin`, respetivamente.

> [!WARNING] Plugins da ferramenta de compilação SPM Os plugins da ferramenta de
> compilação SPM devem ser declarados usando o mecanismo [integração padrão do
> Xcode](#xcode-s-default-integration), mesmo quando se usa a [integração
> baseada no XcodeProj](#tuist-s-xcodeproj-based-integration) do Tuist para as
> dependências do projeto.

Uma aplicação prática de um plugin de ferramenta de compilação SPM é a
realização de code linting durante a fase de compilação "Run Build Tool
Plug-ins" do Xcode. Num manifesto de pacote isto é definido da seguinte forma:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

Para gerar um projeto Xcode com o plug-in da ferramenta de compilação intacto,
tem de declarar o pacote no conjunto `packages` do manifesto do projeto e, em
seguida, incluir um pacote com o tipo `.plugin` nas dependências de um destino.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Cartago {#carthage}

Uma vez que [Carthage](https://github.com/carthage/carthage) produz `frameworks`
ou `xcframeworks`, pode executar `carthage update` para produzir as dependências
no diretório `Carthage/Build` e, em seguida, utilizar o tipo de dependência
`.framework` ou `.xcframework` target para declarar a dependência no seu
destino. Pode envolver isto num script que pode ser executado antes de gerar o
projeto.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING] CONSTRUIR E TESTAR Se construir e testar o seu projeto através de
> `tuist build` e `tuist test`, terá igualmente de garantir que as dependências
> resolvidas pelo Carthage estão presentes executando o comando `carthage
> update` antes de `tuist build` ou `tuist test` serem executados.

### CocoaPods {#cocoapods}

O [CocoaPods](https://cocoapods.org) espera um projeto Xcode para integrar as
dependências. Pode usar o Tuist para gerar o projeto, e depois executar `pod
install` para integrar as dependências criando um espaço de trabalho que contém
o seu projeto e as dependências dos Pods. Pode envolver isto num script que pode
ser executado antes de gerar o projeto.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING] As dependências CocoaPods não são compatíveis com fluxos de
> trabalho como `build` ou `test` que executam `xcodebuild` logo após a geração
> do projeto. Também são incompatíveis com o cache binário e o teste seletivo,
> uma vez que a lógica de impressão digital não tem em conta as dependências de
> Pods.

## Estático ou dinâmico {#estático-ou-dinâmico}

As estruturas e bibliotecas podem ser ligadas de forma estática ou dinâmica,
**uma escolha que tem implicações significativas em aspectos como o tamanho da
aplicação e o tempo de arranque**. Apesar de sua importância, essa decisão é
frequentemente tomada sem muita consideração.

A **regra geral** é que quer que o máximo de coisas possível sejam ligadas
estaticamente em compilações de lançamento para conseguir tempos de arranque
rápidos, e o máximo de coisas possível sejam ligadas dinamicamente em
compilações de depuração para conseguir tempos de iteração rápidos.

O desafio de mudar entre ligação estática e dinâmica em um projeto gráfico é que
não é trivial no Xcode porque uma mudança tem efeito cascata em todo o gráfico
(por exemplo, bibliotecas não podem conter recursos, frameworks estáticos não
precisam ser embutidos). A Apple tentou resolver o problema com soluções em
tempo de compilação como a decisão automática do Swift Package Manager entre
ligação estática e dinâmica, ou [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Entretanto, isso adiciona novas variáveis dinâmicas ao gráfico de compilação,
adicionando novas fontes de não-determinismo, e potencialmente causando algumas
funcionalidades como Swift Previews que dependem do gráfico de compilação para
se tornarem não confiáveis.

Felizmente, Tuist conceitualmente comprime a complexidade associada com a
mudança entre estático e dinâmico e sintetiza
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle
accessors</LocalizedLink> que são padrão entre os tipos de ligação. Em
combinação com
<LocalizedLink href="/guides/features/projects/dynamic-configuration">configurações
dinâmicas via variáveis de ambiente</LocalizedLink>, é possível passar o tipo de
ligação no momento da invocação e usar o valor em seus manifestos para definir o
tipo de produto de seus alvos.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Observe que o Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience">não usa a
conveniência por padrão através de configuração implícita devido aos seus
custos</LocalizedLink>. O que isto significa é que dependemos da configuração do
tipo de ligação e de quaisquer configurações de compilação adicionais que são
por vezes necessárias, como a [`-ObjC` linker
flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184),
para garantir que os binários resultantes estão corretos. Portanto, a posição
que tomamos é fornecer-lhe os recursos, normalmente sob a forma de documentação,
para tomar as decisões corretas.

> [EXEMPLO: ARQUITECTURA COMPOSTA Um Pacote Swift que muitos projectos integram
> é a [Arquitetura
> Composta](https://github.com/pointfreeco/swift-composable-architecture).
> Conforme descrito
> [aqui](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
> e na [seção de solução de problemas](#troubleshooting), será necessário
> definir a configuração de compilação `OTHER_LDFLAGS` para `$(inherited) -ObjC`
> ao vincular os pacotes estaticamente, que é o tipo de vinculação padrão do
> Tuist. Alternativamente, é possível substituir o tipo de produto para que o
> pacote seja dinâmico.

### Cenários {#scenarios}

Existem alguns cenários em que definir a ligação inteiramente como estática ou
dinâmica não é viável ou uma boa ideia. Segue-se uma lista não exaustiva de
cenários em que poderá ser necessário misturar ligação estática e dinâmica:

- **Aplicações com extensões:** Uma vez que as aplicações e as suas extensões
  necessitam de partilhar código, poderá ser necessário tornar esses alvos
  dinâmicos. Caso contrário, acabará por ter o mesmo código duplicado na
  aplicação e na extensão, fazendo com que o tamanho do binário aumente.
- **Dependências externas pré-compiladas:** Por vezes, são-lhe fornecidos
  binários pré-compilados que podem ser estáticos ou dinâmicos. Os binários
  estáticos podem ser agrupados em estruturas ou bibliotecas dinâmicas para
  serem ligados dinamicamente.

Ao fazer alterações no gráfico, o Tuist irá analisá-lo e exibir um aviso se
detetar um "efeito colateral estático". Este aviso tem o objetivo de ajudá-lo a
identificar problemas que podem surgir ao vincular um alvo estaticamente que
depende transitivamente de um alvo estático através de alvos dinâmicos. Esses
efeitos colaterais geralmente se manifestam como aumento do tamanho do binário
ou, no pior dos casos, travamentos em tempo de execução.

## Resolução de problemas {#troubleshooting}

### Dependências de Objective-C {#objectivec-dependencies}

Ao integrar dependências Objective-C, a inclusão de determinados sinalizadores
no destino de consumo pode ser necessária para evitar falhas de tempo de
execução, conforme descrito em [Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Uma vez que o sistema de compilação e o Tuist não têm forma de inferir se a flag
é necessária ou não, e uma vez que a flag vem com efeitos secundários
potencialmente indesejáveis, o Tuist não irá aplicar automaticamente qualquer
uma destas flags, e porque o Swift Package Manager considera `-ObjC` para ser
incluída através de uma `.unsafeFlag` a maioria dos pacotes não a pode incluir
como parte das suas definições de ligação predefinidas quando necessário.

Os consumidores de dependências de Objective-C (ou alvos internos de
Objective-C) devem aplicar os sinalizadores `-ObjC` ou `-force_load` quando
necessário, definindo `OTHER_LDFLAGS` nos alvos de consumo.

### Firebase e outras bibliotecas do Google {#firebase-other-google-libraries}

As bibliotecas de código aberto da Google - embora poderosas - podem ser
difíceis de integrar no Tuist, uma vez que utilizam frequentemente arquitetura e
técnicas não normalizadas na forma como são construídas.

Seguem-se algumas dicas que podem ser necessárias para integrar o Firebase e as
outras bibliotecas do Google para a plataforma Apple:

#### Garantir que `-ObjC` é adicionado a `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Muitas das bibliotecas da Google são escritas em Objective-C. Por este motivo,
qualquer alvo que consuma terá de incluir a etiqueta `-ObjC` na sua definição de
construção `OTHER_LDFLAGS`. Isso pode ser definido em um arquivo `.xcconfig` ou
especificado manualmente nas configurações do alvo dentro de seus manifestos
Tuist. Um exemplo:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Para mais informações, consulte a secção [Dependências
Objective-C](#objective-c-dependencies) acima.

#### Definir o tipo de produto para `FBLPromises` para estrutura dinâmica {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Algumas bibliotecas do Google dependem de `FBLPromises`, outra das bibliotecas
do Google. Poderá deparar-se com uma falha que menciona `FBLPromises`, com um
aspeto semelhante a este:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Definir explicitamente o tipo de produto de `FBLPromises` para `.framework` no
seu ficheiro `Package.swift` deverá resolver o problema:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### Fuga de dependências estáticas transitivas através de `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

Quando uma estrutura ou biblioteca dinâmica depende de outras estáticas através
de `import StaticSwiftModule`, os símbolos são incluídos no `.swiftmodule` da
estrutura ou biblioteca dinâmica, potencialmente
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">causando
falha na compilação</LocalizedLink>. Para evitar isso, você terá que importar a
dependência estática usando
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal
import`</LocalizedLink>:

```swift
internal import StaticModule
```

> [NOTA] O nível de acesso nas importações foi incluído no Swift 6. Se estiver a
> utilizar versões mais antigas do Swift, terá de utilizar
> <LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
> em vez disso:

```swift
@_implementationOnly import StaticModule
```
