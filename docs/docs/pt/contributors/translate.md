---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Traduzir {#translate}

As línguas podem ser barreiras à compreensão. Queremos garantir que o Tuist é
acessível ao maior número possível de pessoas. Se fala uma língua que não é
suportada pelo Tuist, pode ajudar-nos traduzindo as várias superfícies do Tuist.

Uma vez que a manutenção das traduções é um esforço contínuo, adicionamos
línguas à medida que vemos colaboradores dispostos a ajudar-nos a mantê-las. As
seguintes línguas são atualmente suportadas:

- Inglês
- coreano
- Japonês
- Russo
- Chinês
- espanhol
- Português

> [Pedir uma nova língua Se acha que o Tuist teria vantagem em suportar uma nova
> língua, por favor crie um novo [tópico no fórum da
> comunidade](https://community.tuist.io/c/general/4) para discutir o assunto
> com a comunidade.

## Como traduzir {#how-to-translate}

Temos uma instância do [Weblate](https://weblate.org/en-gb/) a correr em
[translate.tuist.dev](https://translate.tuist.dev). Pode ir a [o
projeto](https://translate.tuist.dev/engage/tuist/), criar uma conta e começar a
traduzir.

As traduções são sincronizadas de volta ao repositório de origem usando
solicitações pull do GitHub que os mantenedores revisarão e mesclarão.

> [IMPORTANTE] NÃO MODIFIQUE OS RECURSOS NA LÍNGUA DE DESTINO O Weblate segmenta
> os ficheiros para associar as línguas de origem e de destino. Se modificar a
> língua de origem, quebrará a ligação e a reconciliação poderá produzir
> resultados inesperados.

## Diretrizes

Seguem-se as diretrizes que seguimos quando traduzimos.

### Contentores personalizados e alertas de GitHub {#custom-containers-and-github-alerts}

Ao traduzir [contentores
personalizados](https://vitepress.dev/guide/markdown#custom-containers) ou
[Alertas
GitHub](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts),
traduzir apenas o título e o conteúdo **mas não o tipo de alerta**.

::: detalhes Exemplo com alerta de GitHub
```markdown
    > [!WARNING] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...

    // Instead of
    > [!주의] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...
    ```
:::


::: details Example with custom container
```
    ::: warning 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::

    # Instead of
    ::: 주의 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::
```
:::

### Heading titles {#heading-titles}

When translating headings, only translate tht title but not the id. For example, when translating the following heading:

```
# Adicionar dependências {#add-dependencies}
```

It should be translated as (note the id is not translated):

```
# 의존성 추가하기 {#add-dependencies}
```

```
