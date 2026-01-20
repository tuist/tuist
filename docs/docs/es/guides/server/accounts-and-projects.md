---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# Cuentas y proyectos {#accounts-and-projects}

Algunas funciones de Tuist requieren un servidor que añada persistencia de datos
y pueda interactuar con otros servicios. Para interactuar con el servidor,
necesitas una cuenta y un proyecto que conectes a tu proyecto local.

## Cuentas {#accounts}

Para utilizar el servidor, necesitarás una cuenta. Hay dos tipos de cuentas:

- **Cuenta personal:** Estas cuentas se crean automáticamente cuando te
  registras y se identifican mediante un identificador que se obtiene del
  proveedor de identidad (por ejemplo, GitHub) o de la primera parte de la
  dirección de correo electrónico.
- **Cuenta de organización:** Estas cuentas se crean manualmente y se
  identifican mediante un identificador definido por el desarrollador. Las
  organizaciones permiten invitar a otros miembros a colaborar en los proyectos.

Si estás familiarizado con [GitHub](https://github.com), el concepto es similar
al suyo, donde puedes tener cuentas personales y de organización, y se
identifican por un *handle* que se utiliza al construir URLs.

::: info CLI-FIRST
<!-- -->
La mayoría de las operaciones para gestionar cuentas y proyectos se realizan a
través de la CLI. Estamos trabajando en una interfaz web que facilitará la
gestión de cuentas y proyectos.
<!-- -->
:::

Puede gestionar la organización a través de los subcomandos bajo
<LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink>.
Para crear una nueva cuenta de organización, ejecute
```bash
tuist organization create {account-handle}
```

## Proyectos {#projects}

Tus proyectos, ya sean de Tuist o de Xcode en bruto, necesitan estar integrados
con tu cuenta a través de un proyecto remoto. Siguiendo con la comparación con
GitHub, es como tener un repositorio local y otro remoto donde empujar tus
cambios. Puedes usar el <LocalizedLink href="/cli/project">`tuist project`</LocalizedLink> para crear y gestionar proyectos.

Los proyectos se identifican mediante un identificador completo, que es el
resultado de concatenar el identificador de la organización y el identificador
del proyecto. Por ejemplo, si tiene una organización con el identificador
`tuist`, y un proyecto con el identificador `tuist`, el identificador completo
sería `tuist/tuist`.

La vinculación entre el proyecto local y el remoto se realiza a través del
fichero de configuración. Si no tienes ninguno, créalo en `Tuist.swift` y añade
el siguiente contenido:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
Tenga en cuenta que hay algunas características como
<LocalizedLink href="/guides/features/cache">binary caching</LocalizedLink> que
requieren que usted tenga un proyecto Tuist. Si utilizas proyectos Xcode sin
procesar, no podrás utilizar estas funciones.
<!-- -->
:::

La URL de tu proyecto se construye utilizando el "handle" completo. Por ejemplo,
el panel de Tuist, que es público, es accesible en
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist), donde `tuist/tuist` es
el nombre completo del proyecto.
