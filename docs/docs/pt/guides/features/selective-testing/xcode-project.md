---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Projeto Xcode {#xcode-project}

> REQUISITOS [!IMPORTANTE]
> - Uma conta e um projeto
>   <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>

Você pode executar os testes de seus projetos Xcode seletivamente através da
linha de comando. Para isso, você pode anexar seu comando `xcodebuild` com
`tuist` - por exemplo, `tuist xcodebuild test -scheme App`. O comando faz o hash
do seu projeto e, em caso de sucesso, persiste os hashes para determinar o que
foi alterado em execuções futuras.

Em execuções futuras `tuist xcodebuild test` utiliza transparentemente os hashes
para filtrar os testes para executar apenas os que foram alterados desde a
última execução de teste bem sucedida.

Por exemplo, supondo o seguinte gráfico de dependências:

- `A característicaA` tem testes `FeatureATests`, e depende de `Core`
- `FeatureB` tem testes `FeatureBTests`, e depende de `Core`
- `O núcleo` tem testes `CoreTests`

`tuist xcodebuild test` comportar-se-á como tal:

| Ação                               | Descrição                                                            | Estado interno                                                             |
| ---------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `tuist xcodebuild test` invocation | Executa os testes em `CoreTests`, `FeatureATests`, e `FeatureBTests` | Os hashes de `FeatureATests`, `FeatureBTests` e `CoreTests` são mantidos   |
| `FuncionalidadeA` é atualizado     | O programador modifica o código de um destino                        | Igual ao anterior                                                          |
| `tuist xcodebuild test` invocation | Executa os testes em `FeatureATests` porque o seu hash foi alterado  | O novo hash de `FeatureATests` é mantido                                   |
| `O núcleo` está atualizado         | O programador modifica o código de um destino                        | Igual ao anterior                                                          |
| `tuist xcodebuild test` invocation | Executa os testes em `CoreTests`, `FeatureATests`, e `FeatureBTests` | O novo hash de `FeatureATests` `FeatureBTests`, e `CoreTests` são mantidos |

Para utilizar `tuist xcodebuild test` no seu CI, siga as instruções no
<LocalizedLink href="/guides/integrations/continuous-integration">Guia de
integração contínua</LocalizedLink>.

Veja o seguinte vídeo para ver os testes selectivos em ação:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
