---
{
  "title": "Skills",
  "titleTemplate": ":title · Programación con agentes · Funcionalidades · Guías · Tuist",
  "description": "Skills preconstruidas que los agentes de programación pueden usar para realizar tareas comunes de Tuist, como la migración de proyectos."
}
---

# Habilidades

Las habilidades son conjuntos de instrucciones preconstruidos para realizar tareas complejas y multipaso de Tuist. En lugar de guiar manualmente a un agente a través de un proceso de migración o configuración, instalas una habilidad y dejas que el agente se encargue.

Si tu agente de programación admite complementos, los [complementos de Tuist](/guides/features/agentic-coding/plugins) instalan estas habilidades y el servidor alojado del Protocolo de Contexto de Modelo (MCP) juntos.

## Habilidades disponibles

| Habilidad | Descripción |
| --- | --- |
| `migrate` | Migra proyectos existentes de Xcode a espacios de trabajo generados por Tuist con validación de compilación y ejecución, mapeo de dependencias externas y listas de verificación de migración. |
| `generated-projects` | Guía el trabajo diario en espacios de trabajo generados por Tuist: generación, comandos de compilación/prueba y carpetas compilables. |
| `fix-flaky-tests` | Corrige tests inestables analizando patrones de fallo desde el análisis de tests de Tuist, identificando las causas raíz y aplicando correcciones específicas. |
| `debug-generated-project` | Depura problemas con proyectos generados por Tuist reproduciendo el escenario, compilando Tuist desde el código fuente cuando sea necesario y determinando si se trata de un error, una mala configuración o algo que requiere la intervención del equipo. |
| `compare-gradle-builds` | Compara dos ejecuciones de compilación de Gradle para identificar regresiones de duración, cambios en la caché y diferencias en los resultados de las tareas. Se puede invocar con IDs de compilación, URLs del panel o nombres de rama. |

## Instalación {#installation}

La forma recomendada de instalar las habilidades de Tuist es con la CLI de [`skills`](https://github.com/vercel-labs/skills). Detecta tus agentes de programación automáticamente y coloca los archivos `SKILL.md` en la ubicación correcta.

### Instalar todas las habilidades

```bash
npx skills add tuist/agent-skills
```

El prompt interactivo te permite elegir qué habilidades y agentes instalar.

### Instalar una habilidad específica

```bash
npx skills add tuist/agent-skills --skill migrate
```

### Instalar para un agente específico

```bash
npx skills add tuist/agent-skills -a claude-code
```

### Instalar globalmente

Añade la bandera `-g` para instalar habilidades en tu directorio personal, de modo que estén disponibles en todos los proyectos:

```bash
npx skills add tuist/agent-skills -g
```

### Actualizar habilidades

```bash
npx skills update
```

### No interactivo (CI)

```bash
npx skills add tuist/agent-skills --all -y
```

### Instalación manual {#manual}

Si prefieres no usar la CLI de `skills`, puedes descargar los archivos `SKILL.md` directamente. Configura las variables para la habilidad que desees y ejecuta el comando `curl` para tu agente:

```bash
SKILL_NAME=tuist-migrate          # or tuist-generated-projects
SKILL_URL=https://tuist.dev/skills/migrate/SKILL.md  # or .../generated-projects/SKILL.md
```

::: code-group

```bash [Claude Code]
mkdir -p .claude/skills/$SKILL_NAME
curl -o .claude/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Codex]
mkdir -p .codex/skills/$SKILL_NAME
curl -o .codex/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Amp]
mkdir -p .agents/skills/$SKILL_NAME
curl -o .agents/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [OpenCode]
mkdir -p .opencode/skills/$SKILL_NAME
curl -o .opencode/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::
