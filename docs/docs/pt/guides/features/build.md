---
{
  "title": "Build",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to build your projects efficiently."
}
---
# Construir {#build}

Os projectos são normalmente construídos através de um CLI fornecido pelo
sistema de construção (por exemplo, `xcodebuild`). A Tuist envolve-os para
melhorar a experiência do utilizador e integrar os fluxos de trabalho com a
plataforma para fornecer optimizações e análises.

Poderá perguntar-se qual é o valor de utilizar `tuist build` em vez de gerar o
projeto com `tuist generate` (se necessário) e construí-lo com o CLI específico
da plataforma. Aqui estão algumas razões:

- **Comando único:** `tuist build` assegura que o projeto é gerado, se
  necessário, antes de compilar o projeto.
- **Saída embelezada:** O Tuist enriquece a saída utilizando ferramentas como
  [xcbeautify](https://github.com/cpisciotta/xcbeautify) que tornam a saída mais
  fácil de utilizar.
- <LocalizedLink href="/guides/features/cache"><bold>Cache:</bold></LocalizedLink>
  Optimiza a construção ao reutilizar deterministicamente os artefactos de
  construção de uma cache remota.
- **Análises:** Recolhe e comunica métricas que são correlacionadas com outros
  pontos de dados para lhe fornecer informações acionáveis para tomar decisões
  informadas.

## Utilização {#usage}

`tuist build` gera o projeto se necessário, e depois constrói-o utilizando a
ferramenta de construção específica da plataforma. Apoiamos a utilização do
terminador `--` para encaminhar todos os argumentos subsequentes diretamente
para a ferramenta de construção subjacente. Isso é útil quando você precisa
passar argumentos que não são suportados por `tuist build` mas são suportados
pela ferramenta de construção subjacente.

::: grupo de códigos
```bash [Build a scheme]
tuist build MyScheme
```
```bash [Build a specific configuration]
tuist build MyScheme -- -configuration Debug
```
```bash [Build all schemes without binary cache]
tuist build --no-binary-cache
```
:::
