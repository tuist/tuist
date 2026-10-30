---
{
  "title": "Habilidades",
  "titleTemplate": ":title · Programación con agentes · Funcionalidades · Guías · Tuist",
  "description": "Habilidades predefinidas que los agentes de programación pueden usar para realizar tareas comunes de Tuist, como la migración de proyectos."
}
---

# Skills

Las skills son conjuntos de instrucciones preconstruidos para realizar tareas complejas y de varios pasos con Tuist. En lugar de guiar manualmente a un agente durante una migración o configuración, instalas una skill y dejas que el agente se encargue.

Si tu agente de programación admite complementos, los [complementos de Tuist](/guides/features/agentic-coding/plugins) instalan estas skills y el servidor alojado de Model Context Protocol juntos.

## Skills disponibles

| Skill | Descripción |
| --- | --- |
| `migrate` | Migra proyectos Xcode existentes a espacios de trabajo generados por Tuist con validación de compilación y ejecución, mapeo de dependencias externas y listas de verificación de migración. |
| `generated-projects` | Guía el trabajo diario en espacios de trabajo generados por Tuist: generación, comandos de compilación/pruebas y carpetas compilables. |
| `fix-flaky-tests` | Corrige tests inestables analizando patrones de fallo desde el análisis de tests de Tuist, identificando causas raíz y aplicando correcciones específicas. |
| `debug-generated-project` | Depura problemas con proyectos generados por Tuist reproduciendo el escenario, compilando Tuist desde el código fuente cuando sea necesario y determinando si es un error, una mala configuración o algo que requiere la intervención del equipo. |
| `compare-gradle-builds` | Compara dos ejecuciones de compilación de Gradle para identificar regresiones de duración, cambios en la caché y diferencias en los resultados de las tareas. Se puede invocar con IDs de compilación, URLs del dashboard o nombres de rama. |

## Instalación {#installation}

La forma recomendada de instalar skills de Tuist es con la CLI de [`skills`](https://github.com/vercel-labs/skills). Detecta automáticamente tus agentes de programación y coloca los archivos `SKILL.md` en la ubicación correcta.

### Instalar todas las skills

```bash
npx skills add tuist/agent-skills
```

El prompt interactivo te permite elegir qué skills y agentes instalar.

### Instalar una skill específica

```bash
npx skills add tuist/agent-skills --skill migrate
```

### Instalar para un agente específico

```bash
npx skills add tuist/agent-skills -a claude-code
```

### Instalar globalmente

Añade la bandera `-g` para instalar skills en tu directorio personal y que estén disponibles en todos los proyectos:

```bash
npx skills add tuist/agent-skills -g
```

### Actualizar skills

```bash
npx skills update
```

### No interactivo (CI)

```bash
npx skills add tuist/agent-skills --all -y
```

### Instalación manual {#manual}

Si prefieres no usar la CLI de `skills`, puedes descargar directamente los archivos `SKILL.md`. Configura las variables para la skill que desees y ejecuta el comando `curl` para tu agente:

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
