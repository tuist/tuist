---
{
  "title": "Importaciones implícitas",
  "titleTemplate": ":title · Inspectar · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar Tuist para encontrar importaciones implícitas."
}
---
# Importaciones implícitas {#implicit-imports}

Para reducir la complejidad de mantener un grafo de proyectos de Xcode con proyectos nativos de Xcode, Apple diseñó el sistema de compilación de forma que las dependencias puedan definirse de manera implícita. Esto significa que un producto, por ejemplo una app, puede depender de un framework sin declarar explícitamente la dependencia. A pequeña escala esto no supone un problema, pero a medida que el grafo del proyecto gana en complejidad, esa implícitud puede traducirse en compilaciones incrementales poco fiables o en funcionalidades basadas en el editor, como las previsualizaciones o la finalización de código.

El problema es que no puedes evitar que aparezcan dependencias implícitas. Cualquier persona desarrolladora puede añadir una sentencia `import` a su código Swift y se creará la dependencia implícita. Aquí es donde entra Tuist. Tuist ofrece un comando para inspeccionar las dependencias implícitas mediante análisis estático del código de tu proyecto. El siguiente comando mostrará las dependencias implícitas de tu proyecto:

```bash
tuist inspect dependencies --only implicit
```

Si el comando detecta alguna importación implícita, finaliza con un código de salida distinto de cero.

> [!TIP]
> **Validar en CI**
>
> Recomendamos encarecidamente ejecutar este comando como parte de tu flujo de <.localized_link href="/guides/integrations/continuous-integration">integración continua</.localized_link> cada vez que se envíe nuevo código al repositorio remoto.


> [!WARNING]
> **No se detectan todos los casos implícitos**
>
> Dado que Tuist se basa en el análisis estático de código para detectar dependencias implícitas, es posible que no capture todos los casos. Por ejemplo, Tuist no puede interpretar importaciones condicionales mediante directivas del compilador en el código.
