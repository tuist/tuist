---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Começar {#get-started}

A forma mais fácil de começar a utilizar o Tuist em qualquer diretório ou no
diretório do seu projeto Xcode ou espaço de trabalho:

::: grupo de códigos

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
:::

O comando irá guiá-lo através dos passos para
<LocalizedLink href="/guides/features/projects">criar um projeto
gerado</LocalizedLink> ou integrar um projeto ou espaço de trabalho Xcode
existente. Ajuda-o a ligar a sua configuração ao servidor remoto, dando-lhe
acesso a funcionalidades como
<LocalizedLink href="/guides/features/selective-testing">testes
selectivos</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">visualizações</LocalizedLink> e
o <LocalizedLink href="/guides/features/registry">registo</LocalizedLink>.

> [NOTA] MIGRAR UM PROJECTO EXISTENTE Se pretender migrar um projeto existente
> para projectos gerados para melhorar a experiência do programador e tirar
> partido da nossa
> <LocalizedLink href="/guides/features/cache">cache</LocalizedLink>, consulte o
> nosso
> <LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">guia
> de migração</LocalizedLink>.
