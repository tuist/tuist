---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Registro {#logging}

La CLI adopta la interfaz [swift-log](https://github.com/apple/swift-log) para
el registro. El paquete abstrae los detalles de implementación del registro, lo
que permite que la CLI sea independiente del backend de registro. El registrador
se inyecta como dependencia mediante variables locales de tarea y se puede
acceder a él desde cualquier lugar utilizando:

```bash
Logger.current
```

::: info
<!-- -->
Las tareas locales no propagan el valor cuando se utiliza `Dispatch` o tareas
separadas, por lo que si las utiliza, deberá obtenerlo y pasarlo a la operación
asíncrona.
<!-- -->
:::

## Qué registrar {#what-to-log}

Los registros no son la interfaz de usuario de la CLI. Son una herramienta para
diagnosticar problemas cuando surgen. Por lo tanto, cuanta más información
proporciones, mejor. Cuando crees nuevas funciones, ponte en el lugar de un
desarrollador que se encuentra con un comportamiento inesperado y piensa qué
información le resultaría útil. Asegúrate de utilizar el [nivel de registro]
adecuado. De lo contrario, los desarrolladores no podrán filtrar el ruido.
