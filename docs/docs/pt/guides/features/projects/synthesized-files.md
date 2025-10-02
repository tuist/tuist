---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# Ficheiros sintetizados {#synthesized-files}

O Tuist pode gerar arquivos e código em tempo de geração para trazer alguma
conveniência para gerenciar e trabalhar com projetos do Xcode. Nesta página,
você aprenderá sobre essa funcionalidade e como usá-la em seus projetos.

## Recursos alvo {#target-resources}

Os projectos Xcode suportam a adição de recursos a alvos. No entanto, eles
apresentam às equipas alguns desafios, especialmente quando se trabalha com um
projeto modular em que as fontes e os recursos são frequentemente deslocados:

- **Acesso inconsistente em tempo de execução**: A localização dos recursos no
  produto final e a forma de aceder aos mesmos depende do produto de destino.
  Por exemplo, se o alvo representar uma aplicação, os recursos são copiados
  para o pacote da aplicação. Isto leva a que o código que acede aos recursos
  faça suposições sobre a estrutura do pacote, o que não é ideal, porque torna o
  código mais difícil de compreender e os recursos mais móveis.
- **Produtos que não suportam recursos**: Há certos produtos, como bibliotecas
  estáticas, que não são pacotes e, portanto, não suportam recursos. Por isso, é
  necessário recorrer a um tipo de produto diferente, por exemplo, frameworks,
  que podem adicionar algumas despesas gerais ao seu projeto ou aplicação. Por
  exemplo, frameworks estáticos serão ligados estaticamente ao produto final, e
  uma fase de construção é necessária para copiar apenas os recursos para o
  produto final. Ou frameworks dinâmicos, onde o Xcode copiará tanto o binário
  quanto os recursos para o produto final, mas aumentará o tempo de
  inicialização da sua aplicação porque o framework precisa ser carregado
  dinamicamente.
- **Propenso a erros de tempo de execução**: Os recursos são identificados pelo
  seu nome e extensão (strings). Por conseguinte, um erro de digitação em
  qualquer uma delas conduzirá a um erro de tempo de execução ao tentar aceder
  ao recurso. Isto não é ideal porque não é detectado em tempo de compilação e
  pode levar a falhas no lançamento.

Tuist resolve os problemas acima referidos **sintetizando uma interface
unificada para aceder a pacotes e recursos** que abstrai os pormenores de
implementação.

> [IMPORTANTE] RECOMENDADO Apesar de o acesso aos recursos através da interface
> sintetizada por Tuist não ser obrigatório, recomendamo-lo porque torna o
> código mais fácil de compreender e os recursos mais fáceis de movimentar.

## Recursos {#resources}

O Tuist fornece interfaces para declarar o conteúdo de ficheiros como
`Info.plist` ou direitos em Swift. Isso é útil para garantir a consistência
entre destinos e projetos, e aproveitar o compilador para detetar problemas em
tempo de compilação. Você também pode criar suas próprias abstrações para
modelar o conteúdo e compartilhá-lo entre destinos e projetos.

Quando o seu projeto é gerado, o Tuist sintetiza o conteúdo desses ficheiros e
escreve-os no diretório `Derived` relativamente ao diretório que contém o
projeto que os define.

> [Recomendamos que adicione o diretório `Derived` ao ficheiro `.gitignore` do
> seu projeto.

## Acessores de pacotes {#bundle-accessors}

O Tuist sintetiza uma interface para aceder ao pacote que contém os recursos
alvo.

### Swift {#swift}

O alvo conterá uma extensão do tipo `Bundle` que expõe o pacote:

```swift
let bundle = Bundle.module
```

### Objetivo-C {#objectivec}

Em Objective-C, terá uma interface `{Target}Resources` para aceder ao pacote:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING] LIMITAÇÃO COM ALVOS INTERNOS Atualmente, o Tuist não gera acessores
> de pacotes de recursos para alvos internos que contêm apenas fontes
> Objective-C. Esta é uma limitação conhecida e registada em [issue
> #6456](https://github.com/tuist/tuist/issues/6456).

> [!DICA] SUPORTAR RECURSOS EM BIBLIOTECAS ATRAVÉS DE PACOTES Se um produto
> alvo, por exemplo uma biblioteca, não suportar recursos, o Tuist incluirá os
> recursos num alvo do tipo de produto `bundle`, assegurando que acaba no
> produto final e que a interface aponta para o pacote correto.

## Acessores de recursos {#resource-accessors}

Os recursos são identificados pelo seu nome e extensão utilizando cadeias de
caracteres. Isso não é ideal porque não é detectado em tempo de compilação e
pode levar a falhas no lançamento. Para evitar isso, o Tuist integra o
[SwiftGen](https://github.com/SwiftGen/SwiftGen) no processo de geração do
projeto para sintetizar uma interface para acessar os recursos. Graças a isso, é
possível acessar os recursos com confiança, aproveitando o compilador para
detetar qualquer problema.

O Tuist inclui
[templates](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
para sintetizar acessores para os seguintes tipos de recursos por padrão:

| Tipo de recurso | Synthesized files               |
| --------------- | ------------------------------- |
| Imagens e cores | `Activos+{Alvo}.swift`          |
| Cordas          | `Strings+{Target}.swift`        |
| Listas          | `{NomeDaLista}.swift`           |
| Fontes          | `Tipos de letra+{Target}.swift` |
| Ficheiros       | `Ficheiros+{Target}.swift`      |

> Nota: É possível desativar a sintetização de acessores de recursos por
> projeto, passando a opção `disableSynthesizedResourceAccessors` para as opções
> do projeto.

#### Modelos personalizados {#custom-templates}

Se pretender fornecer os seus próprios modelos para sintetizar acessores para
outros tipos de recursos, que devem ser suportados pelo
[SwiftGen](https://github.com/SwiftGen/SwiftGen), pode criá-los em
`Tuist/ResourceSynthesizers/{name}.stencil`, onde o nome é a versão em
maiúsculas do recurso.

| Resources        | Nome do modelo             |
| ---------------- | -------------------------- |
| cordas           | `Strings.stencil`          |
| activos          | `Activos.stencil`          |
| listas           | `Plists.stencil`           |
| fontes           | `Tipos de letra.stencil`   |
| dados principais | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| ficheiros        | `Ficheiros.stencil`        |

Se pretender configurar a lista de tipos de recursos para os quais sintetizar os
acessores, pode utilizar a propriedade `Project.resourceSynthesizers` passando a
lista de sintetizadores de recursos que pretende utilizar:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [REFERÊNCIA Pode consultar [este
> acessório](https://github.com/tuist/tuist/tree/main/cli/Fixtures/ios_app_with_templates)
> para ver um exemplo de como utilizar modelos personalizados para sintetizar os
> acessores dos recursos.
