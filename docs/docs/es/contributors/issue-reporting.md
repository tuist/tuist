---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# Emisión de informes {#issue-reporting}

Como usuario de Tuist, es posible que te encuentres con errores o
comportamientos inesperados. Si lo haces, te animamos a que nos informes de
ellos para que podamos solucionarlos.

## GitHub issues es nuestra plataforma de tickets {#github-issues-is-our-ticketing-platform}

Las incidencias deben notificarse en GitHub como [GitHub
issues](https://github.com/tuist/tuist/issues) y no en Slack u otras
plataformas. GitHub es mejor para rastrear y gestionar problemas, está más cerca
del código base y nos permite seguir el progreso del problema. Además, fomenta
una descripción larga del problema, lo que obliga al informador a pensar sobre
el problema y a proporcionar más contexto.

## El contexto es crucial {#context-is-crucial}

Una cuestión sin contexto suficiente se considerará incompleta y se pedirá al
autor contexto adicional. En caso contrario, la incidencia se cerrará. Piénsalo
de esta manera: cuanto más contexto proporciones, más fácil nos resultará
comprender el problema y solucionarlo. Por lo tanto, si quieres que se solucione
tu problema, proporciona todo el contexto posible. Intenta responder a las
siguientes preguntas:

- ¿Qué intentabas hacer?
- ¿Qué aspecto tiene su gráfico?
- ¿Qué versión de Tuist utilizas?
- ¿Esto te bloquea?

También le pedimos que nos proporcione un proyecto mínimo reproducible **** .

## Proyecto reproducible {#reproducible-project}

### ¿Qué es un proyecto reproducible? {#what-is-a-reproducible-project}

Un proyecto reproducible es un pequeño proyecto Tuist para demostrar un problema
- a menudo este problema es causado por un bug en Tuist. Tu proyecto
reproducible debe contener las características mínimas necesarias para demostrar
claramente el error.

### ¿Por qué crear un caso de prueba reproducible? {#why-should-you-create-a-reproducible-test-case}

Un proyecto reproducible nos permite aislar la causa de un problema, ¡que es el
primer paso para solucionarlo! La parte más importante de cualquier informe de
fallo es describir los pasos exactos necesarios para reproducir el fallo.

Un proyecto reproducible es una gran manera de compartir un entorno específico
que causa un error. Tu proyecto reproducible es la mejor manera de ayudar a la
gente que quiere ayudarte.

### Pasos para crear un proyecto reproducible {#steps-to-create-a-reproducible-project}

- Crear un nuevo repositorio git.
- Inicializar un proyecto utilizando `tuist init` en el directorio del
  repositorio.
- Añade el código necesario para recrear el error que has visto.
- Publica el código (tu cuenta de GitHub es un buen lugar para hacerlo) y luego
  vincúlalo al crear una incidencia.

### Ventajas de los proyectos reproducibles {#benefits-of-reproducible-projects}

- **Menor superficie:** Al eliminar todo menos el error, no tienes que excavar
  para encontrar el fallo.
- **No es necesario publicar el código secreto:** Es posible que no puedas
  publicar tu sitio principal (por muchas razones). Rehacer una pequeña parte de
  ella como caso de prueba reproducible te permite demostrar públicamente un
  problema sin exponer ningún código secreto.
- **Prueba del fallo:** A veces, un error se debe a una combinación de ajustes
  en tu máquina. Un caso de prueba reproducible permite a los colaboradores
  descargar tu compilación y probarla también en sus máquinas. Esto ayuda a
  verificar y reducir la causa de un problema.
- **Consigue ayuda para solucionar tu error:** Si otra persona puede reproducir
  tu problema, suele tener muchas posibilidades de solucionarlo. Es casi
  imposible arreglar un fallo sin poder reproducirlo antes.
