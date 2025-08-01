#!/usr/bin/env node

import { execa } from "execa";
import path from "node:path";
import fs from "node:fs";
import fg from "fast-glob";

const rootDirectory = path.join(import.meta.dirname, "../..");
const docsDirectory = path.join(import.meta.dirname, "..");
const outputFile = path.join(docsDirectory, ".vitepress/data/manifest-data.json");

console.log("🔨 Generating manifest documentation...");

try {
  // Ensure output directory exists
  fs.mkdirSync(path.dirname(outputFile), { recursive: true });

  await execa("tuist", ["install"], {
    cwd: rootDirectory,
    stdio: "inherit",
  });

  await execa("tuist", ["generate", "--no-open", "--no-binary-cache"], {
    cwd: rootDirectory,
    stdio: "inherit",
  });

  await execa(
    "mise",
    [
      "x",
      "spm:tuist/sourcedocs@2.0.2",
      "--",
      "sourcedocs",
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
    { cwd: rootDirectory, stdio: "inherit" },
  );

  // Clean up README.md
  const readmePath = path.join(docsDirectory, "docs/generated/manifest/README.md");
  if (fs.existsSync(readmePath)) {
    fs.rmSync(readmePath);
  }

  // Rename files with brackets
  fg.sync(path.join(docsDirectory, "docs/generated/manifest/**/*.md")).forEach(
    (file) => {
      const renamedPath = file.replace(/\[(.*?)\]/g, "Array<$1>");
      if (file !== renamedPath) {
        fs.renameSync(file, renamedPath);
      }
    },
  );

  // Generate intermediate JSON data
  const generatedDirectory = path.join(docsDirectory, "docs/generated/manifest");
  const files = fg
    .sync("**/*.md", {
      cwd: generatedDirectory,
      absolute: true,
      ignore: ["**/README.md"],
    })
    .sort();

  const manifestData = files.map((file) => {
    const category = path.basename(path.dirname(file));
    const fileName = path.basename(file).replace(".md", "");
    return {
      category: category,
      title: fileName,
      name: fileName.toLowerCase(),
      identifier: category + "/" + fileName.toLowerCase(),
      description: "",
      content: fs.readFileSync(file, "utf-8"),
    };
  });

  // Write intermediate data file
  fs.writeFileSync(outputFile, JSON.stringify({
    generatedAt: new Date().toISOString(),
    data: manifestData
  }, null, 2));

  console.log(`✅ Generated manifest data with ${manifestData.length} items`);
  console.log(`📄 Output written to: ${outputFile}`);

} catch (error) {
  console.error("❌ Failed to generate manifest documentation:", error.message);
  
  // Write empty data file on failure
  fs.writeFileSync(outputFile, JSON.stringify({
    generatedAt: new Date().toISOString(),
    error: error.message,
    data: []
  }, null, 2));
  
  process.exit(1);
}