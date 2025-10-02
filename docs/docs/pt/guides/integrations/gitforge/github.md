---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# Integração do GitHub {#github}

Os repositórios Git são a peça central da grande maioria dos projetos de
software por aí. Nós integramos com o GitHub para fornecer insights Tuist
diretamente nos seus pull requests e para economizar algumas configurações, como
a sincronização do seu branch padrão.

## Configuração {#setup}

Instale o [Tuist GitHub app](https://github.com/marketplace/tuist). Uma vez
instalado, terá de indicar ao Tuist o URL do seu repositório, tal como:

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
