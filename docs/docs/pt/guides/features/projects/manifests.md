---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Manifestos {#manifestos}

O Tuist usa como padrão os arquivos Swift como a principal maneira de definir
projetos e espaços de trabalho e configurar o processo de geração. Estes
ficheiros são referidos como **manifest files** em toda a documentação.

A decisão de utilizar Swift foi inspirada pelo [Swift Package
Manager](https://www.swift.org/documentation/package-manager/), que também
utiliza ficheiros Swift para definir pacotes. Graças à utilização do Swift,
podemos aproveitar o compilador para validar a correção do conteúdo e reutilizar
o código em diferentes ficheiros de manifesto, e o Xcode para proporcionar uma
experiência de edição de primeira classe graças ao realce da sintaxe, ao
preenchimento automático e à validação.

> [Como os arquivos de manifesto são arquivos Swift que precisam ser compilados,
> o Tuist armazena em cache os resultados da compilação para acelerar o processo
> de análise. Portanto, você notará que na primeira vez que executar o Tuist,
> ele pode demorar um pouco mais para gerar o projeto. As execuções subsequentes
> serão mais rápidas.

## Project.swift {#projectswift}

O manifesto
<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
declara um projeto Xcode. O projeto é gerado no mesmo diretório onde o ficheiro
de manifesto está localizado com o nome indicado na propriedade `name`.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING] ROOT VARIABLES A única variável que deve estar na raiz do manifesto
> é `let project = Project(...)`. Se precisar de reutilizar código em várias
> partes do manifesto, pode utilizar funções Swift.

## Workspace.swift {#workspaceswift}

Por padrão, o Tuist gera um [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
contendo o projeto que está sendo gerado e os projetos de suas dependências. Se,
por qualquer razão, quiser personalizar o espaço de trabalho para adicionar
projectos adicionais ou incluir ficheiros e grupos, pode fazê-lo definindo um
manifesto
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

> [NOTA] O Tuist resolverá o gráfico de dependências e incluirá os projetos das
> dependências no espaço de trabalho. Não é necessário incluí-los manualmente.
> Isso é necessário para que o sistema de construção resolva as dependências
> corretamente.

### Multi ou mono-projeto {#multi-or-monoproject}

Uma questão que surge frequentemente é se se deve usar um único projeto ou
vários projectos num espaço de trabalho. Em um mundo sem o Tuist, onde uma
configuração de projeto único levaria a conflitos frequentes do Git, o uso de
espaços de trabalho é incentivado. No entanto, como não recomendamos a inclusão
dos projetos Xcode gerados pelo Tuist no repositório Git, os conflitos do Git
não são um problema. Portanto, a decisão de usar um único projeto ou vários
projetos em um espaço de trabalho fica a seu critério.

No projeto Tuist, nos apoiamos em mono-projetos porque o tempo de geração de
cold é mais rápido (menos arquivos de manifesto para compilar) e aproveitamos
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink> como uma unidade de encapsulamento. No entanto, você
pode querer usar projetos do Xcode como uma unidade de encapsulamento para
representar diferentes domínios do seu aplicativo, que se alinha mais de perto
com a estrutura de projeto recomendada do Xcode.

## Tuist.swift {#tuistswift}

O Tuist fornece
<LocalizedLink href="/contributors/principles.html#default-to-conventions">padrões
sensíveis</LocalizedLink> para simplificar a configuração do projeto. No
entanto, você pode personalizar a configuração definindo um
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
na raiz do projeto, que é usado pelo Tuist para determinar a raiz do projeto.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
