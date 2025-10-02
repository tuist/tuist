---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# O custo da conveniência {#the-cost-of-convenience}

Conceber um editor de código que o espetro **de projectos de pequena a grande
escala possa utilizar** é uma tarefa difícil. Muitas ferramentas abordam o
problema colocando a sua solução em camadas e fornecendo extensibilidade. A
camada mais baixa é de muito baixo nível e próxima do sistema de compilação
subjacente, e a camada mais alta é uma abstração de alto nível que é conveniente
de usar mas menos flexível. Ao fazer isso, eles tornam as coisas simples fáceis,
e todo o resto possível.

No entanto, **[Apple](https://www.apple.com) decidiu adotar uma abordagem
diferente com o Xcode**. A razão é desconhecida, mas é provável que a otimização
para os desafios de projectos de grande escala nunca tenha sido o seu objetivo.
Eles investiram demais em conveniência para pequenos projetos, forneceram pouca
flexibilidade e acoplaram fortemente as ferramentas com o sistema de construção
subjacente. Para alcançar a conveniência, eles fornecem padrões sensatos, que
podem ser facilmente substituídos, e adicionaram muitos comportamentos
implícitos resolvidos em tempo de compilação que são os culpados de muitos
problemas em escala.

## Explicitação e escala {#explicitação-e-escala}

Quando se trabalha em escala, a **explicitação é fundamental**. Ela permite que
o sistema de compilação analise e entenda a estrutura do projeto e dependências
antes do tempo, e realize otimizações que seriam impossíveis de outra forma. A
mesma explicitação é também fundamental para garantir que as funcionalidades do
editor como [SwiftUI
previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
ou [Swift
Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)
funcionam de forma fiável e previsível. Porque o Xcode e os projectos Xcode
abraçaram a implicação como uma escolha de design válida para alcançar a
conveniência, um princípio que o Gestor de Pacotes Swift herdou, as dificuldades
de usar o Xcode também estão presentes no Gestor de Pacotes Swift.

> [!INFO] O PAPEL DO TUIST Poderíamos resumir o papel do Tuist como uma
> ferramenta que evita projetos definidos implicitamente e aproveita a
> explicitação para proporcionar uma melhor experiência ao desenvolvedor (por
> exemplo, validações, otimizações). Ferramentas como
> [Bazel](https://bazel.build) levam isso mais longe, trazendo-o para o nível do
> sistema de compilação.

Este é um problema que é pouco discutido na comunidade, mas é significativo.
Enquanto trabalhamos no Tuist, notamos muitas organizações e desenvolvedores
pensando que os desafios atuais que eles enfrentam serão resolvidos pelo [Swift
Package Manager](https://www.swift.org/documentation/package-manager/), mas o
que eles não percebem é que, porque ele está construindo sobre os mesmos
princípios, mesmo que ele mitigue os tão conhecidos conflitos do Git, eles
degradam a experiência do desenvolvedor em outras áreas e continuam a tornar os
projetos não otimizáveis.

Nas seções a seguir, discutiremos alguns exemplos reais de como a implicação
afeta a experiência do desenvolvedor e a saúde do projeto. A lista não é
exaustiva, mas deve dar uma boa ideia dos desafios que você pode enfrentar ao
trabalhar com projetos Xcode ou pacotes Swift.

## A conveniência a meter-se no seu caminho {#convenience-getting-in-your-way}

### Diretório de produtos criados partilhados {#shared-built-products-diretory}

O Xcode usa um diretório dentro do diretório de dados derivados para cada
produto. Dentro dele, ele armazena os artefatos de compilação, como os binários
compilados, os arquivos dSYM e os logs. Como todos os produtos de um projeto vão
para o mesmo diretório, que é visível por predefinição de outros alvos para
ligação, **poderá acabar com alvos que dependem implicitamente uns dos outros.**
Enquanto isto pode não ser um problema quando se tem apenas alguns alvos, pode
manifestar-se como falhas de compilação que são difíceis de depurar quando o
projeto cresce.

A consequência desta decisão de conceção é que muitos projectos compilam
acidentalmente com um gráfico que não está bem definido.

> [!TIP] TUIST DETECÇÃO DE DEPENDÊNCIAS IMPLÍCITAS O Tuist fornece um comando
> <LocalizedLink href="/guides/features/inspect/implicit-dependencies"></LocalizedLink>
> para detetar dependências implícitas. Pode utilizar o comando para validar na
> CI que todas as suas dependências são explícitas.

### Encontrar dependências implícitas em esquemas {#find-implicit-dependencies-in-schemes}

Definir e manter um gráfico de dependências no Xcode torna-se mais difícil à
medida que o projeto cresce. É difícil porque eles são codificados nos arquivos
`.pbxproj` como fases de compilação e configurações de compilação, não há
ferramentas para visualizar e trabalhar com o gráfico, e as mudanças no gráfico
(por exemplo, adicionar um novo framework pré-compilado dinâmico), podem exigir
mudanças de configuração a montante (por exemplo, adicionar uma nova fase de
compilação para copiar o framework no pacote).

A Apple decidiu em algum momento que, em vez de evoluir o modelo gráfico para
algo mais gerenciável, faria mais sentido adicionar uma opção para resolver
dependências implícitas em tempo de compilação. Esta é mais uma vez uma escolha
de design questionável porque pode acabar com tempos de compilação mais lentos
ou compilações imprevisíveis. Por exemplo, uma compilação pode passar localmente
devido a algum estado nos dados de derivação, que age como um
[singleton](https://en.wikipedia.org/wiki/Singleton_pattern), mas depois falhar
na compilação no CI porque o estado é diferente.

> [Recomendamos que desactive esta opção nos esquemas do seu projeto e utilize
> um Tuist que facilite a gestão do gráfico de dependências.

### Pré-visualizações da SwiftUI e bibliotecas estáticas/frameworks {#swiftui-previews-and-static-librariesframeworks}

Alguns recursos do editor, como SwiftUI Previews ou Swift Macros, exigem a
compilação do gráfico de dependência do arquivo que está sendo editado. Esta
integração entre o editor requer que o sistema de compilação resolva qualquer
implicação e produza os artefactos corretos que são necessários para que essas
funcionalidades funcionem. Como pode imaginar, **quanto mais implícito for o
gráfico, mais desafiante é a tarefa para o sistema de compilação**, e por isso
não é surpreendente que muitas destas funcionalidades não funcionem de forma
fiável. Muitas vezes ouvimos de desenvolvedores que eles pararam de usar SwiftUI
previews há muito tempo porque eles eram muito pouco confiáveis. Em vez disso,
eles estão usando aplicativos de exemplo, ou evitando certas coisas, como o uso
de bibliotecas estáticas ou fases de construção de script, porque eles causam a
quebra do recurso.

### Bibliotecas mescláveis {#bibliotecas mescláveis}

As estruturas dinâmicas, embora mais flexíveis e mais fáceis de trabalhar, têm
um impacto negativo no tempo de lançamento das aplicações. Por outro lado, as
bibliotecas estáticas são mais rápidas de lançar, mas afectam o tempo de
compilação e são um pouco mais difíceis de trabalhar, especialmente em cenários
gráficos complexos. *Não seria ótimo se fosse possível alternar entre um ou
outro, dependendo da configuração?* Foi isso que a Apple deve ter pensado quando
decidiu trabalhar em bibliotecas mescláveis. Mas, mais uma vez, eles
transferiram a inferência do tempo de compilação para o tempo de compilação. Se
raciocinar sobre um gráfico de dependência, imagine ter que fazer isso quando a
natureza estática ou dinâmica do alvo será resolvida em tempo de compilação com
base em algumas configurações de compilação em alguns alvos. Boa sorte para
fazer isso funcionar de forma confiável enquanto garante que funcionalidades
como o SwiftUI previews não quebrem.

**Muitos utilizadores chegam ao Tuist querendo usar bibliotecas fundíveis e a
nossa resposta é sempre a mesma. Não é necessário.** Você pode controlar a
natureza estática ou dinâmica dos seus alvos em tempo de geração, levando a um
projeto cujo gráfico é conhecido antes da compilação. Nenhuma variável precisa
ser resolvida em tempo de compilação.

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## Explícito, explícito e explícito {#explícito-explícito-e-explícito}

Se há um princípio importante não escrito que recomendamos a todos os
desenvolvedores ou organizações que querem que seu desenvolvimento com o Xcode
seja escalável, é que eles devem abraçar a explicitação. E se a explicitação é
difícil de gerir com projectos Xcode em bruto, devem considerar outra coisa, ou
[Tuist](https://tuist.io) ou [Bazel](https://bazel.build). **Só então a
fiabilidade, a previsibilidade e as optimizações serão possíveis.**

## Futuro

Não se sabe se a Apple vai fazer algo para evitar todos os problemas acima. As
suas decisões contínuas incorporadas no Xcode e no Swift Package Manager não
sugerem que o farão. Uma vez que você permite a configuração implícita como um
estado válido, **é difícil sair daí sem introduzir mudanças significativas.**
Voltar aos primeiros princípios e repensar o design das ferramentas pode levar à
quebra de muitos projectos Xcode que compilaram acidentalmente durante anos.
Imagine o alvoroço da comunidade se isso acontecesse.

A Apple encontra-se numa espécie de problema do ovo e da galinha. A conveniência
é o que ajuda os programadores a começar rapidamente e a criar mais aplicações
para o seu ecossistema. Mas as suas decisões de tornar a experiência conveniente
a essa escala estão a dificultar-lhes a tarefa de garantir que algumas das
funcionalidades do Xcode funcionam de forma fiável.

Como o futuro é desconhecido, tentamos **estar o mais próximo possível das
normas da indústria e dos projectos Xcode**. Evitamos os problemas acima
referidos e aproveitamos o conhecimento que temos para proporcionar uma melhor
experiência ao programador. Idealmente não teríamos de recorrer à geração de
projectos para isso, mas a falta de extensibilidade do Xcode e do Gestor de
Pacotes Swift tornam-na a única opção viável. E é também uma opção segura porque
eles terão que quebrar os projectos Xcode para quebrar os projectos Tuist.

Idealmente, **o sistema de compilação era mais extensível**, mas não seria uma
má ideia ter plugins/extensões que contratam com um mundo de implicação? Não me
parece uma boa ideia. Assim, parece que vamos precisar de ferramentas externas
como o Tuist ou o [Bazel](https://bazel.build) para proporcionar uma melhor
experiência ao programador. Ou talvez a Apple nos surpreenda a todos e torne o
Xcode mais extensível e explícito...

Até que isso aconteça, tem de escolher se quer abraçar a conveniência do Xcode e
assumir a dívida que a acompanha, ou confiar em nós nesta viagem para
proporcionar uma melhor experiência de desenvolvimento. Não o iremos desiludir.
