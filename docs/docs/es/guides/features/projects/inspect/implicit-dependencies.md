---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# Importaciones implícitas {#implicit-imports}

Para aliviar la complejidad de mantener un gráfico de proyecto Xcode con un
proyecto Xcode en bruto, Apple diseñó el sistema de compilación de forma que
permite definir dependencias implícitamente. Esto significa que un producto, por
ejemplo una app, puede depender de un framework, incluso sin declarar la
dependencia explícitamente. A pequeña escala, esto está bien, pero a medida que
el gráfico del proyecto crece en complejidad, la implicitud puede manifestarse
como construcciones incrementales poco fiables o características basadas en el
editor, como vistas previas o finalización de código.

El problema es que no se puede evitar que se produzcan dependencias implícitas.
Cualquier desarrollador puede añadir una declaración `import` a su código Swift,
y se creará la dependencia implícita. Aquí es donde entra Tuist. Tuist
proporciona un comando para inspeccionar las dependencias implícitas analizando
estáticamente el código de tu proyecto. El siguiente comando mostrará las
dependencias implícitas de tu proyecto:

```bash
tuist inspect implicit-imports
```

Si el comando detecta alguna importación implícita, sale con un código de salida
distinto de cero.

::: tip VALIDAR EN CI
<!-- -->
Recomendamos encarecidamente ejecutar este comando como parte de su
<LocalizedLink href="/guides/features/automate/continuous-integration">comando de integración continua</LocalizedLink> cada vez que se publique nuevo código.
<!-- -->
:::

::: advertencia NO SE DETECTAN TODOS LOS CASOS IMPLÍCITOS
<!-- -->
Dado que Tuist se basa en el análisis estático del código para detectar
dependencias implícitas, es posible que no detecte todos los casos. Por ejemplo,
Tuist es incapaz de entender las importaciones condicionales a través de
directivas del compilador en el código.
<!-- -->
:::
