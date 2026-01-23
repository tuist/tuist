---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# Dokumenty {#docs}

Źródło:
[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## Do czego służy {#what-it-is-for}

Witryna dokumentacji zawiera dokumentację produktów i współpracowników Tuist.
Została ona stworzona przy użyciu VitePress.

## Jak wnieść swój wkład {#how-to-contribute}

### Skonfiguruj lokalnie {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### Opcjonalne dane generowane {#optional-generated-data}

W dokumentacji umieszczamy niektóre wygenerowane dane:

- Dane referencyjne CLI: `mise run generate-cli-docs`
- Dane referencyjne manifestu projektu: `mise run generate-manifests-docs`

Są one opcjonalne. Dokumenty są renderowane bez nich, więc uruchamiaj je tylko
wtedy, gdy chcesz odświeżyć wygenerowaną treść.
