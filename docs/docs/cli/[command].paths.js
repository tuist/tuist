import cliDataLoader from "./commands.data";
import ejs from "ejs";

function traverse(command, paths) {
  paths.push({
    params: { command: command.link.replace(/\/cli\//, "") },
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
### <%- arg.valueName %> <%- (arg.isOptional) ? "<Badge type='info' text='Optional' />" : "" %>
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
        arguments: command.spec.arguments.map((arg) => {
          const envVarMatch = arg.abstract.match(envVarRegex);
          return {
            ...arg,
            envVar: envVarMatch ? envVarMatch[1] : undefined,
            abstract: arg.abstract.replace(envVarRegex, "").trim(),
          };
        }),
      },
    },
  });
  return content;
}

export default {
  async paths() {
    let paths = [];
    (await cliDataLoader.load()).items.forEach((command) => {
      traverse(command, paths);
    });
    return paths;
  },
};
