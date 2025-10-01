---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Projeto Xcode {#xcode-project}

Para adicionar pacotes utilizando o registo no seu projeto Xcode, utilize a IU
predefinida do Xcode. Você pode procurar pacotes no registro clicando no botão
`+` na guia `Dependências de pacotes` no Xcode. Se o pacote estiver disponível
no registo, verá o registo `tuist.dev` no canto superior direito:

![Adicionando dependências de
pacotes](/images/guides/features/build/registry/registry-add-package.png)

> [NOTA] Atualmente, o Xcode não suporta a substituição automática de pacotes de
> controlo de origem pelos seus equivalentes de registo. Terá de remover
> manualmente o pacote de controlo de origem e adicionar o pacote de registo
> para acelerar a resolução.
