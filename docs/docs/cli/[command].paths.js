import cliDataLoader from "./commands.data";

function traverse(command, paths) {
  paths.push({
    params: { command: command.link.replace(/\/cli\//, "") },
    content: content(command),
  });
  (command.items ?? []).forEach((subCommand) => {
    traverse(subCommand, paths);
  });
}

function content(command) {
  let body = "";
  body += `# ${command.fullCommand}\n`;
  body += `${command.command.abstract}\n`;
  const args = command.command.arguments;
  if (args && args.length > 0) {
    body += `## Arguments\n`;
    args.forEach((arg) => {
      body += `### ${arg.valueName} ${arg.isOptional ? "<Badge type='info' text='Optional' />" : ""}\n`;
      const envVarRegex = /\(env:\s*([^)]+)\)/;
      const envVarMatch = arg.abstract.match(envVarRegex);
      let envVar;
      if (envVarMatch) {
        envVar = envVarMatch[1];
      }

      if (envVar) {
        body += `**Environment variable** \`${envVar}\`\n\n`;
      }

      body += `${arg.abstract.replace(envVarRegex, "").trim()}\n`;
      if (arg.kind === "positional") {
        body += `\`\`\`bash\n${command.fullCommand} [${arg.valueName}]\n\`\`\`\n`;
      } else if (arg.kind === "flag") {
        body += `\`\`\`bash\n${arg.names
          .map((name) => {
            if (name.kind === "long") {
              return `${command.fullCommand} --${name.name}`;
            } else {
              return `${command.fullCommand} -${name.name}`;
            }
          })
          .join("\n")}\n\`\`\`\n`;
      } else if (arg.kind === "option") {
        body += `\`\`\`bash\n${arg.names
          .map((name) => {
            if (name.kind === "long") {
              return `${command.fullCommand} --${name.name} [${arg.valueName}]`;
            } else {
              return `${command.fullCommand} -${name.name} [${arg.valueName}]`;
            }
          })
          .join("\n")}\n\`\`\`\n`;
      }

      return body;
    });

    // {
    //   "isRepeating" : true,
    //   "kind" : "positional",
    //   "shouldDisplay" : true,
    // },

    // "defaultValue" : "--no-generate-only",
    // "isOptional" : true,
    // "isRepeating" : false,
    // "kind" : "flag",
    // "names" : [
    //   {
    //     "kind" : "long",
    //     "name" : "generate-only"
    //   },
    //   {
    //     "kind" : "long",
    //     "name" : "no-generate-only"
    //   }
    // ],
    // "preferredName" : {
    //   "kind" : "long",
    //   "name" : "generate-only"
    // },
  }
  return body;
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
