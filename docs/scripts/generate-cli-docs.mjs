#!/usr/bin/env node

import { execa, $ } from "execa";
import { temporaryDirectoryTask } from "tempy";
import * as path from "node:path";
import * as fs from "node:fs/promises";

const rootDirectory = path.join(import.meta.dirname, "../..");
const docsDirectory = path.join(import.meta.dirname, "..");
const schemaPath = path.join(docsDirectory, "docs/generated/cli/schema.json");

console.log("Building Swift products...");
await execa({
  stdio: "inherit",
})`swift build --product ProjectDescription --configuration debug --package-path ${rootDirectory}`;

await execa({
  stdio: "inherit",
})`swift build --product tuist --configuration debug --package-path ${rootDirectory}`;

console.log("Generating CLI schema...");
let dumpedCLISchema;
await temporaryDirectoryTask(async (tmpDir) => {
  dumpedCLISchema = await $`${path.join(
    rootDirectory,
    ".build/debug/tuist",
  )} --experimental-dump-help --path ${tmpDir}`;
});

const { stdout } = dumpedCLISchema;
const schema = JSON.parse(stdout);

console.log("Ensuring output directory exists...");
await fs.mkdir(path.dirname(schemaPath), { recursive: true });

console.log("Writing schema to file...");
await fs.writeFile(schemaPath, JSON.stringify(schema, null, 2), 'utf-8');
console.log(`Schema written to ${schemaPath}`);