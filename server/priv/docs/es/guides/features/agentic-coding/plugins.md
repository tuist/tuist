---
{
  "title": "Plugins",
  "titleTemplate": ":title · Programación con agentes · Funcionalidades · Guías · Tuist",
  "description": "Instala el plugin de Tuist para Cursor o el paquete Agent Plugins, independiente del proveedor."
}
---

# Plugins

Tuist empaqueta sus habilidades para agentes y el servidor MCP alojado como plugins para que puedas instalarlos juntos. Elige el paquete que coincida con tu agente de programación.

## Claude Code

El [marketplace de Tuist Claude Code](https://github.com/tuist/claude-plugin) empaqueta el plugin de Tuist para su instalación con:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

El plugin proporciona habilidades de Tuist y conecta Claude Code al servidor MCP alojado.

## Cursor

Instala el [plugin de Tuist para Cursor](https://github.com/tuist/cursor-plugin) desde el [Marketplace de Cursor](https://cursor.com/marketplace):

1. Abre **Personalizar** en la barra lateral de Cursor.
2. Busca **Tuist**.
3. Selecciona **Instalar** y luego elige si deseas instalarlo para el proyecto actual o para tu cuenta de usuario.

También puedes escribir `/add-plugin` en Cursor para abrir el mismo flujo de instalación. El plugin proporciona habilidades de Tuist y conecta Cursor al servidor MCP alojado.

Si tu organización gestiona los marketplaces de Cursor, importa primero `https://github.com/tuist/cursor-plugin` desde **Configuración → Plugins → Marketplaces de equipo → Importar marketplace**.

## Otros agentes de programación

El [Plugin de Agente de Tuist](https://github.com/tuist/agent-plugin) sigue el estándar abierto e independiente del proveedor [Agent Plugins](https://agent-plugins.org/). Apunta un cliente compatible al repositorio, siguiendo las instrucciones de ese cliente para instalar o referenciar directorios de plugins:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

Instala las habilidades de Tuist y registra `https://tuist.dev/mcp` como un servidor MCP remoto. Para clientes que aún no admiten Agent Plugins, instala las <.localized_link href="/guides/features/agentic-coding/skills">habilidades</.localized_link> o configura el <.localized_link href="/guides/features/agentic-coding/mcp">servidor MCP</.localized_link> por separado.

## Autenticación

La mayoría de las habilidades utilizan la interfaz de línea de comandos de Tuist, así que autentícate una vez antes de pedirle a un agente que acceda a los datos de tu proyecto:

```bash
tuist auth login
```

El servidor MCP alojado solicita su propio inicio de sesión cuando es necesario. Consulta la <.localized_link href="/guides/features/agentic-coding/mcp">guía de MCP</.localized_link> para obtener detalles sobre la configuración y la autenticación específicas del cliente.
