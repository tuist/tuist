---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Empezar {#get-started}

La forma más fácil de empezar con Tuist en cualquier directorio o en el
directorio de tu proyecto Xcode o espacio de trabajo:

::: grupo de códigos

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

El comando le guiará a través de los pasos para
<LocalizedLink href="/guides/features/projects">crear un proyecto generado</LocalizedLink> o integrar un proyecto o espacio de trabajo de Xcode
existente. Le ayudará a conectar su configuración al servidor remoto, dándole
acceso a funciones como
<LocalizedLink href="/guides/features/selective-testing">pruebas selectivas</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">previews</LocalizedLink>, y el
<LocalizedLink href="/guides/features/registry">registro</LocalizedLink>.

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
Si desea migrar un proyecto existente a proyectos generados para mejorar la
experiencia del desarrollador y aprovechar nuestra
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>, consulte
nuestra
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">guía de migración</LocalizedLink>.
<!-- -->
:::
