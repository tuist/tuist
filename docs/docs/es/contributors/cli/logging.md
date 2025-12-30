---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Registro {#logging}

La CLI adopta la interfaz [swift-log](https://github.com/apple/swift-log) para
el registro. El paquete abstrae los detalles de implementación de registro,
permitiendo a la CLI ser agnóstica al backend de registro. El registrador se
inyecta en la dependencia utilizando tareas locales y se puede acceder en
cualquier lugar utilizando:

```bash
Logger.current
```

::: info
<!-- -->
Las tareas locales no propagan el valor cuando se utiliza `Dispatch` o tareas
separadas, por lo que si las utiliza, tendrá que obtenerlo y pasarlo a la
operación asíncrona.
<!-- -->
:::

## Qué registrar {#what-to-log}

Los registros no son la interfaz de usuario de la CLI. Son una herramienta para
diagnosticar problemas cuando surgen. Por lo tanto, cuanta más información
proporcione, mejor. Cuando construyas nuevas funcionalidades, ponte en el lugar
de un desarrollador que se encuentra con un comportamiento inesperado, y piensa
qué información le sería útil. Asegúrate de que utilizas el [nivel de
registro](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)
adecuado. De lo contrario, los desarrolladores no podrán filtrar el ruido.
