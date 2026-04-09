---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# Protokół kontekstu modelu (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com) to standard
zaproponowany przez [Claude](https://claude.ai) dla LLM do interakcji ze
środowiskami programistycznymi. Można o nim myśleć jak o USB-C dla LLM. Podobnie
jak kontenery transportowe, które sprawiły, że ładunek i transport stały się
bardziej interoperacyjne, lub protokoły takie jak TCP, które oddzieliły warstwę
aplikacji od warstwy transportowej, MCP sprawia, że aplikacje oparte na LLM,
takie jak [Claude](https://claude.ai/), [Claude
Code](https://docs.anthropic.com/en/docs/claude-code) i edytory takie jak
[Zed](https://zed.dev), [Cursor](https://www.cursor.com) lub [VS
Code](https://code.visualstudio.com) są interoperacyjne z innymi domenami.

Tuist zapewnia lokalny serwer za pośrednictwem interfejsu CLI, dzięki czemu
można wchodzić w interakcje ze środowiskiem programistycznym aplikacji **** .
Podłączając do niego aplikacje klienckie, można używać języka do interakcji z
projektami.

Na tej stronie dowiesz się, jak ją skonfigurować i jakie są jej możliwości.

:: info
<!-- -->
Serwer Tuist MCP wykorzystuje najnowsze projekty Xcode jako źródło prawdy dla
projektów, z którymi chcesz wchodzić w interakcje.
<!-- -->
:::

## Konfiguracja

Tuist zapewnia automatyczne polecenia konfiguracyjne dla popularnych klientów
kompatybilnych z MCP. Wystarczy uruchomić odpowiednie polecenie dla danego
klienta:

### [Claude](https://claude.ai)

Dla [Claude desktop](https://claude.ai/download), uruchom:
```bash
tuist mcp setup claude
```

Spowoduje to skonfigurowanie pliku pod adresem `~/Library/Application
Support/Claude/claude_desktop_config.json`.

### [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

Dla Claude Code, uruchom:
```bash
tuist mcp setup claude-code
```

Spowoduje to skonfigurowanie tego samego pliku co pulpit Claude.

### [Kursor](https://www.cursor.com)

Cursor IDE można skonfigurować globalnie lub lokalnie:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

W przypadku edytora Zed można również skonfigurować go globalnie lub lokalnie:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS Code](https://code.visualstudio.com)

W przypadku VS Code z rozszerzeniem MCP skonfiguruj je globalnie lub lokalnie:
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### Konfiguracja ręczna

Jeśli wolisz konfigurować ręcznie lub używasz innego klienta MCP, dodaj serwer
MCP Tuist do konfiguracji klienta:

::: code-group

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp", "start"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
<!-- -->
:::

## Możliwości

W poniższych sekcjach dowiesz się o możliwościach serwera Tuist MCP.

### Zasoby

#### Ostatnie projekty i przestrzenie robocze

Tuist prowadzi rejestr projektów Xcode i obszarów roboczych, z którymi ostatnio
pracowałeś, dając Twojej aplikacji dostęp do ich wykresów zależności w celu
uzyskania potężnych wglądów. Możesz przeszukiwać te dane, aby odkryć szczegóły
dotyczące struktury projektu i relacji, takie jak:

- Jakie są bezpośrednie i przechodnie zależności określonego celu?
- Który cel ma najwięcej plików źródłowych i ile ich zawiera?
- Jakie są wszystkie statyczne produkty (np. statyczne biblioteki lub
  frameworki) na wykresie?
- Czy możesz wymienić wszystkie cele, posortowane alfabetycznie, wraz z ich
  nazwami i typami produktów (np. aplikacja, framework, test jednostkowy)?
- Które cele zależą od konkretnego frameworka lub zewnętrznej zależności?
- Jaka jest całkowita liczba plików źródłowych we wszystkich obiektach
  docelowych w projekcie?
- Czy istnieją jakieś zależności kołowe między celami, a jeśli tak, to gdzie?
- Które cele używają określonego zasobu (np. obrazu lub pliku plist)?
- Jaki jest najgłębszy łańcuch zależności na wykresie i które cele są w niego
  zaangażowane?
- Czy możesz pokazać mi wszystkie cele testów i powiązane z nimi cele aplikacji
  lub frameworka?
- Które cele mają najdłuższy czas budowy na podstawie ostatnich interakcji?
- Jakie są różnice w zależnościach między dwoma konkretnymi celami?
- Czy w projekcie są jakieś nieużywane pliki źródłowe lub zasoby?
- Które cele mają wspólne zależności i jakie one są?

Dzięki Tuist możesz zagłębić się w swoje projekty Xcode jak nigdy dotąd,
ułatwiając zrozumienie, optymalizację i zarządzanie nawet najbardziej złożonymi
konfiguracjami!
