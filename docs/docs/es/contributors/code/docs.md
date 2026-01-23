---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# Documentos {#docs}

Fuente:
[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## Para qué sirve {#what-it-is-for}

El sitio de documentación aloja la documentación de los productos y
colaboradores de Tuist. Está construido con VitePress.

## Cómo contribuir {#how-to-contribute}

### Configurar localmente {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### Datos generados opcionales {#optional-generated-data}

Incorporamos algunos datos generados en los documentos:

- Datos de referencia de la CLI: `mise run generate-cli-docs`
- Datos de referencia del manifiesto del proyecto: `mise run
  generate-manifests-docs`

Son opcionales. Los documentos se muestran sin ellos, así que solo utilícelos
cuando necesite actualizar el contenido generado.
