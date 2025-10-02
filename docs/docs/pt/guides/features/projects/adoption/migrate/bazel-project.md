---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Migrar um projeto Bazel {#migrate-a-bazel-project}

O [Bazel](https://bazel.build) é um sistema de compilação cujo código aberto foi
criado pelo Google em 2015. É uma ferramenta poderosa que permite construir e
testar software de qualquer tamanho, de forma rápida e fiável. Algumas grandes
organizações como
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae),
ou [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) usam-no, no entanto,
requer um investimento inicial (ou seja, aprender a tecnologia) e contínuo (ou
seja, acompanhar as actualizações do Xcode) para introduzir e manter. Embora
isso funcione para algumas organizações que tratam isso como uma preocupação
transversal, pode não ser a melhor opção para outras que desejam se concentrar
no desenvolvimento de seus produtos. Por exemplo, já vimos organizações cuja
equipa da plataforma iOS introduziu o Bazel e teve de o abandonar depois de os
engenheiros que lideraram o esforço terem deixado a empresa. A posição da Apple
sobre o forte acoplamento entre o Xcode e o sistema de compilação é outro fator
que dificulta a manutenção de projetos Bazel ao longo do tempo.

> [A UNIQUEZA DO TUIST ESTÁ NA SUA FINESSE Em vez de lutar contra o Xcode e os
> projectos Xcode, o Tuist abraça-os. São os mesmos conceitos (por exemplo,
> alvos, esquemas, configurações de compilação), uma linguagem familiar (ou
> seja, Swift) e uma experiência simples e agradável que torna a manutenção e o
> escalonamento de projectos uma tarefa de todos e não apenas da equipa da
> plataforma iOS.

## Regras {#rules}

O Bazel usa regras para definir como construir e testar software. As regras são
escritas em [Starlark](https://github.com/bazelbuild/starlark), uma linguagem
semelhante ao Python. O Tuist usa o Swift como uma linguagem de configuração,
que fornece aos desenvolvedores a conveniência de usar os recursos de
autocompletar, verificação de tipos e validação do Xcode. Por exemplo, a regra a
seguir descreve como criar uma biblioteca Swift no Bazel:

::: grupo de códigos
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
:::

Eis um outro exemplo, mas que compara a forma de definir testes unitários em
Bazel e Tuist:

:::grupo de códigos
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
:::


## Dependências do Gestor de Pacotes Swift {#swift-package-manager-dependencies}

No Bazel, você pode usar o plugin
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
para usar os pacotes Swift como dependências. O plugin requer um `Package.swift`
como fonte de verdade para as dependências. A interface do Tuist é similar à do
Bazel nesse sentido. Você pode usar o comando `tuist install` para resolver e
obter as dependências do pacote. Após a conclusão da resolução, é possível gerar
o projeto com o comando `tuist generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Geração de projectos {#project-generation}

A comunidade fornece um conjunto de regras,
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj),
para gerar projetos Xcode a partir de projetos declarados pelo Bazel. Ao
contrário do Bazel, onde é necessário adicionar alguma configuração ao arquivo
`BUILD`, o Tuist não requer nenhuma configuração. Você pode executar `tuist
generate` no diretório raiz do seu projeto, e o Tuist irá gerar um projeto Xcode
para você.
