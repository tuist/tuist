---
{
  "title": "Registro",
  "titleTemplate": ":title · CLI · Contribuidores · Tuist",
  "description": "Cómo funciona el registro en la CLI de Tuist y directrices para contribuidores."
}
---
# Registro {#logging}

La CLI adopta la interfaz de registro [swift-log](https://github.com/apple/swift-log). El paquete abstrae los detalles de implementación del registro, lo que permite que la CLI sea independiente del backend de registro. El logger se inyecta como dependencia mediante task locals y puede accederse en cualquier lugar usando:

```bash
Logger.current
```

> [!NOTE]
> Los task locals no propagan el valor al usar `Dispatch` o tareas separadas, por lo que si las usas, deberás obtenerlo y pasarlo a la operación asíncrona.


## Qué registrar {#what-to-log}

Los logs no son la interfaz de usuario de la CLI. Son una herramienta para diagnosticar problemas cuando surgen. Por lo tanto, cuanta más información proporciones, mejor. Al desarrollar nuevas funcionalidades, ponte en el lugar de un desarrollador que se encuentra con un comportamiento inesperado y piensa qué información le sería útil. Asegúrate de usar el [nivel de log](https://www.swift.org/documentation/server/guides/libraries/log-levels.html) adecuado. De lo contrario, los desarrolladores no podrán filtrar el ruido.
