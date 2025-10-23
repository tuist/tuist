import * as path from "node:path";
import { fileURLToPath } from "node:url";
import * as fs from "node:fs";
import ejs from "ejs";
import { localizedString } from "../i18n.mjs";

// Root directory
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load pre-generated schema
const schemaPath = path.join(__dirname, "../../docs/generated/cli/schema.json");
let schema;
try {
  const schemaContent = fs.readFileSync(schemaPath, "utf-8");
  schema = JSON.parse(schemaContent);
} catch (error) {
  throw new Error(
    `Failed to load CLI schema from ${schemaPath}. Please run 'mise run generate-cli-docs' first.`,
  );
}

export { schema };

// Paths
function traverse(command, paths) {
  paths.push({
    params: { command: command.link.split("cli/")[1] },
    content: content(command),
  });
  (command.items ?? []).forEach((subCommand) => {
    traverse(subCommand, paths);
  });
}

const template = ejs.compile(
  `
# <%= command.fullCommand %>
<%= command.spec.abstract %>
<% if (command.spec.arguments && command.spec.arguments.length > 0) { %>
## Arguments
<% command.spec.arguments.forEach(function(arg) { %>
### <%- arg.valueName %> <%- (arg.isOptional) ? "<Badge type='info' text='Optional' />" : "" %> <%- (arg.isDeprecated) ? "<Badge type='warning' text='Deprecated' />" : "" %>
<% if (arg.envVar) { %>
**Environment variable** \`<%- arg.envVar %>\`
<% } %>
<%- arg.abstract %>
<% if (arg.kind === "positional") { -%>
\`\`\`bash
<%- command.fullCommand %> [<%- arg.valueName %>]
\`\`\`
<% } else if (arg.kind === "flag") { -%>
\`\`\`bash
<% arg.names.forEach(function(name) { -%>
<% if (name.kind === "long") { -%>
<%- command.fullCommand %> --<%- name.name %>
<% } else { -%>
<%- command.fullCommand %> -<%- name.name %>
<% } -%>
<% }) -%>
\`\`\`
<% } else if (arg.kind === "option") { -%>
\`\`\`bash
<% arg.names.forEach(function(name) { -%>
<% if (name.kind === "long") { -%>
<%- command.fullCommand %> --<%- name.name %> [<%- arg.valueName %>]
<% } else { -%>
<%- command.fullCommand %> -<%- name.name %> [<%- arg.valueName %>]
<% } -%>
<% }) -%>
\`\`\`
<% } -%>
<% }); -%>
<% } -%>
`,
  {},
);

function content(command) {
  const envVarRegex = /\(env:\s*([^)]+)\)/;
  const content = template({
    command: {
      ...command,
      spec: {
        ...command.spec,
        arguments: command.spec.arguments
          .map((arg) => {
            if (!arg.abstract) {
              return null;
            }
            const envVarMatch = arg.abstract.match(envVarRegex);
            return {
              ...arg,
              envVar: envVarMatch ? envVarMatch[1] : undefined,
              isDeprecated:
                arg.abstract.includes("[Deprecated]") ||
                arg.abstract.includes("[deprecated]"),
              abstract: arg.abstract
                .replace(envVarRegex, "")
                .replace("[Deprecated]", "")
                .replace("[deprecated]", "")
                .trim()
                .replace(/<([^>]+)>/g, "\\<$1\\>"),
            };
          })
          .filter((item) => item != null),
      },
    },
  });
  return content;
}

export async function paths(locale) {
  let paths = [];
  (await loadData(locale)).items[0].items.forEach((command) => {
    traverse(command, paths);
  });
  return paths;
}

export async function cliSidebar(locale) {
  const sidebar = await loadData(locale);
  return {
    ...sidebar,
    items: [
      {
        text: "CLI",
        items: [
          {
            text: localizedString(
              locale,
              "sidebars.cli.items.cli.items.logging.text",
            ),
            link: `/${locale}/cli/logging`,
          },
          {
            text: localizedString(
              locale,
              "sidebars.cli.items.cli.items.directories.text",
            ),
            link: `/${locale}/cli/directories`,
          },
          {
            text: localizedString(
              locale,
              "sidebars.cli.items.cli.items.shell-completions.text",
            ),
            link: `/${locale}/cli/shell-completions`,
          },
        ],
      },
      ...sidebar.items,
    ],
  };
}

export async function loadData(locale) {
  function parseCommand(
    command,
    parentCommand = "tuist",
    parentPath = `/${locale}/cli/`,
  ) {
    const output = {
      text: command.commandName,
      fullCommand: parentCommand + " " + command.commandName,
      link: path.join(parentPath, command.commandName),
      spec: command,
    };
    if (command.subcommands && command.subcommands.length !== 0) {
      output.items = command.subcommands.map((subcommand) => {
        return parseCommand(
          subcommand,
          parentCommand + " " + command.commandName,
          path.join(parentPath, command.commandName),
        );
      });
    }

    return output;
  }

  const {
    command: { subcommands },
  } = schema;

  return {
    text: localizedString(locale, "sidebars.cli.text"),
    items: [
      {
        text: localizedString(locale, "sidebars.cli.items.commands.text"),
        collapsed: true,
        items: subcommands
          .map((command) => {
            return {
              ...parseCommand(command),
              collapsed: true,
            };
          })
          .sort((a, b) => a.text.localeCompare(b.text)),
      },
    ],
  };
}
