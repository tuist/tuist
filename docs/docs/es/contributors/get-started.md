---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# Empezar {#get-started}

Si tienes experiencia creando aplicaciones para plataformas Apple, como iOS,
añadir código a Tuist no debería ser muy diferente. Hay dos diferencias en
comparación con el desarrollo de aplicaciones que vale la pena mencionar:

- **Las interacciones con las CLI se producen a través del terminal.** El
  usuario ejecuta Tuist, que realiza la tarea deseada, y luego vuelve con éxito
  o con un código de estado. Durante la ejecución, el usuario puede ser
  notificado enviando información de salida a la salida estándar y al error
  estándar. No hay gestos, ni interacciones gráficas, sólo la intención del
  usuario.

- **No hay runloop que mantenga el proceso vivo a la espera de entrada**, como
  ocurre en una aplicación iOS cuando la aplicación recibe eventos del sistema o
  del usuario. CLI se ejecuta en su proceso y termina cuando el trabajo está
  hecho. El trabajo asíncrono se puede realizar utilizando APIs del sistema como
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  o [structured
  concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency),
  pero hay que asegurarse de que el proceso se está ejecutando mientras se
  ejecuta el trabajo asíncrono. De lo contrario, el proceso terminará el trabajo
  asíncrono.

Si no tienes experiencia con Swift, te recomendamos [el libro oficial de
Apple](https://docs.swift.org/swift-book/) para familiarizarte con el lenguaje y
los elementos más utilizados de la API de la Fundación.

## Requisitos mínimos {#minimum-requirements}

Para cotizar a Tuist, los requisitos mínimos son:

- macOS 14.0+
- Xcode 16.3+

## Configurar el proyecto localmente {#set-up-the-project-locally}

Para empezar a trabajar en el proyecto, podemos seguir los pasos que se indican
a continuación:

- Clone el repositorio ejecutando: `git clone git@github.com:tuist/tuist.git`
- [Instalar](https://mise.jdx.dev/getting-started.html) Mise para aprovisionar
  el entorno de desarrollo.
- Ejecuta `mise install` para instalar las dependencias del sistema necesarias
  para Tuist
- Ejecuta `tuist install` para instalar las dependencias externas que necesita
  Tuist
- (Opcional) Ejecute `tuist auth login` para obtener acceso a la
  <LocalizedLink href="/guides/features/cache">Caché de Tuist</LocalizedLink>
- Ejecuta `tuist generate` para generar el proyecto Tuist Xcode usando el propio
  Tuist

**El proyecto generado se abre automáticamente**. Si necesita abrirlo de nuevo
sin generarlo, ejecute `abra Tuist.xcworkspace` (o utilice Finder).

::: info XED .
<!-- -->
Si intentas abrir el proyecto usando `xed .`, abrirá el paquete, y no el
proyecto generado por Tuist. Te recomendamos que utilices el proyecto generado
por Tuist para probar la herramienta.
<!-- -->
:::

## Editar el proyecto {#edit-the-project}

Si necesitas editar el proyecto, por ejemplo para añadir dependencias o ajustar
objetivos, puedes usar el comando
<LocalizedLink href="/guides/features/projects/editing">`tuist edit` </LocalizedLink>. Esto apenas se utiliza, pero es bueno saber que existe.

## Corre Tuist {#run-tuist}

### Desde Xcode {#from-xcode}

Para ejecutar `tuist` desde el proyecto Xcode generado, edite el esquema
`tuist`, y establezca los argumentos que desea pasar al comando. Por ejemplo,
para ejecutar el comando `tuist generate`, puede establecer los argumentos a
`generate --no-open` para evitar que el proyecto se abra después de la
generación.

![Ejemplo de configuración de un esquema para ejecutar el comando generate con
Tuist](/images/contributors/scheme-arguments.png)

También tendrá que establecer el directorio de trabajo en la raíz del proyecto
que se está generando. Puede hacerlo utilizando el argumento `--path`, que todos
los comandos aceptan, o configurando el directorio de trabajo en el esquema como
se muestra a continuación:


![Un ejemplo de cómo establecer el directorio de trabajo para ejecutar
Tuist](/images/contributors/scheme-working-directory.png)

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
El CLI `tuist` depende de la presencia del framework `ProjectDescription` en el
directorio de productos construidos. Si `tuist` no se ejecuta porque no
encuentra el framework `ProjectDescription`, construya primero el esquema
`Tuist-Workspace`.
<!-- -->
:::

### Desde el terminal {#from-the-terminal}

Puedes ejecutar `tuist` utilizando el propio Tuist a través de su comando `run`:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

También puede ejecutarlo directamente a través del gestor de paquetes Swift:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
