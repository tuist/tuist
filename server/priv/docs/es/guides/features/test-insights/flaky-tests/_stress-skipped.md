### Cuándo no se ejecuta la puerta {#when-the-gate-does-not-run}

- La primera pasada ya falló. Corrige esos tests primero.
- El proyecto no tiene rama predeterminada o aún no se ha ejecutado nada en CI sobre ella.
- Más del 30% de los casos de test del proyecto parecen nuevos. Volver a ejecutar tantos llevaría más tiempo del que vale la pena. Esto es esperable en un proyecto que acaba de empezar a enviar datos a Tuist, o tras un cambio de nombre que mueve muchos tests a la vez.
