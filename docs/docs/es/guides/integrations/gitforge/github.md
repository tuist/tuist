---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# Integración en GitHub {#github}

Los repositorios Git son la pieza central de la gran mayoría de los proyectos de
software. Nos integramos con GitHub para ofrecer información de Tuist
directamente en tus pull requests y ahorrarte algunas configuraciones, como la
sincronización de tu rama por defecto.

## Configuración {#setup}

Instala la [Tuist GitHub app](https://github.com/marketplace/tuist). Una vez
instalada, tendrás que indicar a Tuist la URL de tu repositorio, por ejemplo:

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
