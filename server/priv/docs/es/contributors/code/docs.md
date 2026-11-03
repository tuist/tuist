---
{
  "title": "Documentación",
  "titleTemplate": ":title · Código · Colaboradores · Tuist",
  "description": "Contribuye al sitio de documentación de Tuist."
}
---
# Documentación {#docs}

Fuente: [github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## Para qué sirve {#what-it-is-for}

El sitio de documentación aloja la documentación del producto y para colaboradores de Tuist. Está construido con VitePress.

## Cómo contribuir {#how-to-contribute}

### Configuración local {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### Datos generados opcionales {#optional-generated-data}

Incluimos algunos datos generados en la documentación:

- Datos de referencia de la CLI: `mise run generate-cli-docs`

Son opcionales. La documentación se renderiza sin ellos, así que ejecútalos solo cuando necesites actualizar el contenido generado.

La referencia de la API de ProjectDescription se aloja por separado como un sitio DocC en [projectdescription.tuist.dev](https://projectdescription.tuist.dev). Para compilarlo localmente, ejecuta `mise run docs:project-description` desde la raíz del repositorio.
