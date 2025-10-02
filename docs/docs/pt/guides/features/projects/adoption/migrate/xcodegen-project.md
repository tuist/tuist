---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# Migrar um projeto XcodeGen {#migrate-an-xcodegen-project}

O [XcodeGen](https://github.com/yonaskolb/XcodeGen) é uma ferramenta de geração
de projectos que utiliza YAML como [um formato de
configuração](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
para definir projectos Xcode. Muitas organizações **adoptaram-na para tentar
escapar aos frequentes conflitos Git que surgem quando se trabalha com projectos
Xcode.** No entanto, os frequentes conflitos no Git são apenas um dos muitos
problemas que as organizações enfrentam. O Xcode expõe os desenvolvedores a
muitas complexidades e configurações implícitas que dificultam a manutenção e
otimização de projetos em escala. O XcodeGen fica aquém disso por design, porque
é uma ferramenta que gera projectos Xcode, não um gestor de projectos. Se
precisar de uma ferramenta que o ajude para além da geração de projectos Xcode,
talvez queira considerar o Tuist.

> [DICA] SWIFT SOBRE YAML Muitas organizações preferem o Tuist como uma
> ferramenta de geração de projetos também porque ele usa o Swift como um
> formato de configuração. O Swift é uma linguagem de programação com a qual os
> programadores estão familiarizados e que lhes proporciona a conveniência de
> utilizar as funcionalidades de preenchimento automático, verificação de tipos
> e validação do Xcode.

O que se segue são algumas considerações e diretrizes para o ajudar a migrar os
seus projectos do XcodeGen para o Tuist.

## Geração de projectos {#project-generation}

Tanto o Tuist como o XcodeGen fornecem um comando `generate` que transforma a
declaração do seu projeto em projectos e espaços de trabalho Xcode.

::: grupo de códigos

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
:::

A diferença está na experiência de edição. Com o Tuist, pode executar o comando
`tuist edit`, que gera um projeto Xcode em tempo real que pode abrir e começar a
trabalhar. Isto é particularmente útil quando se pretende fazer alterações
rápidas ao projeto.

## `project.yaml` {#projectyaml}

O arquivo de descrição `project.yaml` do XcodeGen se torna `Project.swift`. Além
disso, você pode ter `Workspace.swift` como uma forma de personalizar como os
projetos são agrupados em espaços de trabalho. Você também pode ter um projeto
`Project.swift` com alvos que fazem referência a alvos de outros projetos.
Nesses casos, o Tuist irá gerar um espaço de trabalho do Xcode incluindo todos
os projetos.

::: grupo de códigos

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```
:::

> [DICA] LINGUAGEM DO XCODE Tanto o XcodeGen quanto o Tuist adotam a linguagem e
> os conceitos do Xcode. No entanto, a configuração baseada em Swift do Tuist
> oferece a conveniência de usar os recursos de autocompletar, verificação de
> tipo e validação do Xcode.

## Modelos de especificações {#spec-templates}

Uma das desvantagens do YAML como linguagem para a configuração de projectos é
que não suporta a reutilização de ficheiros YAML fora da caixa. Esta é uma
necessidade comum ao descrever projetos, que o XcodeGen teve que resolver com
sua própria solução proprietária chamada *"templates"*. Com o Tuist, a
reutilização está embutida na própria linguagem, Swift, e através de um módulo
Swift chamado
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink>, que permite a reutilização de código em todos os seus
arquivos de manifesto.

::: grupo de códigos
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
