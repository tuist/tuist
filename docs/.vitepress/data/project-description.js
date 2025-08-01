import * as path from "node:path";
import fs from "node:fs";

const manifestDataFile = path.join(import.meta.dirname, "manifest-data.json");

// Cache the manifest data to avoid loading it multiple times
let cachedManifestData = null;

function loadManifestData() {
  // Return cached data if already loaded
  if (cachedManifestData !== null) {
    return cachedManifestData;
  }

  try {
    if (fs.existsSync(manifestDataFile)) {
      const manifestData = JSON.parse(fs.readFileSync(manifestDataFile, "utf-8"));
      if (manifestData.data && !manifestData.error) {
        console.log(`✅ Loaded manifest data from ${manifestDataFile} (${manifestData.data.length} items)`);
        cachedManifestData = manifestData.data;
        return cachedManifestData;
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
  
  // Cache and return empty array as fallback
  cachedManifestData = [];
  return cachedManifestData;
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
