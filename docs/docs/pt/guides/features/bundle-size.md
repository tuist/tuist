---
{
  "title": "Bundle Size",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Tamanho do pacote {#bundle-size}

> REQUISITOS [!IMPORTANTE]
> - Uma conta e um projeto
>   <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>

À medida que adiciona mais funcionalidades à sua aplicação, o tamanho do seu
pacote de aplicações continua a crescer. Embora parte do crescimento do tamanho
do pacote seja inevitável à medida que envia mais código e activos, existem
muitas formas de minimizar esse crescimento, por exemplo, assegurando que os
seus activos não são duplicados nos seus pacotes ou retirando símbolos binários
não utilizados. A Tuist fornece-lhe ferramentas e informações para ajudar a
manter o tamanho da sua aplicação reduzido - e também monitorizamos o tamanho da
sua aplicação ao longo do tempo.

## Utilização {#usage}

Para analisar um pacote, pode utilizar o comando `tuist inspect bundle`:

::: grupo de códigos
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
:::

O comando `tuist inspect bundle` analisa o pacote e fornece-lhe uma ligação para
ver uma visão geral pormenorizada do pacote, incluindo uma análise do conteúdo
do pacote ou uma análise do módulo:

![Feixe analisado](/images/guides/features/bundle-size/analyzed-bundle.png)

## Integração contínua {#continuous-integration}

Para rastrear o tamanho do pacote ao longo do tempo, você precisará analisar o
pacote no CI. Primeiro, você precisará garantir que seu CI seja
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticado</LocalizedLink>:

Um exemplo de fluxo de trabalho para GitHub Actions poderia então ter o seguinte
aspeto:

```yaml
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_CONFIG_TOKEN: ${{ secrets.TUIST_CONFIG_TOKEN }}
```

Uma vez configurado, poderá ver como o tamanho do seu pacote evolui ao longo do
tempo:

![Gráfico de tamanho de
pacote](/images/guides/features/bundle-size/bundle-size-graph.png)

## Comentários do pedido pull/merge {#pullmerge-request-comments}

> [!IMPORTANTE] É NECESSÁRIA A INTEGRAÇÃO COM A PLATAFORMA GIT Para obter
> comentários automáticos de pedidos de pull/merge, integre o seu projeto
> <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
> com uma plataforma
> <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.

Assim que o seu projeto Tuist estiver ligado à sua plataforma Git, como o
[GitHub](https://github.com), o Tuist irá publicar um comentário diretamente nos
seus pedidos de pull/merge sempre que executar `tuist inspect bundle`: ![GitHub
app comment with inspected
bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)
