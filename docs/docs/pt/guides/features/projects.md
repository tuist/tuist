---
{
  "title": "Projects",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn about Tuist's DSL for defining Xcode projects."
}
---
# Projectos gerados {#projectos gerados}

O Generated é uma alternativa viável que ajuda a superar esses desafios,
mantendo a complexidade e os custos em um nível aceitável. Ele considera os
projetos Xcode como um elemento fundamental, garantindo a resiliência contra
futuras atualizações do Xcode, e aproveita a geração de projetos Xcode para
fornecer às equipes uma API declarativa focada na modularização. A Tuist utiliza
a declaração de projeto para simplificar as complexidades da modularização**,
otimizar fluxos de trabalho como a construção ou o teste em vários ambientes e
facilitar e democratizar a evolução dos projectos Xcode.

## Como é que funciona? {Como é que funciona?}

Para começar a utilizar os projectos gerados, basta definir o seu projeto
utilizando **Tuist's Domain Specific Language (DSL)**. Isso implica no uso de
arquivos de manifesto como `Workspace.swift` ou `Project.swift`. Se já trabalhou
com o Swift Package Manager antes, a abordagem é muito semelhante.

Depois de definir o seu projeto, o Tuist oferece vários fluxos de trabalho para
o gerir e interagir com ele:

- **Gerar:** Este é um fluxo de trabalho fundamental. Use-o para criar um
  projeto Xcode que seja compatível com o Xcode.
- **<LocalizedLink href="/guides/features/build">Build</LocalizedLink>:** Este
  fluxo de trabalho não só gera o projeto Xcode como também emprega `xcodebuild`
  para o compilar.
- **<LocalizedLink href="/guides/features/test">Test</LocalizedLink>:** Operando
  de forma muito semelhante ao fluxo de trabalho de compilação, isto não só gera
  o projeto Xcode como utiliza `xcodebuild` para o testar.

## Desafios com projectos Xcode {#challenges-with-xcode-projects}

À medida que os projetos do Xcode crescem, as organizações **podem enfrentar um
declínio na produtividade** devido a vários fatores, incluindo compilações
incrementais não confiáveis, limpeza frequente do cache global do Xcode por
desenvolvedores que encontram problemas e configurações de projeto frágeis. Para
manter o rápido desenvolvimento de recursos, as organizações normalmente
exploram várias estratégias.

Algumas organizações optam por contornar o compilador abstraindo a plataforma
usando tempos de execução dinâmicos baseados em JavaScript, como o [React
Native](https://reactnative.dev/). Embora essa abordagem possa ser eficaz, ela
[complica o acesso aos recursos nativos da
plataforma](https://shopify.engineering/building-app-clip-react-native). Outras
organizações optam por **modularizar a base de código**, o que ajuda a
estabelecer limites claros, tornando a base de código mais fácil de trabalhar e
melhorando a confiabilidade dos tempos de construção. No entanto, o formato do
projeto Xcode não foi concebido para a modularidade e resulta em configurações
implícitas que poucos compreendem e em conflitos frequentes. Isso leva a um
fator de barramento ruim e, embora as compilações incrementais possam melhorar,
os desenvolvedores ainda podem limpar frequentemente o cache de compilação do
Xcode (ou seja, dados derivados) quando as compilações falham. Para resolver
isso, algumas organizações optam por **abandonar o sistema de build do Xcode** e
adotar alternativas como [Buck](https://buck.build/) ou
[Bazel](https://bazel.build/). No entanto, isso acarreta uma [alta complexidade
e carga de manutenção](https://bazel.build/migrate/xcode).


## Alternativas {#alternativas}

### Gestor de pacotes Swift {#swift-package-manager}

Enquanto o Swift Package Manager (SPM) foca principalmente em dependências, o
Tuist oferece uma abordagem diferente. Com o Tuist, você não define apenas
pacotes para a integração do SPM; você molda seus projetos usando conceitos
familiares como projetos, espaços de trabalho, alvos e esquemas.

### XcodeGen {#xcodegen}

O [XcodeGen](https://github.com/yonaskolb/XcodeGen) é um gerador de projectos
dedicado, concebido para reduzir conflitos em projectos Xcode colaborativos e
simplificar algumas complexidades do funcionamento interno do Xcode. No entanto,
os projetos são definidos usando formatos serializáveis como
[YAML](https://yaml.org/). Ao contrário do Swift, isso não permite que os
desenvolvedores construam sobre abstrações ou verificações sem incorporar
ferramentas adicionais. Embora o XcodeGen ofereça uma maneira de mapear
dependências para uma representação interna para validação e otimização, ele
ainda expõe os desenvolvedores às nuances do Xcode. Isso pode fazer do XcodeGen
uma base adequada para [construir
ferramentas](https://github.com/MobileNativeFoundation/rules_xcodeproj), como
visto na comunidade Bazel, mas não é ideal para a evolução de projetos
inclusivos que visam manter um ambiente saudável e produtivo.

### Bazel {#bazel}

O [Bazel](https://bazel.build) é um sistema de compilação avançado conhecido por
seus recursos de cache remoto, ganhando popularidade dentro da comunidade Swift
principalmente por essa capacidade. No entanto, dada a extensibilidade limitada
do Xcode e seu sistema de build, substituí-lo pelo sistema do Bazel exige
esforço e manutenção significativos. Apenas algumas empresas com recursos
abundantes podem suportar esta sobrecarga, como é evidente a partir da lista
selecionada de empresas que investem fortemente para integrar o Bazel com o
Xcode. Curiosamente, a comunidade criou uma
[ferramenta](https://github.com/MobileNativeFoundation/rules_xcodeproj) que
emprega o XcodeGen do Bazel para gerar um projeto Xcode. Isso resulta em uma
cadeia complicada de conversões: de arquivos do Bazel para o XcodeGen YAML e,
finalmente, para projetos do Xcode. Essa indireção em camadas muitas vezes
complica a solução de problemas, tornando os problemas mais difíceis de
diagnosticar e resolver.
