---
{
  "title": "Code reviews",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Revisões de código {#revisões de código}

A revisão de pedidos pull é um tipo comum de contribuição. Apesar da integração
contínua (CI) garantir que o código faz o que é suposto fazer, não é suficiente.
Existem caraterísticas de contribuição que não podem ser automatizadas: design,
estrutura e arquitetura do código, qualidade dos testes ou erros de digitação.
As secções seguintes representam diferentes aspectos do processo de revisão do
código.

## Legibilidade {#readability}

O código expressa claramente a sua intenção? **Se precisar de perder muito tempo
a descobrir o que o código faz, a implementação do código precisa de ser
melhorada.** Sugira a divisão do código em abstracções mais pequenas que sejam
mais fáceis de compreender. Alternativamente, e como último recurso, podem
acrescentar um comentário a explicar o raciocínio subjacente. Pergunte a si
próprio se seria capaz de compreender o código num futuro próximo, sem qualquer
contexto envolvente como a descrição do pull request.

## Pedidos pequenos {#small-pull-requests}

Os pull requests grandes são difíceis de rever e é mais fácil perder pormenores.
Se um pull request se tornar demasiado grande e impossível de gerir, sugira ao
autor que o divida em partes.

> [EXCEPÇÕES Há alguns cenários em que dividir o pull request não é possível,
> como quando as alterações estão fortemente acopladas e não podem ser
> divididas. Nesses casos, o autor deve fornecer uma explicação clara das
> alterações e o raciocínio por trás delas.

## Consistência {#consistência}

É importante que as alterações sejam coerentes com o resto do projeto. As
inconsistências complicam a manutenção e, por isso, devemos evitá-las. Se houver
uma abordagem para enviar mensagens ao utilizador, ou reportar erros, devemos
manter essa abordagem. Se o autor não concordar com os padrões do projeto,
sugira-lhe que abra uma issue onde possamos discuti-los melhor.

## Testes {#tests}

Os testes permitem alterar o código com confiança. O código nos pedidos pull
deve ser testado, e todos os testes devem passar. Um bom teste é um teste que
produz consistentemente o mesmo resultado e que é fácil de entender e manter. Os
revisores passam a maior parte do tempo de revisão no código de implementação,
mas os testes são igualmente importantes porque também são código.

## Alterações de rutura {#breaking-changes}

As alterações de rutura são uma má experiência para os utilizadores do Tuist. As
contribuições devem evitar a introdução de alterações de rutura, a menos que
seja estritamente necessário. Há muitas caraterísticas da linguagem que podem
ser aproveitadas para evoluir a interface do Tuist sem recorrer a uma mudança de
rutura. Se uma mudança é ou não quebrável pode não ser óbvio. Um método para
verificar se a mudança é uma quebra é rodar o Tuist contra os projetos de
fixtures no diretório de fixtures. É necessário colocarmo-nos no lugar do
utilizador e imaginar como as alterações o afectariam.
