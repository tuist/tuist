import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { $ } from "execa";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDirectory = path.join(__dirname, "../../..");

export default {
  watch: [path.join(rootDirectory, "Sources/**/*.swift")],

  async load() {
    await $`swift build --product tuist --configuration debug --package-path ${rootDirectory}`;
    const { stdout } =
      await $`${path.join(rootDirectory, ".build/debug/tuist")} --experimental-dump-help`;

    const {
      command: { subcommands },
    } = JSON.parse(stdout);
    return {
      text: "CLI",
      items: subcommands.map((command) => {
        return this.parseCommand(command);
      }),
    };
  },

  parseCommand(command, parentCommand = "tuist", parentPath = "/cli/") {
    const output = {
      text: command.commandName,
      fullCommand: parentCommand + " " + command.commandName,
      link: path.join(parentPath, command.commandName),
      command: command,
    };
    if (command.subcommands && command.subcommands.length != 0) {
      output.items = command.subcommands.map((subCommand) => {
        return this.parseCommand(
          subCommand,
          parentCommand + " " + command.commandName,
          path.join(parentPath, command.commandName),
        );
      });
    }

    return output;
  },
};
