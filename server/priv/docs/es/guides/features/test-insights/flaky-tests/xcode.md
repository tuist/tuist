---
{
  "title": "Tests inestables en Xcode",
  "titleTemplate": ":title · Tests inestables · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta, gestiona y aísla tests inestables en proyectos de Xcode con Tuist."
}
---
# Tests inestables de Xcode {#xcode-flaky-tests}

> [!IMPORTANT]
> **Requisitos**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Análisis de tests de Xcode</.localized_link> configurado. Tuist detecta tests inestables a partir de los eventos de análisis de tests que sube cada ejecución de tests.

<!-- @snippet: ./_intro -->

![Página de Tests Inestables](/images/guides/features/test-insights/flaky-tests-page.png)

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist detecta tests inestables de dos maneras:

### Reintentos de tests {#test-retries}

Cuando ejecutas tests con funcionalidad de reintento, Tuist analiza los resultados de cada intento. Si un test falla en algunos intentos pero pasa en otros, se marca como inestable.

Pasa `-retry-tests-on-failure` o `-test-iterations` a través de `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Detalle del caso de test inestable](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## Poner en cuarentena tests inestables {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Un test en cuarentena está en uno de dos modos:

- **Silenciado**: el test sigue ejecutándose, pero `tuist xcodebuild test` oculta el fallo. Los fallos siguen alimentando el detector de tests inestables, así que puedes seguir vigilando el test sin romper la compilación. Elige esta opción para un test que estés investigando activamente.
- **Omitido**: xcodebuild recibe `-skip-testing <identifier>`, por lo que el test nunca se inicia. No genera nuevos resultados y desaparece del panel de tests inestables hasta que lo vuelvas a habilitar. Elige esta opción cuando el test esté roto, sea lento o tan persistentemente inestable que ejecutarlo solo desperdicie minutos de CI.

<!-- @snippet: ./_quarantined-passing -->

### Ejecutar tests {#running-tests}

`tuist xcodebuild test` es un envoltorio transparente que respeta ambos modos automáticamente. Úsalo igual que llamarías a xcodebuild:

```sh
tuist xcodebuild test -scheme MyScheme
```

Los tests omitidos se añaden a tu invocación de xcodebuild como `-skip-testing <identifier>` y nunca se inician. Los tests silenciados se ejecutan con normalidad; si fallan, el fallo se oculta en el estado de compilación resultante.

#### Omitir la cuarentena {#bypassing-quarantine}

`tuist xcodebuild test` acepta `--skip-quarantine` para ejecutar todo, incluidos los tests silenciados y omitidos:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### Llamar a xcodebuild directamente {#calling-xcodebuild-directly}

Si no puedes pasar por `tuist xcodebuild test`, expande tú mismo los tests en cuarentena en argumentos `-skip-testing` con `tuist test case list`:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

Este es el comportamiento seguro por defecto fuera de `tuist xcodebuild test`: el ocultamiento de fallos para tests silenciados solo ocurre cuando pasas por ese comando, así que omitir ambos modos evita fallos espurios en CI. Si necesitas un control más fino, usa `tuist xcodebuild test` en su lugar.

## Pruebas de estrés para tests nuevos {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Un caso de test se considera nuevo cuando no se ha ejecutado en CI en los últimos 90 días en la rama predeterminada del proyecto, o en un commit que desde entonces se haya integrado en ella. Con una cola de merge, un caso de test que la cola ejecutó se conoce una vez que el commit de la cola se integra, y sigue siendo nuevo si la cola lo descarta. Los commits se emparejan a través del <.localized_link href="/guides/features/test-insights/xcode#git-history">historial de Git</.localized_link> que Tuist recopila en CI.

<!-- @snippet: ./_stress-modes -->

Pásalo antes de los argumentos transparentes, o establece `TUIST_TEST_STRESS_NEW_TESTS` para variar el modo por canal de CI:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

Las reejecuciones reutilizan lo que construyó la primera pasada.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
