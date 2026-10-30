---
{
  "title": "Informes de incidencias",
  "titleTemplate": ":title · Colaboradores · Tuist",
  "description": "Aprende a contribuir a Tuist informando de errores"
}
---
# Informes de incidencias {#issue-reporting}

Como usuario de Tuist, puedes encontrarte con errores o comportamientos inesperados. Si te ocurre, te animamos a que los informes para que podamos corregirlos.

## GitHub Issues es nuestra plataforma de tickets {#github-issues-is-our-ticketing-platform}

Las incidencias deben reportarse en GitHub como [GitHub issues](https://github.com/tuist/tuist/issues), no en Slack ni en otras plataformas. GitHub es mejor para rastrear y gestionar incidencias, está más cerca del código base y nos permite seguir el progreso de la incidencia. Además, fomenta una descripción detallada del problema, lo que obliga al informante a reflexionar sobre el problema y aportar más contexto.

## El contexto es crucial {#context-is-crucial}

Una incidencia sin suficiente contexto se considerará incompleta y se pedirá al autor que aporte contexto adicional. Si no se proporciona, la incidencia se cerrará. Piénsalo así: cuanto más contexto aportes, más fácil será para nosotros entender el problema y solucionarlo. Por tanto, si quieres que tu incidencia se resuelva, aporta todo el contexto posible. Intenta responder a las siguientes preguntas:

- ¿Qué intentabas hacer?
- ¿Cómo es tu grafo?
- ¿Qué versión de Tuist estás usando?
- ¿Esto te está bloqueando?

También requerimos que proporciones un **proyecto reproducible** mínimo.

## Proyecto reproducible {#reproducible-project}

### ¿Qué es un proyecto reproducible? {#what-is-a-reproducible-project}

Un proyecto reproducible es un pequeño proyecto de Tuist para demostrar un problema; a menudo este problema está causado por un error en Tuist. Tu proyecto reproducible debe contener el mínimo de funcionalidades necesarias para demostrar claramente el error.

### ¿Por qué deberías crear un caso de test reproducible? {#why-should-you-create-a-reproducible-test-case}

Un proyecto reproducible nos permite aislar la causa de un problema, que es el primer paso para solucionarlo. La parte más importante de cualquier informe de error es describir los pasos exactos necesarios para reproducir el error.

Un proyecto reproducible es una excelente manera de compartir un entorno específico que provoca un error. Tu proyecto reproducible es la mejor forma de ayudar a quienes quieren ayudarte.

### Pasos para crear un proyecto reproducible {#steps-to-create-a-reproducible-project}

- Crea un nuevo repositorio git.
- Inicializa un proyecto usando `tuist init` en el directorio del repositorio.
- Añade el código necesario para recrear el error que has visto.
- Publica el código (tu cuenta de GitHub es un buen lugar para hacerlo) y luego enlázalo al crear una incidencia.

### Beneficios de los proyectos reproducibles {#benefits-of-reproducible-projects}

- **Menor superficie:** Al eliminar todo excepto el error, no tienes que indagar para encontrar el fallo.
- **No hace falta publicar código secreto:** Es posible que no puedas publicar tu sitio principal (por muchas razones). Recrear una pequeña parte como un caso de test reproducible te permite demostrar públicamente un problema sin exponer ningún código secreto.
- **Prueba del error:** A veces un error está causado por alguna combinación de ajustes en tu máquina. Un caso de test reproducible permite a los colaboradores descargar tu compilación y probarla también en sus máquinas. Esto ayuda a verificar y acotar la causa de un problema.
- **Obtén ayuda para corregir tu error:** Si otra persona puede reproducir tu problema, suele tener buenas posibilidades de solucionarlo. Es casi imposible corregir un error sin poder reproducirlo primero.
