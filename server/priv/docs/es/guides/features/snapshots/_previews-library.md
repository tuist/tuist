### Ajusta la comparación {#tune}

Para tolerar pequeñas diferencias de renderizado, como el suavizado de bordes, asigna un umbral de diferencia a una vista previa: la proporción de píxeles, de 0 a 1, que pueden diferir antes de que la imagen se considere cambiada.

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

Para excluir vistas previas, sobrescribe `includes(_:)` en tu subclase `PreviewSnapshotTestCase` .

### Opciones {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`): desactiva las subidas en CI.
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`): el conjunto al que pertenecen las imágenes. Por defecto es el esquema.
