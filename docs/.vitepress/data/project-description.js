import * as path from "node:path";
import fs from "node:fs";

const manifestDataFile = path.join(import.meta.dirname, "manifest-data.json");

function loadManifestData() {
  try {
    if (fs.existsSync(manifestDataFile)) {
      const manifestData = JSON.parse(fs.readFileSync(manifestDataFile, "utf-8"));
      if (manifestData.data && !manifestData.error) {
        console.log(`✅ Loaded manifest data from ${manifestDataFile} (${manifestData.data.length} items)`);
        return manifestData.data;
      } else {
        console.warn(`⚠️  Manifest data file exists but contains error: ${manifestData.error}`);
      }
    } else {
      console.warn(`⚠️  Manifest data file not found: ${manifestDataFile}`);
      console.warn("   Run 'node docs/scripts/generate-manifest-data.mjs' to generate it");
    }
  } catch (error) {
    console.warn(`⚠️  Failed to load manifest data: ${error.message}`);
  }
  
  // Return empty array as fallback
  return [];
}

export async function paths(locale) {
  return (await loadData()).map((item) => {
    return {
      params: {
        type: item.name,
        title: item.title,
        description: item.description,
        identifier: item.identifier,
      },
      content: item.content,
    };
  });
}

export async function loadData(locale) {
  return loadManifestData();
}
