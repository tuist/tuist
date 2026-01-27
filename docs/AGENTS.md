# Tuist Documentation

This node covers the Tuist documentation site under `docs/`. The site is built with VitePress and provides guides, references, and tutorials for Tuist users.

## Project Structure
- `docs/en/` - English content (source language)
- `docs/{lang}/` - Translated content (ar, es, ja, ko, pl, pt, ru, tr, yue_Hant, zh_Hans, zh_Hant)
- `docs/generated/` - Auto-generated API documentation
- `docs/public/` - Static assets
- `.vitepress/` - VitePress configuration and theme

## Content Categories
- `cli/` - CLI command references
- `guides/` - User guides and tutorials
- `contributors/` - Contributor documentation
- `references/` - API and configuration references

## Building and Testing
- Build: `mise run docs:build`
- Dev server: `mise run docs:dev`
- Deployment: Automatic via CI

## Translation Guidelines
- English is the source language; only modify English content.
- Do not manually edit translated content in other language directories.
- Translations are managed through Weblate.

## Writing Guidelines
- Use clear, concise language.
- Include code examples where appropriate.
- Follow existing formatting patterns.
