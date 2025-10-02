---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# A Arquitetura Modular (TMA) {#the-modular-architecture-tma}

A TMA é uma abordagem arquitetónica para estruturar as aplicações do Apple OS de
modo a permitir a escalabilidade, otimizar os ciclos de construção e teste e
garantir boas práticas na sua equipa. A sua ideia central é construir as suas
aplicações através da criação de funcionalidades independentes que estão
interligadas utilizando APIs claras e concisas.

Estas diretrizes introduzem os princípios da arquitetura, ajudando-o a
identificar e organizar as funcionalidades da sua aplicação em diferentes
camadas. Também apresenta dicas, ferramentas e conselhos se decidir utilizar
esta arquitetura.

> [µFEATURES Esta arquitetura era anteriormente conhecida como µFeatures.
> Mudámos o seu nome para A Arquitetura Modular (TMA) para refletir melhor o seu
> objetivo e os princípios que lhe estão subjacentes.

## Princípio fundamental {#princípio fundamental}

Os programadores devem ser capazes de **construir, testar e experimentar** as
suas funcionalidades rapidamente, independentemente da aplicação principal, e ao
mesmo tempo garantir que as funcionalidades do Xcode, como as pré-visualizações
da IU, o preenchimento de código e a depuração, funcionam de forma fiável.

## O que é um módulo {#o que é um módulo}

Um módulo representa uma funcionalidade da aplicação e é uma combinação dos
cinco objectivos seguintes (em que o objetivo se refere a um objetivo do Xcode):

- **Fonte:** Contém o código-fonte da funcionalidade (Swift, Objective-C, C++,
  JavaScript...) e os seus recursos (imagens, tipos de letra, storyboards,
  xibs).
- **Interface:** Trata-se de um objetivo complementar que contém a interface
  pública e os modelos da funcionalidade.
- **Testes:** Contém a unidade de caraterísticas e os testes de integração.
- **Testes:** Fornece dados de teste que podem ser usados em testes e no
  aplicativo de exemplo. Também fornece simulações para classes de módulo e
  protocolos que podem ser usados por outros recursos, como veremos mais tarde.
- **Exemplo:** Contém uma aplicação de exemplo que os programadores podem
  utilizar para experimentar a funcionalidade em determinadas condições
  (diferentes idiomas, tamanhos de ecrã, definições).

Recomendamos que siga uma convenção de nomes para os alvos, algo que pode ser
aplicado no seu projeto graças à DSL do Tuist.

| Objetivo                | Dependencies                       | Conteúdo                         |
| ----------------------- | ---------------------------------- | -------------------------------- |
| `Caraterística`         | `Interface de recursos`            | Código-fonte e recursos          |
| `Interface de recursos` | -                                  | Interface pública e modelos      |
| `FeatureTests`          | `Funcionalidade`, `FeatureTesting` | Testes unitários e de integração |
| `FeatureTesting`        | `Interface de recursos`            | Testar dados e simulações        |
| `CaracterísticaExemplo` | `FeatureTesting`, `Feature`        | Exemplo de aplicação             |

> [!TIP] Pré-visualizações da IU `Feature` pode utilizar `FeatureTesting` como
> um Ativo de Desenvolvimento para permitir pré-visualizações da IU

> [!IMPORTANTE] DIRECTIVAS DO COMPILADOR EM VEZ DE TARGETS DE TESTE Em
> alternativa, pode utilizar as diretivas do compilador para incluir dados de
> teste e simulações nos destinos `Feature` ou `FeatureInterface` ao compilar
> para `Debug`. Simplifica o gráfico, mas acaba por compilar código que não é
> necessário para executar a aplicação.

## Porquê um módulo {#porque um módulo}

### APIs claras e concisas {#clear-and-concise-apis}

Quando todo o código-fonte da aplicação reside no mesmo destino, é muito fácil
criar dependências implícitas no código e acabar com o tão conhecido código
esparguete. Tudo está fortemente acoplado, o estado é por vezes imprevisível e a
introdução de novas alterações torna-se um pesadelo. Quando definimos
caraterísticas em objectivos independentes, temos de conceber API públicas como
parte da implementação da nossa caraterística. Temos de decidir o que deve ser
público, como a nossa funcionalidade deve ser consumida e o que deve permanecer
privado. Temos mais controlo sobre a forma como queremos que os clientes da
nossa funcionalidade a utilizem e podemos aplicar boas práticas através da
conceção de APIs seguras.

### Pequenos módulos {#pequenos-módulos}

[Dividir e conquistar](https://en.wikipedia.org/wiki/Divide_and_conquer).
Trabalhar em pequenos módulos permite-lhe ter mais foco e testar e experimentar
a funcionalidade isoladamente. Além disso, os ciclos de desenvolvimento são
muito mais rápidos, uma vez que temos uma compilação mais selectiva, compilando
apenas os componentes que são necessários para que a nossa funcionalidade
funcione. A compilação de toda a aplicação só é necessária no final do nosso
trabalho, quando precisamos de integrar a funcionalidade na aplicação.

### Reutilização {#reusabilidade}

A reutilização de código em aplicações e outros produtos, como extensões, é
incentivada através da utilização de estruturas ou bibliotecas. Construir
módulos e reutilizá-los é bastante simples. Podemos criar uma extensão iMessage,
uma extensão Today ou uma aplicação watchOS combinando apenas módulos existentes
e adicionando _(quando necessário)_ camadas de IU específicas da plataforma.

## Dependências {#dependências}

Quando um módulo depende de outro módulo, ele declara uma dependência em relação
à sua interface de destino. O benefício disso é duplo. Impede que a
implementação de um módulo seja acoplada à implementação de outro módulo e
acelera as compilações limpas porque elas só precisam compilar a implementação
do nosso recurso e as interfaces de dependências diretas e transitivas. Esta
abordagem é inspirada na ideia do SwiftRock de [Reduzir o tempo de compilação do
iOS usando módulos de
interface](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

Depender de interfaces requer que as aplicações construam o grafo de
implementações em tempo de execução e injeção de dependências nos módulos que
precisam delas. Embora o TMA não tenha opinião sobre como fazer isso,
recomendamos o uso de soluções ou padrões de injeção de dependência ou soluções
que não adicionem indireções em tempo de construção ou usem APIs de plataforma
que não foram projetadas para esse fim.

## Tipos de produtos {#product-types}

Ao construir um módulo, é possível escolher entre **bibliotecas e frameworks**,
e **ligação estática e dinâmica** para os alvos. Sem o Tuist, tomar essa decisão
é um pouco mais complexo, pois é necessário configurar o gráfico de dependências
manualmente. No entanto, graças ao Tuist Projects, isso não é mais um problema.

Recomendamos o uso de bibliotecas dinâmicas ou frameworks durante o
desenvolvimento usando
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle
accessors</LocalizedLink> para desacoplar a lógica de acesso ao bundle da
biblioteca ou natureza do framework do alvo. Isto é fundamental para tempos de
compilação rápidos e para garantir que o [SwiftUI
Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
funciona de forma fiável. E bibliotecas estáticas ou frameworks para as
compilações de lançamento para garantir que o aplicativo inicialize rapidamente.
É possível aproveitar a configuração dinâmica para alterar o tipo de produto no
momento da geração:

```bash
# You'll have to read the value of the variable from the manifest {#youll-have-to-read-the-value-of-the-variable-from-the-manifest}
# and use it to change the linking type {#and-use-it-to-change-the-linking-type}
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```


> [IMPORTANTE] BIBLIOTECAS MERGEÁVEIS A Apple tentou aliviar o incómodo de
> alternar entre bibliotecas estáticas e dinâmicas introduzindo [bibliotecas
> mergeáveis](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
> No entanto, isso introduz um não-determinismo em tempo de compilação que torna
> a sua compilação não-reprodutível e mais difícil de otimizar, pelo que não
> recomendamos a sua utilização.

## Código {#code}

A TMA não tem qualquer opinião sobre a arquitetura do código e os padrões dos
seus módulos. No entanto, gostaríamos de partilhar algumas dicas com base na
nossa experiência:

- **Aproveitar o compilador é ótimo.** Aproveitar demais o compilador pode
  acabar não sendo produtivo e fazer com que alguns recursos do Xcode, como
  visualizações, não funcionem de forma confiável. Recomendamos o uso do
  compilador para impor boas práticas e detetar erros antecipadamente, mas não a
  ponto de tornar o código mais difícil de ler e manter.
- **Use macros Swift com moderação.** Elas podem ser muito poderosas, mas também
  podem tornar o código mais difícil de ler e manter.
- **Abrace a plataforma e a linguagem, não as abstraia.** Tentar criar camadas
  de abstração elaboradas pode acabar por ser contraproducente. A plataforma e a
  linguagem são suficientemente poderosas para criar excelentes aplicações sem a
  necessidade de camadas de abstração adicionais. Utilize bons padrões de
  programação e design como referência para criar as suas funcionalidades.

## Recursos {#resources}

- [Construção de
  µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Programação orientada para a
  estrutura](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and
  Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Aproveitar as estruturas para acelerar o nosso desenvolvimento no iOS - Parte
  1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Programação orientada para
  bibliotecas](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Construindo Estruturas
  Modernas](https://developer.apple.com/videos/play/wwdc2014/416/)
- [O guia não oficial dos ficheiros
  xcconfig](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Bibliotecas estáticas e
  dinâmicas](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
