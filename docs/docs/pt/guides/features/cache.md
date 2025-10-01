---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---
# Cache {#cache}

> REQUISITOS [!IMPORTANTE]
> - Um projeto gerado por
>   <LocalizedLink href="/guides/features/projects"></LocalizedLink>
> - Uma conta e um projeto
>   <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>

O sistema de build do Xcode fornece [builds
incrementais](https://en.wikipedia.org/wiki/Incremental_build_model), aumentando
a eficiência em circunstâncias normais. No entanto, esta funcionalidade é
insuficiente em ambientes de [Integração Contínua
(CI)](https://en.wikipedia.org/wiki/Continuous_integration), onde os dados
essenciais para compilações incrementais não são partilhados entre diferentes
compilações. Além disso, os desenvolvedores do **frequentemente redefinem esses
dados localmente para solucionar problemas complexos de compilação**, levando a
compilações limpas mais frequentes. Isto faz com que as equipas passem demasiado
tempo à espera que as compilações locais terminem ou que os pipelines de
integração contínua forneçam feedback sobre os pedidos pull. Além disso, a
mudança frequente de contexto num ambiente deste tipo agrava esta
improdutividade.

O Tuist aborda esses desafios de forma eficaz com seu recurso de cache. Esta
ferramenta optimiza o processo de construção através da colocação em cache de
binários compilados, reduzindo significativamente os tempos de construção tanto
em ambientes de desenvolvimento local como de CI. Esta abordagem não só acelera
os ciclos de feedback como também minimiza a necessidade de mudança de contexto,
aumentando a produtividade.

## Aquecimento {#warming}

Tuist utiliza eficientemente hashes</LocalizedLink> para cada alvo no gráfico de
dependência para detetar alterações. Utilizando esses dados, ele constrói e
atribui identificadores exclusivos a binários derivados desses alvos. No momento
da geração do grafo, o Tuist substitui sem problemas os alvos originais pelas
suas versões binárias correspondentes.

Esta operação, conhecida como *"warming",* produz binários para uso local ou
para partilhar com colegas de equipa e ambientes CI via Tuist. O processo de
aquecimento da cache é direto e pode ser iniciado com um simples comando:


```bash
tuist cache
```

O comando reutiliza binários para acelerar o processo.

## Utilização {#usage}

Por padrão, quando os comandos do Tuist necessitam da geração do projeto, eles
substituem automaticamente as dependências por seus equivalentes binários do
cache, se disponíveis. Além disso, se você especificar uma lista de alvos para
focar, o Tuist também substituirá quaisquer alvos dependentes por seus binários
em cache, desde que estejam disponíveis. Para aqueles que preferem uma abordagem
diferente, há uma opção para desativar esse comportamento inteiramente usando um
sinalizador específico:

::: grupo de códigos
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```
:::

> [AVISO] O armazenamento em cache binário é uma funcionalidade concebida para
> fluxos de trabalho de desenvolvimento, como a execução da aplicação num
> simulador ou dispositivo, ou a execução de testes. Não se destina a
> compilações de lançamento. Ao arquivar a aplicação, gere um projeto com as
> fontes utilizando a bandeira `--no-binary-cache`.

## Produtos suportados {#produtos suportados}

Apenas os seguintes produtos de destino são armazenados em cache pelo Tuist:

- Estruturas (estáticas e dinâmicas) que não dependem do
  [XCTest](https://developer.apple.com/documentation/xctest)
- Pacotes
- Macros Swift

Estamos a trabalhar no suporte de bibliotecas e alvos que dependem do XCTest.

> [Quando um alvo é não armazenável em cache, isso faz com que os alvos a
> montante também não sejam armazenáveis em cache. Por exemplo, se tiver o
> gráfico de dependências `A &gt; B`, em que A depende de B, se B não for
> armazenável em cache, A também não será armazenável em cache.

## Eficiência {#efficiency}

O nível de eficiência que pode ser alcançado com o cache binário depende muito
da estrutura do gráfico. Para obter os melhores resultados, recomendamos o
seguinte:

1. Evite gráficos de dependência muito aninhados. Quanto mais raso for o
   gráfico, melhor.
2. Definir dependências com alvos de protocolo/interface em vez de alvos de
   implementação, e implementações de injeção de dependências a partir dos alvos
   mais elevados.
3. Dividir os alvos frequentemente modificados em alvos mais pequenos cuja
   probabilidade de alteração é menor.

As sugestões acima fazem parte da
<LocalizedLink href="/guides/features/projects/tma-architecture">Arquitetura
Modular</LocalizedLink>, que propomos como uma forma de estruturar os seus
projectos para maximizar os benefícios não só do caching binário mas também das
capacidades do Xcode.

## Configuração recomendada {#configuração recomendada}

Recomendamos ter um trabalho de CI que **é executado em cada commit no ramo
principal** para aquecer o cache. Isso irá garantir que o cache sempre contenha
binários para as mudanças em `main` para que o ramo local e CI construam
incrementalmente sobre eles.

> [O comando `tuist cache` também utiliza a cache binária para acelerar o
> aquecimento.

Seguem-se alguns exemplos de fluxos de trabalho comuns:

### Um programador começa a trabalhar numa nova funcionalidade {#a-developer-starts-to-work-on-a-new-feature}

1. Criam um novo ramo a partir de `main`.
2. Executam `tuist geram`.
3. Tuist puxa os binários mais recentes de `main` e gera o projeto com eles.

### Um programador faz push de alterações a montante {#a-developer-pushes-changes-upstream}

1. O pipeline de CI irá executar `tuist build` ou `tuist test` para construir ou
   testar o projeto.
2. O fluxo de trabalho irá obter os binários mais recentes de `main` e gerar o
   projeto com eles.
3. Em seguida, constrói ou testa o projeto de forma incremental.

## Resolução de problemas {#troubleshooting}

### Não utiliza binários para os meus alvos {#it-doesnt-use-binaries-for-my-targets}

Certifique-se de que os
<LocalizedLink href="/guides/features/projects/hashing#debugging">hashes são
determinísticos</LocalizedLink> entre ambientes e execuções. Isso pode acontecer
se o projeto tiver referências ao ambiente, por exemplo, através de caminhos
absolutos. Você pode usar o comando `diff` para comparar os projetos gerados por
duas invocações consecutivas de `tuist generate` ou entre ambientes ou
execuções.

Certifique-se também de que o destino não depende direta ou indiretamente de um
destino <LocalizedLink href="/guides/features/cache#supported-products">não
armazenável em cache</LocalizedLink>.
