#!/usr/bin/env node

import { execa } from "execa";
import path from "node:path";
import fs from "node:fs";
import fg from "fast-glob";

const rootDirectory = path.join(import.meta.dirname, "../..");
const docsDirectory = path.join(import.meta.dirname, "..");

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
    path.join(docsDirectory, "docs/generated/manifest"),
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

fs.rmSync(path.join(docsDirectory, "docs/generated/manifest/README.md"));

fg.sync(path.join(docsDirectory, "docs/generated/manifest/**/*.md")).forEach((file) => {
  const renamedPath = file.replace(/\[(.*?)\]/g, "Array<$1>");
  fs.renameSync(file, renamedPath);
});