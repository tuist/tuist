### Cuántas veces se vuelve a ejecutar cada test {#stress-reruns}

Depende del tiempo que tardó el caso de test en la primera pasada:

| Primera pasada | Reejecuciones |
| --- | --- |
| Hasta 5 s | 10 |
| Hasta 10 s | 5 |
| Hasta 30 s | 3 |
| Hasta 5 min | 2 |
| Más de 5 min | No se reejecuta |

La pasada se detiene al alcanzar los 200 casos de test o los 10 minutos, lo que ocurra primero, e indica qué límite se alcanzó.
