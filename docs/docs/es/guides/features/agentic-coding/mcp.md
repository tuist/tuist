---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# Protocolo de Contexto Modelo (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com) es un estándar
propuesto por [Claude](https://claude.ai) para que los LLM interactúen con
entornos de desarrollo. Se puede considerar como el USB-C de los LLM. Al igual
que los contenedores marítimos, que hicieron la carga y el transporte más
interoperables, o protocolos como TCP, que desacoplaron la capa de aplicación de
la capa de transporte, MCP hace que las aplicaciones impulsadas por LLMs como
[Claude](https://claude.ai/), [Claude
Code](https://docs.anthropic.com/en/docs/claude-code), y editores como
[Zed](https://zed.dev), [Cursor](https://www.cursor.com), o [VS
Code](https://code.visualstudio.com) sean interoperables con otros dominios.

Tuist proporciona un servidor local a través de su CLI para que puedas
interactuar con tu entorno de desarrollo de apps **** . Conectando tus apps
cliente a él, puedes usar el lenguaje para interactuar con tus proyectos.

En esta página aprenderás cómo configurarlo y sus funciones.

::: info
<!-- -->
El servidor MCP de Tuist utiliza los proyectos más recientes de Xcode como
fuente de verdad de los proyectos con los que quieres interactuar.
<!-- -->
:::

## Póngalo en marcha

Tuist proporciona comandos de configuración automatizados para los clientes más
populares compatibles con MCP. Simplemente ejecuta el comando apropiado para tu
cliente:

### [Claude](https://claude.ai)

Para [Claude desktop](https://claude.ai/download), ejecuta:
```bash
tuist mcp setup claude
```

Esto configurará el archivo en `~/Library/Application
Support/Claude/claude_desktop_config.json`.

### [Código Claude](https://docs.anthropic.com/en/docs/claude-code)

Para Claude Code, ejecute:
```bash
tuist mcp setup claude-code
```

Esto configurará el mismo archivo que el escritorio de Claude.

### [Cursor](https://www.cursor.com)

Para Cursor IDE, puede configurarlo global o localmente:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

Para el editor Zed, también puedes configurarlo global o localmente:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [Código VS](https://code.visualstudio.com)

Para VS Code con extensión MCP, configúrelo global o localmente:
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### Configuración manual

Si prefieres configurarlo manualmente o utilizas otro cliente MCP, añade el
servidor Tuist MCP a la configuración de tu cliente:

::: grupo de códigos

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

## Capacidades

En las siguientes secciones conocerás las capacidades del servidor Tuist MCP.

### Recursos

#### Proyectos y espacios de trabajo recientes

Tuist mantiene un registro de los proyectos y espacios de trabajo de Xcode con
los que has trabajado recientemente, dando a tu aplicación acceso a sus gráficos
de dependencias para obtener información de gran alcance. Puedes consultar estos
datos para descubrir detalles sobre la estructura y las relaciones de tus
proyectos, por ejemplo:

- ¿Cuáles son las dependencias directas y transitivas de un objetivo específico?
- ¿Qué objetivo tiene más archivos fuente y cuántos incluye?
- ¿Cuáles son todos los productos estáticos (por ejemplo, bibliotecas estáticas
  o frameworks) del gráfico?
- ¿Puede enumerar todos los objetivos, ordenados alfabéticamente, junto con sus
  nombres y tipos de producto (por ejemplo, aplicación, marco, prueba unitaria)?
- ¿Qué objetivos dependen de un determinado marco o dependencia externa?
- ¿Cuál es el número total de archivos fuente de todos los objetivos del
  proyecto?
- ¿Existen dependencias circulares entre objetivos y, en caso afirmativo, dónde?
- ¿Qué objetivos utilizan un recurso específico (por ejemplo, una imagen o un
  archivo plist)?
- ¿Cuál es la cadena de dependencia más profunda del gráfico y qué objetivos
  están implicados?
- ¿Puede mostrarme todos los objetivos de prueba y sus objetivos de aplicación o
  marco asociados?
- ¿Qué objetivos tienen los tiempos de construcción más largos según las
  interacciones recientes?
- ¿Cuáles son las diferencias de dependencia entre dos objetivos concretos?
- ¿Hay archivos fuente o recursos no utilizados en el proyecto?
- ¿Qué objetivos comparten dependencias comunes y cuáles son?

Con Tuist, puedes profundizar en tus proyectos de Xcode como nunca antes,
facilitando la comprensión, optimización y gestión incluso de las
configuraciones más complejas.
