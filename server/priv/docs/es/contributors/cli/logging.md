---
{
  "title": "Registro de eventos",
  "titleTemplate": ":title · CLI · Colaboradores · Tuist",
  "description": "Cómo funciona el registro de eventos en la CLI de Tuist y directrices para colaboradores."
}
---
# Registro {#logging}

La CLI adopta la interfaz de registro [swift-log](https://github.com/apple/swift-log). El paquete abstrae los detalles de implementación del registro, lo que permite que la CLI sea independiente del backend de registro. El logger se inyecta como dependencia mediante task locals y se puede acceder a él en cualquier lugar con:

```bash
Logger.current
```

> [!NOTE]
> Los task locals no propagan el valor al usar `Dispatch` o tareas separadas, por lo que si los usas, deberás obtenerlo y pasarlo a la operación asíncrona.


## Qué registrar {#what-to-log}

Los registros no son la interfaz de usuario de la CLI. Son una herramienta para diagnosticar problemas cuando surgen. Por lo tanto, cuanta más información proporciones, mejor. Al crear nuevas funcionalidades, ponte en el lugar de un desarrollador que se encuentra con un comportamiento inesperado y piensa qué información le resultaría útil. Asegúrate de usar el [nivel de registro](https://www.swift.org/documentation/server/guides/libraries/log-levels.html) adecuado. De lo contrario, los desarrolladores no podrán filtrar el ruido.
