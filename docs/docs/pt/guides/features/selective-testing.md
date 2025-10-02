---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Testes selectivos {#selective-testing}

À medida que o seu projeto cresce, também cresce a quantidade de testes. Durante
muito tempo, executar todos os testes em cada PR ou push para `main` leva
dezenas de segundos. Mas esta solução não se adapta a milhares de testes que a
sua equipa possa ter.

Em cada execução de teste no CI, você provavelmente executa novamente todos os
testes, independentemente das alterações. Os testes selectivos da Tuist
ajudam-no a acelerar drasticamente a execução dos próprios testes, executando
apenas os testes que foram alterados desde a última execução de teste bem
sucedida, com base no nosso algoritmo
<LocalizedLink href="/guides/features/projects/hashing">hashing</LocalizedLink>.

O teste seletivo funciona com `xcodebuild`, que suporta qualquer projeto Xcode,
ou se gerar os seus projectos com o Tuist, pode utilizar o comando `tuist test`
que fornece alguma conveniência extra, como a integração com a cache
<LocalizedLink href="/guides/features/cache">binary</LocalizedLink>. Para
começar a usar o teste seletivo, siga as instruções com base na configuração do
seu projeto:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Generated
  project</LocalizedLink>

> [Devido à impossibilidade de detetar as dependências no código entre testes e
> fontes, a granularidade máxima do teste seletivo está no nível do alvo.
> Portanto, recomendamos manter seus alvos pequenos e focados para maximizar os
> benefícios do teste seletivo.

> [COBERTURA DE TESTES As ferramentas de cobertura de testes assumem que todo o
> conjunto de testes é executado de uma vez, o que as torna incompatíveis com
> execuções seletivas de testes - isso significa que os dados de cobertura podem
> não refletir a realidade ao usar a seleção de testes. Esta é uma limitação
> conhecida, e não significa que você está fazendo algo errado. Nós encorajamos
> as equipes a refletir se a cobertura ainda está trazendo insights
> significativos neste contexto, e se estiver, tenha certeza que nós já estamos
> pensando em como fazer a cobertura funcionar corretamente com execuções
> seletivas no futuro.


## Comentários do pedido pull/merge {#pullmerge-request-comments}

> [!IMPORTANTE] É NECESSÁRIA A INTEGRAÇÃO COM A PLATAFORMA GIT Para obter
> comentários automáticos de pedidos de pull/merge, integre o seu projeto
> <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
> com uma plataforma
> <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.

Quando seu projeto Tuist estiver conectado à sua plataforma Git, como
[GitHub](https://github.com), e você começar a usar `tuist xcodebuild test` ou
`tuist test` como parte do seu fluxo de trabalho de CI, o Tuist postará um
comentário diretamente nas suas solicitações de pull/merge, incluindo quais
testes foram executados e quais foram ignorados: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
