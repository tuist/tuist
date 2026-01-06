#!/usr/bin/env node

import { execa, $ } from "execa";
import { temporaryDirectoryTask } from "tempy";
import * as path from "node:path";
import * as fs from "node:fs/promises";

const rootDirectory = path.join(import.meta.dirname, "../..");
const docsDirectory = path.join(import.meta.dirname, "..");
const schemaPath = path.join(docsDirectory, "docs/generated/cli/schema.json");
const derivedDataPath = path.join(rootDirectory, ".build/docs-gen");

console.log("Generating Xcode project...");
await execa("tuist", ["generate", "ProjectDescription", "tuist", "--no-open"], {
  cwd: rootDirectory,
  stdio: "inherit",
});

console.log("Building tuist with xcodebuild...");
await execa(
  "xcodebuild",
  [
    "build",
    "-workspace",
    "Tuist.xcworkspace",
    "-scheme",
    "tuist",
    "-configuration",
    "Debug",
    "-derivedDataPath",
    derivedDataPath,
    "ONLY_ACTIVE_ARCH=YES",
  ],
  {
    cwd: rootDirectory,
    stdio: "inherit",
  },
);

console.log("Generating CLI schema...");
let dumpedCLISchema;
await temporaryDirectoryTask(async (tmpDir) => {
  dumpedCLISchema = await $`${path.join(
    derivedDataPath,
    "Build/Products/Debug",
    "tuist",
  )} --experimental-dump-help --path ${tmpDir}`;
});

const { stdout } = dumpedCLISchema;
const schema = JSON.parse(stdout);

console.log("Ensuring output directory exists...");
await fs.mkdir(path.dirname(schemaPath), { recursive: true });

console.log("Writing schema to file...");
await fs.writeFile(schemaPath, JSON.stringify(schema, null, 2), "utf-8");
console.log(`Schema written to ${schemaPath}`);
