---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Rejestrowanie {#logging}

CLI obejmuje interfejs [swift-log](https://github.com/apple/swift-log) dla
logowania. Pakiet abstrahuje od szczegółów implementacji logowania, pozwalając
CLI być niezależnym od backendu logowania. Rejestrator jest wstrzykiwany w
zależności przy użyciu lokalnych zadań i może być dostępny w dowolnym miejscu
przy użyciu:

```bash
Logger.current
```

:: info
<!-- -->
Lokalne zadania nie propagują wartości podczas korzystania z `Dispatch` lub
odłączonych zadań, więc jeśli ich używasz, musisz je pobrać i przekazać do
operacji asynchronicznej.
<!-- -->
:::

## Co rejestrować {#what-to-log}

Dzienniki nie są interfejsem użytkownika CLI. Są narzędziem do diagnozowania
problemów, gdy się pojawią. Dlatego im więcej informacji dostarczysz, tym
lepiej. Tworząc nowe funkcje, postaw się w sytuacji dewelopera napotykającego
nieoczekiwane zachowanie i zastanów się, jakie informacje byłyby dla niego
pomocne. Upewnij się, że używasz właściwego [poziomu
logów](https://www.swift.org/documentation/server/guides/libraries/log-levels.html).
W przeciwnym razie deweloperzy nie będą w stanie odfiltrować szumu.
