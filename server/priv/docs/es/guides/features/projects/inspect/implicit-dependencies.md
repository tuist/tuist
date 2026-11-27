---
{
  "title": "Importaciones implícitas",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Aprende a usar Tuist para encontrar importaciones implícitas."
}
---
# Importaciones implícitas {#implicit-imports}

Para aliviar la complejidad de mantener un grafo de proyecto de Xcode con proyectos de Xcode sin procesar, Apple diseñó el sistema de compilación de manera que permite definir dependencias de forma implícita. Esto significa que un producto, por ejemplo una app, puede depender de un framework aunque no declare la dependencia explícitamente. A pequeña escala esto funciona bien, pero a medida que el grafo del proyecto gana en complejidad, la naturaleza implícita puede manifestarse como compilaciones incrementales poco fiables o funcionalidades basadas en el editor, como las previews o la finalización de código.

El problema es que no puedes evitar que se produzcan dependencias implícitas. Cualquier persona desarrolladora puede añadir una sentencia `import` a su código Swift y se creará la dependencia implícita. Aquí es donde entra Tuist. Tuist ofrece un comando para inspeccionar las dependencias implícitas mediante análisis estático del código de tu proyecto. El siguiente comando mostrará las dependencias implícitas de tu proyecto:

```bash
tuist inspect dependencies --only implicit
```

Si el comando detecta alguna importación implícita, finaliza con un código de salida distinto de cero.

> [!TIP]
> **Validar en CI**
>
> Recomendamos encarecidamente ejecutar este comando como parte de tu flujo de <.localized_link href="/guides/integrations/continuous-integration">integración continua</.localized_link> cada vez que se suba nuevo código al repositorio remoto.


> [!WARNING]
> **No se detectan todos los casos implícitos**
>
> Dado que Tuist se basa en análisis estático de código para detectar dependencias implícitas, es posible que no capture todos los casos. Por ejemplo, Tuist no puede interpretar importaciones condicionales mediante directivas del compilador en el código.
