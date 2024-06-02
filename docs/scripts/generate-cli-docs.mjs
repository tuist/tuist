#!/usr/bin/env node

import { execa } from "execa";
import path from "node:path";
import fs from "node:fs";
import fg from "fast-glob";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDirectory = path.join(__dirname, "../..");
const docsDirectory = path.join(__dirname, "../docs/generated/cli");
const manDirectory = path.join(
  rootDirectory,
  ".build/plugins/GenerateManual/outputs/tuist"
);

const generateManPages = async () => {
  await execa(
    "swift",
    ["package", "plugin", "generate-manual", "--multi-page"],
    {
      cwd: rootDirectory,
      stdio: "inherit",
    }
  );
};

const runManCommand = async (filePath) => {
  const { stdout } = await execa("sh", ["-c", `man ${filePath} | col -b`]);
  return stdout;
};

const parseManPage = async (filePath) => {
  const manContent = await runManCommand(filePath);

  // Remove the first line containing `TUIST.BUILD(1) General Commands Manual TUIST.BUILD(1)`
  const lines = manContent.split("\n").slice(1);

  // Remove the last line
  lines.pop();

  // Convert all caps sections to subheadings
  const formattedContent = lines
    .map((line) => {
      if (/^[A-Z ]+$/.test(line.trim())) {
        return `### ${line.trim()}`;
      }
      return line;
    })
    .join("\n");

  return `# ${path.basename(filePath, ".1")}

${formattedContent}`;
};

const generateDocs = async () => {
  if (!fs.existsSync(docsDirectory)) {
    fs.mkdirSync(docsDirectory, { recursive: true });
  }

  const manFiles = fg.sync(path.join(manDirectory, "*.1"));

  for (const file of manFiles) {
    const commandName = path.basename(file, ".1");
    const docContent = await parseManPage(file);

    // Create directory structure based on the path
    const docPathParts = commandName.split(".").slice(1); // Remove "tuist"
    const docDirParts = docPathParts.slice(0, -1); // All but the last part
    const docDir = path.join(docsDirectory, ...docDirParts);
    const docPath = path.join(docDir, `${commandName}.md`);

    if (!fs.existsSync(docDir)) {
      fs.mkdirSync(docDir, { recursive: true });
    }

    fs.writeFileSync(docPath, docContent, "utf-8");
  }

  console.log("All command docs generated successfully.");
};

const main = async () => {
  await generateManPages();
  await generateDocs();
};

main();
