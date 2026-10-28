---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Sharding de tests en Rust {#rust-test-sharding}

Tuist no fragmenta las ejecuciones normales de `cargo test` ni distribuye sus tests compilados entre los workers de CI. Establecer variables de entorno de shard-plan no cambia qué tests ejecuta Cargo.

Ejecuta tus tests en un único trabajo de CI en su lugar:

```sh
tuist cargo test --workspace
```

Cargo gestiona el paralelismo local de los tests y Tuist informa de los resultados, incluidos los doctests. Consulta <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> para obtener detalles sobre la configuración y los informes.

Puedes usar la selección de paquetes y los filtros de tests de Cargo para elegir qué ejecuta cada trabajo, pero estos trabajos son ejecuciones independientes, no shards gestionados por Tuist.
