---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Rejestrowanie {#logging}

CLI wykorzystuje interfejs [swift-log](https://github.com/apple/swift-log) do
rejestrowania. Pakiet abstrahuje szczegóły implementacji rejestrowania, dzięki
czemu CLI jest niezależne od zaplecza rejestrowania. Rejestrator jest
wstrzykiwany jako zależność przy użyciu zmiennych lokalnych zadania i można
uzyskać do niego dostęp z dowolnego miejsca za pomocą:

```bash
Logger.current
```

:: info
<!-- -->
Lokalizacje zadań nie propagują wartości podczas korzystania z `Dispatch` lub
zadań odłączonych, więc jeśli z nich korzystasz, musisz je pobrać i przekazać do
operacji asynchronicznej.
<!-- -->
:::

## Co należy rejestrować {#what-to-log}

Logi nie są interfejsem użytkownika CLI. Są narzędziem służącym do diagnozowania
problemów, gdy się pojawią. Dlatego im więcej informacji podasz, tym lepiej.
Tworząc nowe funkcje, postaw się w sytuacji programisty, który napotyka
nieoczekiwane zachowanie, i zastanów się, jakie informacje byłyby dla niego
pomocne. Upewnij się, że używasz odpowiedniego [poziomu
logowania](https://www.swift.org/documentation/server/guides/libraries/log-levels.html).
W przeciwnym razie programiści nie będą w stanie odfiltrować szumu.
