// Local test-only Kubernetes ConfigMap endpoint. The production controller is
// exercised by the staging harness; this fixture isolates runtime resource costs.
import https from "node:https";
import fs from "node:fs";
https
  .createServer(
    {
      key: fs.readFileSync("/fixture/server.key"),
      cert: fs.readFileSync("/fixture/server.crt"),
    },
    (req, res) => {
      if (
        req.url !==
        "/api/v1/namespaces/qualification/configmaps/qualification-serving"
      ) {
        res.writeHead(404).end();
        return;
      }
      try {
        const grant = JSON.parse(
          fs.readFileSync("/fixture/grant.json", "utf8"),
          (_key, value, context) =>
            typeof value === "number" && !Number.isSafeInteger(value)
              ? JSON.rawJSON(context.source)
              : value,
        );
        if (grant.renew) grant.expires_ms = Date.now() + 14000;
        delete grant.renew;
        res.setHeader("content-type", "application/json");
        res.end(JSON.stringify({ data: { grant: JSON.stringify(grant) } }));
      } catch {
        res.writeHead(503).end();
      }
    },
  )
  .listen(443, "0.0.0.0");
