---
{
  "title": "Documentación",
  "titleTemplate": ":title · Código · Colaboradores · Tuist",
  "description": "Contribuye al sitio de documentación de Tuist."
}
---
# Documentación {#docs}

Fuente: [github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## Para qué sirve {#what-it-is-for}

El sitio de documentación aloja la documentación del producto y para colaboradores de Tuist. Forma parte del servidor de Tuist, una aplicación Phoenix, que renderiza las páginas Markdown en `server/priv/docs/en` en `/docs`.

## Cómo contribuir {#how-to-contribute}

Edita las páginas en inglés en `server/priv/docs/en`. Las traducciones se gestionan por separado, así que no edites los demás directorios de idiomas. La barra lateral se define en `server/lib/tuist/docs_sidebar.ex`; añade nuevas páginas allí para que los lectores puedan encontrarlas.

Cuando varias páginas comparten el mismo texto, por ejemplo, la misma sección entre sistemas de compilación, colócalo en un archivo cuyo nombre empiece por `_` junto a esas páginas e inclúyelo con un comentario HTML `@snippet:` que apunte al archivo, como hacen las páginas de tests inestables. Los archivos que empiezan por `_` no se publican como páginas independientes.

### Configuración local {#set-up-locally}

Ejecuta el servidor desde el directorio `server`, siguiendo sus [instrucciones de configuración](https://github.com/tuist/tuist/blob/main/server/AGENTS.md):

```bash
cd server
mise install
mise run dev
```

Luego abre [http://localhost:8080/en/docs](http://localhost:8080/en/docs).

### Contenido generado {#generated-content}

La referencia de la CLI se genera a partir de la especificación de comandos de la última versión de la CLI, por lo que no es necesario construirla localmente.

La referencia de la API de ProjectDescription se aloja por separado como un sitio DocC en [projectdescription.tuist.dev](https://projectdescription.tuist.dev). Para construirla localmente, ejecuta `mise run docs:project-description` desde la raíz del repositorio.
