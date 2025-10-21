import { AutoRouter } from "itty-router";
import { handleGetValue, handleSave } from "./cas.js";
import { handleKeyValueGet, handleKeyValuePut } from "./key-value.js";
import { withRouteTiming } from "./metrics.js";

const router = AutoRouter();

router.put(
  "/api/cache/keyvalue/:cas_id",
  withRouteTiming("/api/cache/keyvalue/:cas_id", handleKeyValueGet),
);

router.put(
  "/api/cache/keyvalue",
  withRouteTiming("/api/cache/keyvalue", handleKeyValuePut),
);

router.get(
  "/api/cache/cas/:id",
  withRouteTiming("/api/cache/cas/:id", handleGetValue),
);

router.post(
  "/api/cache/cas/:id",
  withRouteTiming("/api/cache/cas/:id", handleSave),
);

export default router;
