#!/usr/bin/env node

import { execa } from "execa";
import path from "node:path";
import fs from "node:fs";
import fg from "fast-glob";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const rootDirectory = path.join(__dirname, "../..");
const docsDirectory = path.join(__dirname, "../docs");

await execa("tuist", ["install"], {
  cwd: rootDirectory,
  stdio: "inherit",
});

await execa("tuist", ["generate", "--no-open", "--no-binary-cache"], {
  cwd: rootDirectory,
  stdio: "inherit",
});

await execa(
  "sourcedocs",
  [
    "generate",
    "-o",
    path.join(docsDirectory, "generated/manifest"),
    "--clean",
    "--table-of-contents",
    "--module-name",
    "ProjectDescription",
    "--",
    "-scheme",
    "Tuist-Workspace",
    "-workspace",
    path.join(rootDirectory, "Tuist.xcworkspace"),
  ],
  { cwd: rootDirectory, stdio: "inherit" }
);

fs.rmSync(path.join(docsDirectory, "generated/manifest/README.md"));

fg.sync(path.join(docsDirectory, "generated/manifest/**/*.md")).forEach((file) => {
  const renamedPath = file.replace(/\[(.*?)\]/g, "Array<$1>");
  fs.renameSync(file, renamedPath);
});
