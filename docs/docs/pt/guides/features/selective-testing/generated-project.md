---
{
  "title": "Generated project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with a generated project."
}
---
# Projeto gerado {#projeto gerado}

> REQUISITOS [!IMPORTANTE]
> - Um projeto gerado por
>   <LocalizedLink href="/guides/features/projects"></LocalizedLink>
> - Uma conta e um projeto
>   <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>

Para executar testes seletivamente com seu projeto gerado, use o comando `tuist
test`. O comando
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
seu projeto Xcode da mesma forma que faz para
<LocalizedLink href="/guides/features/cache#cache-warming">aquecer o
cache</LocalizedLink> e, em caso de sucesso, ele persiste os hashes para
determinar o que foi alterado em execuções futuras.

Em execuções futuras `tuist test` utiliza transparentemente os hashes para
filtrar os testes e executar apenas os que foram alterados desde a última
execução de teste bem sucedida.

Por exemplo, supondo o seguinte gráfico de dependências:

- `A característicaA` tem testes `FeatureATests`, e depende de `Core`
- `FeatureB` tem testes `FeatureBTests`, e depende de `Core`
- `O núcleo` tem testes `CoreTests`

`O teste tuista` comportar-se-á como tal:

| Ação                           | Descrição                                                            | Estado interno                                                             |
| ------------------------------ | -------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `teste tuist` invocação        | Executa os testes em `CoreTests`, `FeatureATests`, e `FeatureBTests` | Os hashes de `FeatureATests`, `FeatureBTests` e `CoreTests` são mantidos   |
| `FuncionalidadeA` é atualizado | O programador modifica o código de um destino                        | Igual ao anterior                                                          |
| `teste tuist` invocação        | Executa os testes em `FeatureATests` porque o seu hash foi alterado  | O novo hash de `FeatureATests` é mantido                                   |
| `O núcleo` está atualizado     | O programador modifica o código de um destino                        | Igual ao anterior                                                          |
| `teste tuist` invocação        | Executa os testes em `CoreTests`, `FeatureATests`, e `FeatureBTests` | O novo hash de `FeatureATests` `FeatureBTests`, e `CoreTests` são mantidos |

`tuist test` integra-se diretamente com o cache binário para utilizar tantos
binários do seu armazenamento local ou remoto para melhorar o tempo de
construção ao executar o seu conjunto de testes. A combinação de testes
selectivos com cache de binários pode reduzir drasticamente o tempo necessário
para executar testes no seu CI.

## Testes de IU {#ui-tests}

O Tuist suporta testes selectivos de testes de IU. No entanto, o Tuist precisa
saber o destino com antecedência. Somente se você especificar o parâmetro
`destination`, o Tuist executará os testes de interface do usuário
seletivamente, como:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
