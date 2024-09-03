import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { $ } from "execa";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDirectory = path.join(__dirname, "../../..");

export default {
  watch: [path.join(rootDirectory, "Sources/**/*.swift")],

  async load() {
    await $`swift build --product tuist --product ProjectDescription --configuration debug --package-path ${rootDirectory}`;
    const { stdout } =
      await $`${path.join(rootDirectory, ".build/debug/tuist")} --experimental-dump-help`;

    const {
      command: { subcommands },
    } = JSON.parse(stdout);
    return {
      text: "CLI",
      items: subcommands
        .map((command) => {
          return {
            ...this.parseCommand(command),
            collapsed: true,
          };
        })
        .sort((a, b) => a.text.localeCompare(b.text)),
    };
  },

  parseCommand(command, parentCommand = "tuist", parentPath = "/cli/") {
    const output = {
      text: command.commandName,
      fullCommand: parentCommand + " " + command.commandName,
      link: path.join(parentPath, command.commandName),
      spec: command,
    };
    if (command.subcommands && command.subcommands.length !== 0) {
      output.items = command.subcommands.map((subcommand) => {
        return this.parseCommand(
          subcommand,
          parentCommand + " " + command.commandName,
          path.join(parentPath, command.commandName),
        );
      });
    }

    return output;
  },
};
