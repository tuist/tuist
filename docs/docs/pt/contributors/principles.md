---
{
  "title": "Principles",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Princípios

Esta página descreve os princípios que constituem os pilares da conceção e do
desenvolvimento do Tuist. Estes princípios evoluem com o projeto e destinam-se a
assegurar um crescimento sustentável que esteja bem alinhado com a base do
projeto.

## Predefinição para convenções {#default-to-conventions}

Uma das razões pelas quais o Tuist existe é porque o Xcode é fraco em convenções
e isso leva a projetos complexos que são difíceis de escalar e manter. Por esse
motivo, o Tuist adota uma abordagem diferente, adotando convenções simples e bem
projetadas. **Os desenvolvedores podem optar por não usar as convenções, mas
essa é uma decisão consciente que não parece natural.**

Por exemplo, há uma convenção para definir dependências entre alvos usando a
interface pública fornecida. Ao fazer isso, o Tuist garante que os projetos
sejam gerados com as configurações corretas para que a vinculação funcione. Os
desenvolvedores têm a opção de definir as dependências através das configurações
de compilação, mas eles estariam fazendo isso implicitamente e, portanto,
quebrando os recursos do Tuist, como `tuist graph` ou `tuist cache` que dependem
de algumas convenções a serem seguidas.

A razão pela qual optamos por convenções é que quanto mais decisões pudermos
tomar em nome dos programadores, mais concentrados eles estarão na criação de
funcionalidades para as suas aplicações. Quando não temos convenções, como é o
caso em muitos projectos, temos de tomar decisões que acabam por não ser
consistentes com outras decisões e, como consequência, haverá uma complexidade
acidental que será difícil de gerir.

## Os manifestos são a fonte da verdade {#manifestos-são-a-fonte-da-verdade}

A existência de muitas camadas de configurações e de contratos entre elas
resulta numa configuração de projeto difícil de compreender e de manter. Pense
por um segundo em um projeto comum. A definição do projeto vive nos diretórios
`.xcodeproj`, a CLI em scripts (por exemplo, `Fastfiles`), e a lógica de CI em
pipelines. Essas são três camadas com contratos entre elas que precisamos
manter. *Quantas vezes já esteve numa situação em que alterou algo nos seus
projectos, e uma semana depois apercebeu-se que os scripts de lançamento estavam
avariados?*

Podemos simplificar isso tendo uma única fonte de verdade, os arquivos de
manifesto. Esses arquivos fornecem ao Tuist as informações de que ele precisa
para gerar projetos Xcode que os desenvolvedores podem usar para editar seus
arquivos. Além disso, ele permite ter comandos padrão para construir projetos a
partir de um ambiente local ou de CI.

**Os tuístas devem assumir a complexidade e expor uma interface simples, segura
e agradável para descrever os seus projectos da forma mais explícita possível.**

## Tornar explícito o implícito {#tornar explícito o implícito}

O Xcode suporta configurações implícitas. Um bom exemplo disso é inferir as
dependências definidas implicitamente. Embora a implicação seja boa para
pequenos projectos, onde as configurações são simples, à medida que os projectos
se tornam maiores pode causar lentidão ou comportamentos estranhos.

O Tuist deve fornecer APIs explícitas para comportamentos implícitos do Xcode.
Ele também deve suportar a definição da implicitude do Xcode, mas implementado
de tal forma que encoraje os desenvolvedores a optar pela abordagem explícita. O
suporte às implicações e complexidades do Xcode facilita a adoção do Tuist, após
o que as equipas podem levar algum tempo para se livrarem das implicações.

A definição de dependências é um bom exemplo disso. Enquanto os desenvolvedores
podem definir dependências através de configurações e fases de construção, o
Tuist fornece uma bela API que encoraja sua adoção.

**A conceção da API para ser explícita permite que o Tuist execute algumas
verificações e optimizações nos projectos que de outra forma não seriam
possíveis.** Além disso, permite funcionalidades como `tuist graph`, que exporta
uma representação do gráfico de dependências, ou `tuist cache`, que armazena em
cache todos os alvos como binários.

> [Devemos tratar cada pedido de portabilidade de funcionalidades do Xcode como
> uma oportunidade para simplificar conceitos com APIs simples e explícitas.

## Manter as coisas simples {#manter as coisas simples}

Um dos principais desafios ao escalar projetos Xcode vem do fato de que **Xcode
expõe muita complexidade para os usuários.** Devido a isso, as equipes têm um
alto fator de ônibus e apenas algumas pessoas na equipe entendem o projeto e os
erros que o sistema de construção lança. Esta é uma má situação, porque a equipa
depende de poucas pessoas.

O Xcode é uma excelente ferramenta, mas tantos anos de melhorias, novas
plataformas e linguagens de programação reflectem-se na sua superfície, que se
esforçou por permanecer simples.

Os tuístas devem aproveitar a oportunidade para manter as coisas simples, porque
trabalhar em coisas simples é divertido e motiva-nos. Ninguém quer perder tempo
a tentar depurar um erro que acontece no final do processo de compilação, ou a
perceber porque é que não conseguem executar a aplicação nos seus dispositivos.
O Xcode delega as tarefas ao seu sistema de compilação subjacente e, em alguns
casos, faz um trabalho muito mau ao traduzir erros em itens acionáveis. Já
alguma vez recebeu um erro *"framework X not found"* e não sabia o que fazer?
Imagine se tivéssemos uma lista de potenciais causas de raiz para o erro.

## Começar pela experiência do programador {#começar pela experiência do programador}

Parte da razão pela qual existe uma falta de inovação em torno do Xcode, ou dito
de outra forma, não tanto como noutros ambientes de programação, deve-se ao
facto de **começarmos frequentemente a analisar problemas a partir de soluções
existentes.** Como consequência, a maioria das soluções que encontramos hoje em
dia giram em torno das mesmas ideias e fluxos de trabalho. Embora seja bom
incluir soluções existentes nas equações, não devemos deixar que elas limitem a
nossa criatividade.

Gostamos de pensar como [Tom Preston](https://tom.preston-werner.com/) diz em
[este podcast](https://tom.preston-werner.com/): *"A maioria das coisas pode ser
alcançada, o que quer que tenhamos na nossa cabeça, provavelmente podemos fazer
com código, desde que seja possível dentro dos limites do universo".* Se
**imaginarmos como gostaríamos que a experiência do programador fosse**, é
apenas uma questão de tempo para o conseguirmos - começar a analisar os
problemas a partir da experiência do programador dá-nos um ponto de vista único
que nos levará a soluções que os utilizadores vão adorar utilizar.

Podemos sentir-nos tentados a seguir o que toda a gente está a fazer, mesmo que
isso signifique ficar com os inconvenientes de que todos se continuam a queixar.
Não vamos fazer isso. Como é que eu imagino arquivar a minha aplicação? Como é
que eu gostaria que fosse a assinatura de código? Que processos posso ajudar a
simplificar com o Tuist? Por exemplo, adicionar suporte para
[Fastlane](https://fastlane.tools/) é uma solução para um problema que
precisamos de compreender primeiro. Podemos chegar à raiz do problema fazendo
perguntas do tipo "porquê". Assim que descobrirmos de onde vem a motivação,
podemos pensar em como o Tuist pode ajudá-los da melhor forma. Talvez a solução
seja a integração com a Fastlane, mas é importante não ignorarmos outras
soluções igualmente válidas que podemos colocar em cima da mesa antes de
fazermos cedências.

## Os erros podem e vão acontecer {#errors-can-and-will-happen}

Nós, programadores, temos a tentação inerente de não ter em conta que os erros
podem acontecer. Como resultado, concebemos e testamos software apenas
considerando o cenário ideal.

O Swift, seu sistema de tipos e um código bem arquitetado podem ajudar a evitar
alguns erros, mas não todos, pois alguns estão fora do nosso controle. Não
podemos assumir que o usuário sempre terá uma conexão com a internet, ou que os
comandos do sistema retornarão com sucesso. Os ambientes em que o Tuist é
executado não são caixas de areia que controlamos e, por isso, precisamos de
fazer um esforço para compreender como podem mudar e afetar o Tuist.

Erros mal tratados resultam numa má experiência para o utilizador e este pode
perder a confiança no projeto. Queremos que os utilizadores apreciem todas as
partes do Tuist, mesmo a forma como lhes apresentamos os erros.

Devemos colocar-nos no lugar dos utilizadores e imaginar o que esperamos que o
erro nos diga. Se a linguagem de programação é o canal de comunicação através do
qual os erros se propagam, e os utilizadores são o destino dos erros, estes
devem ser escritos na mesma língua que o alvo (utilizadores) fala. Devem incluir
informação suficiente para saber o que aconteceu e ocultar a informação que não
é relevante. Além disso, devem ser acionáveis, indicando aos utilizadores os
passos que podem dar para recuperar dos erros.

E por último, mas não menos importante, os nossos casos de teste devem
contemplar cenários de falha. Não só garantem que estamos a tratar os erros como
é suposto, mas também evitam que futuros programadores quebrem essa lógica.
