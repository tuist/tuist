---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Tests inestables · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta, gestiona y aísla los tests inestables en un proyecto de Xcode generado por Tuist."
}
---
# Proyecto de Xcode generado {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **Requisitos**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Análisis de tests de Xcode</.localized_link> configurado (los esquemas autogenerados incluyen la post-acción `tuist inspect test`; los esquemas personalizados deben añadirla).

<!-- @snippet: ./_intro -->

![Página de tests inestables](/images/guides/features/test-insights/flaky-tests-page.png)

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist detecta tests inestables de dos formas:

### Reintentos de tests {#test-retries}

Cuando ejecutas tests con funcionalidad de reintento, Tuist analiza los resultados de cada intento. Si un test falla en algunos intentos pero pasa en otros, se marca como inestable.

Pasa `-retry-tests-on-failure` o `-test-iterations` a través de `tuist test`:

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![Detalle del caso de test inestable](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## Poner en cuarentena tests inestables {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Un test en cuarentena está en uno de estos dos modos:

- **Silenciado**: el test sigue ejecutándose, pero `tuist test` oculta el fallo. Los fallos siguen alimentando el detector de tests inestables, así que puedes seguir monitorizando el test sin romper la compilación. Elige esta opción para un test que estés investigando activamente.
- **Omitido**: xcodebuild recibe `-skip-testing <identifier>`, por lo que el test nunca se inicia. No genera nuevos resultados y desaparece del panel de tests inestables hasta que lo vuelvas a habilitar. Elige esta opción cuando el test esté roto, sea lento o tan persistentemente inestable que ejecutarlo solo suponga un desperdicio de minutos de CI.

<!-- @snippet: ./_quarantined-passing -->

### Ejecución de tests {#running-tests}

`tuist test` respeta ambos modos automáticamente:

```sh
tuist test
```

Los tests omitidos se pasan a xcodebuild como `-skip-testing` y nunca se inician. Los tests silenciados se ejecutan con normalidad; si fallan, el fallo se oculta en el estado de compilación resultante.

Para omitir por completo la cuarentena y ejecutar todo, incluidos los tests silenciados y omitidos:

```sh
tuist test --skip-quarantine
```

## Pruebas de estrés para tests nuevos {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Un caso de test se considera nuevo cuando no se ha ejecutado en CI en los últimos 90 días en la rama predeterminada del proyecto, o en un commit que ya se haya integrado en ella. Con una cola de merge, un caso de test ejecutado por la cola se conoce una vez que el commit de la cola se integra, y permanece como nuevo si la cola lo descarta. Los commits se emparejan a través del <.localized_link href="/guides/features/test-insights/xcode#git-history">historial de Git</.localized_link> que Tuist recopila en CI.

<!-- @snippet: ./_stress-modes -->

En ambos modos, los <.localized_link href="/guides/features/selective-testing/generated-xcode-project">tests selectivos</.localized_link> no omiten un target de test que contenga un caso de test nuevo e inestable en la siguiente ejecución. El target vuelve a ejecutarse y la puerta de control somete el caso de test a pruebas de nuevo hasta que pase todos sus reintentos.

Pásalo antes de los argumentos de paso directo, o establece `TUIST_TEST_STRESS_NEW_TESTS` para variar el modo según la línea de CI:

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

Los reintentos reutilizan lo que construyó la primera pasada.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
