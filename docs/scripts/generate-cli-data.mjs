#!/usr/bin/env node

import { execa, $ } from "execa";
import { temporaryDirectoryTask } from "tempy";
import path from "node:path";
import fs from "node:fs";

const rootDirectory = path.join(import.meta.dirname, "../..");
const docsDirectory = path.join(import.meta.dirname, "..");
const outputFile = path.join(docsDirectory, ".vitepress/data/cli-data.json");

console.log("🔨 Generating CLI documentation...");

try {
  // Ensure output directory exists
  fs.mkdirSync(path.dirname(outputFile), { recursive: true });

  console.log("Building ProjectDescription...");
  await execa({
    stdio: "inherit",
  })`swift build --product ProjectDescription --configuration debug --package-path ${rootDirectory}`;
  
  console.log("Building tuist CLI...");
  await execa({
    stdio: "inherit",
  })`swift build --product tuist --configuration debug --package-path ${rootDirectory}`;

  console.log("Dumping CLI schema...");
  let dumpedCLISchema;
  await temporaryDirectoryTask(async (tmpDir) => {
    // I'm passing --path to sandbox the execution since we are only interested in the schema and nothing else.
    dumpedCLISchema = await $`${path.join(
      rootDirectory,
      ".build/debug/tuist",
    )} --experimental-dump-help --path ${tmpDir}`;
  });

  const { stdout } = dumpedCLISchema;
  const schema = JSON.parse(stdout);

  // Write intermediate data file
  fs.writeFileSync(outputFile, JSON.stringify({
    generatedAt: new Date().toISOString(),
    schema: schema
  }, null, 2));

  console.log("✅ Generated CLI schema successfully");
  console.log(`📄 Output written to: ${outputFile}`);

} catch (error) {
  console.error("❌ Failed to generate CLI documentation:", error.message);
  
  // Write empty data file on failure
  fs.writeFileSync(outputFile, JSON.stringify({
    generatedAt: new Date().toISOString(),
    error: error.message,
    schema: null
  }, null, 2));
  
  process.exit(1);
}