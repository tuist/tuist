---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# Notificación de problemas {#issue-reporting}

Como usuario de Tuist, es posible que encuentres errores o comportamientos
inesperados. Si es así, te animamos a que los informes para que podamos
solucionarlos.

## GitHub Issues es nuestra plataforma de tickets. {#github-issues-is-our-ticketing-platform}

Los problemas deben informarse en GitHub como [problemas de
GitHub](https://github.com/tuist/tuist/issues) y no en Slack u otras
plataformas. GitHub es mejor para rastrear y gestionar problemas, está más cerca
del código base y nos permite realizar un seguimiento del progreso del problema.
Además, fomenta una descripción detallada del problema, lo que obliga al
informante a pensar en el problema y proporcionar más contexto.

## El contexto es fundamental. {#context-is-crucial}

Una incidencia sin suficiente contexto se considerará incompleta y se pedirá al
autor que proporcione contexto adicional. Si no se proporciona, la incidencia se
cerrará. Piénsalo de esta manera: cuanto más contexto proporciones, más fácil
nos resultará comprender el problema y solucionarlo. Por lo tanto, si quieres
que se solucione tu incidencia, proporciona todo el contexto posible. Intenta
responder a las siguientes preguntas:

- ¿Qué intentabas hacer?
- ¿Cómo se ve tu gráfico?
- ¿Qué versión de Tuist estás utilizando?
- ¿Esto le está impidiendo continuar?

También le pedimos que proporcione un proyecto reproducible mínimo **** .

## Proyecto reproducible. {#reproducible-project}

### ¿Qué es un proyecto reproducible? {#what-is-a-reproducible-project}

Un proyecto reproducible es un pequeño proyecto de Tuist para demostrar un
problema, que a menudo está causado por un error en Tuist. Tu proyecto
reproducible debe contener las características mínimas necesarias para demostrar
claramente el error.

### ¿Por qué debería crear un caso de prueba reproducible? {#why-should-you-create-a-reproducible-test-case}

Un proyecto reproducible nos permite aislar la causa de un problema, ¡lo cual es
el primer paso para solucionarlo! La parte más importante de cualquier informe
de error es describir los pasos exactos necesarios para reproducir el error.

Un proyecto reproducible es una forma estupenda de compartir un entorno
específico que provoca un error. Tu proyecto reproducible es la mejor manera de
ayudar a las personas que quieren ayudarte.

### Pasos para crear un proyecto reproducible {#steps-to-create-a-reproducible-project}

- Crea un nuevo repositorio git.
- Inicialice un proyecto utilizando `tuist init` en el directorio del
  repositorio.
- Añade el código necesario para recrear el error que has visto.
- Publica el código (tu cuenta de GitHub es un buen lugar para hacerlo) y luego
  enlázalo al crear una incidencia.

### Ventajas de los proyectos reproducibles {#benefits-of-reproducible-projects}

- **Superficie más pequeña:** Al eliminar todo excepto el error, no es necesario
  buscar el error.
- **No es necesario publicar el código secreto:** Es posible que no puedas
  publicar tu sitio web principal (por muchas razones). Rehacer una pequeña
  parte del mismo como un caso de prueba reproducible te permite demostrar
  públicamente un problema sin exponer ningún código secreto.
- **Prueba del error:** A veces, un error se debe a una combinación de ajustes
  en tu equipo. Un caso de prueba reproducible permite a los colaboradores
  descargar tu compilación y probarla también en sus equipos. Esto ayuda a
  verificar y delimitar la causa de un problema.
- **Obtenga ayuda para corregir su error:** Si otra persona puede reproducir su
  problema, es muy probable que pueda solucionarlo. Es casi imposible corregir
  un error sin poder reproducirlo primero.
