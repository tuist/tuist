---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# Pruebas poco fiables {#flaky-tests}

::: advertencia REQUISITOS
<!-- -->
- <LocalizedLink href="/guides/features/test-insights">Test
  Insights</LocalizedLink> debe estar configurado.
<!-- -->
:::

Las pruebas inestables son aquellas que producen resultados diferentes
(aprobadas o suspendidas) cuando se ejecutan varias veces con el mismo código.
Socavan la confianza en tu conjunto de pruebas y hacen perder tiempo a los
desarrolladores investigando falsos fallos. Tuist detecta automáticamente las
pruebas inestables y te ayuda a realizar un seguimiento de ellas a lo largo del
tiempo.

![Página de pruebas poco
fiables](/images/guides/features/test-insights/flaky-tests-page.png)

## Cómo funciona la detección de irregularidades {#how-it-works}

Tuist detecta pruebas poco fiables de dos maneras:

### Reintentos de prueba {#test-retries}

Cuando ejecutas pruebas con la función de reintento de Xcode (utilizando
`-retry-tests-on-failure` o `-test-iterations`), Tuist analiza los resultados de
cada intento. Si una prueba falla en algunos intentos pero pasa en otros, se
marca como inestable.

Por ejemplo, si una prueba falla en el primer intento pero pasa en el reintento,
Tuist lo registra como una prueba inestable.

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Detalle del caso de prueba poco
fiable](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Detección de cruces {#cross-run-detection}

Incluso sin reintentos de pruebas, Tuist puede detectar pruebas inestables
comparando los resultados de diferentes ejecuciones de CI en la misma
confirmación. Si una prueba pasa en una ejecución de CI pero falla en otra
ejecución para la misma confirmación, ambas ejecuciones se marcan como
inestables.

Esto resulta especialmente útil para detectar pruebas inestables que no fallan
con la suficiente consistencia como para ser detectadas por los reintentos, pero
que siguen provocando fallos intermitentes en la integración continua.

## Gestión de pruebas inestables {#managing-flaky-tests}

### Borrado automático

Tuist elimina automáticamente la marca de inestabilidad de las pruebas que no
han sido inestables durante 14 días. Esto garantiza que las pruebas que se han
corregido no permanezcan marcadas como inestables de forma indefinida.

### Gestión manual

También puede marcar o desmarcar manualmente las pruebas como inestables desde
la página de detalles del caso de prueba. Esto resulta útil cuando:
- Quieres reconocer una prueba defectuosa conocida mientras trabajas en una
  solución.
- Una prueba se marcó incorrectamente debido a problemas de infraestructura.

## Notificaciones de Slack {#slack-notifications}

Reciba notificaciones instantáneas cuando una prueba se vuelva inestable
configurando
<LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">alertas de
pruebas inestables</LocalizedLink> en su integración de Slack.
