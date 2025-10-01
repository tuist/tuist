---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# Protocolo de contexto de modelo (MCP)

O [Model Context Protocol (MCP)](https://www.claudemcp.com) é um padrão proposto
por [Claude](https://claude.ai) para que os LLMs interajam com ambientes de
desenvolvimento. Pode pensar-se nele como o USB-C dos LLMs. Assim como os
contêineres, que tornaram a carga e o transporte mais interoperáveis, ou
protocolos como o TCP, que desacoplou a camada de aplicação da camada de
transporte, o MCP torna as aplicações alimentadas por LLMs como
[Claude](https://claude.ai/), [Claude
Code](https://docs.anthropic.com/en/docs/claude-code), e editores como
[Zed](https://zed.dev), [Cursor](https://www.cursor.com), ou [VS
Code](https://code.visualstudio.com) interoperáveis com outros domínios.

O Tuist fornece um servidor local através do seu CLI para que possa interagir
com o seu ambiente de desenvolvimento de aplicações **** . Ao ligar as suas
aplicações cliente a este servidor, pode utilizar a linguagem para interagir com
os seus projectos.

Nesta página, ficará a saber como configurá-lo e as suas capacidades.

> [NOTA] O servidor Tuist MCP usa os projetos mais recentes do Xcode como a
> fonte de verdade para os projetos com os quais você deseja interagir.

## Configurar

O Tuist fornece comandos de configuração automatizados para clientes populares
compatíveis com MCP. Basta executar o comando apropriado para o seu cliente:

### [Claude](https://claude.ai)

Para [Ambiente de trabalho do Claude](https://claude.ai/download), executar:
```bash
tuist mcp setup claude
```

Isto irá configurar o ficheiro em `~/Library/Application
Support/Claude/claude_desktop_config.json`.

### [Código de Claude](https://docs.anthropic.com/en/docs/claude-code)

Para o Claude Code, executar:
```bash
tuist mcp setup claude-code
```

Isto irá configurar o mesmo ficheiro que o ambiente de trabalho do Claude.

### [Cursor](https://www.cursor.com)

Para o IDE Cursor, pode configurá-lo globalmente ou localmente:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

Para o editor Zed, também pode configurá-lo globalmente ou localmente:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [Código VS](https://code.visualstudio.com)

Para o VS Code com extensão MCP, configure-o globalmente ou localmente:
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### Configuração manual

Se preferir configurar manualmente ou estiver a utilizar um cliente MCP
diferente, adicione o servidor Tuist MCP à configuração do seu cliente:

:::grupo de códigos

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
:::

## Capacidades

Nas secções seguintes, ficará a conhecer as capacidades do servidor Tuist MCP.

### Resources

#### Projectos e espaços de trabalho recentes

O Tuist mantém um registro dos projetos e espaços de trabalho do Xcode com os
quais você trabalhou recentemente, dando ao seu aplicativo acesso aos gráficos
de dependência para obter insights poderosos. Você pode consultar esses dados
para descobrir detalhes sobre a estrutura e os relacionamentos do seu projeto,
como:

- Quais são as dependências diretas e transitivas de um objetivo específico?
- Qual é o destino que tem mais ficheiros de origem e quantos inclui?
- Quais são todos os produtos estáticos (por exemplo, bibliotecas ou estruturas
  estáticas) no gráfico?
- Pode listar todos os alvos, ordenados alfabeticamente, juntamente com os seus
  nomes e tipos de produtos (por exemplo, aplicação, estrutura, teste de
  unidade)?
- Que objectivos dependem de um determinado quadro ou dependência externa?
- Qual é o número total de ficheiros de origem em todos os alvos do projeto?
- Existem dependências circulares entre objectivos e, em caso afirmativo, onde?
- Que alvos utilizam um recurso específico (por exemplo, uma imagem ou um
  ficheiro plist)?
- Qual é a cadeia de dependência mais profunda no gráfico e quais são os
  objectivos envolvidos?
- Pode mostrar-me todos os alvos de teste e os respectivos alvos de aplicação ou
  estrutura associados?
- Que alvos têm os tempos de construção mais longos com base em interações
  recentes?
- Quais são as diferenças nas dependências entre dois objectivos específicos?
- Existem ficheiros de origem ou recursos não utilizados no projeto?
- Que alvos partilham dependências comuns e quais são?

Com o Tuist, pode aprofundar os seus projectos Xcode como nunca antes, tornando
mais fácil compreender, otimizar e gerir até as configurações mais complexas!
