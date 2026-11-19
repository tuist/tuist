import { writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createServer as createSocket } from "node:net";
import { join } from "node:path";

// Loopback-only fixture. Public discovery deliberately advertises reports only:
// Kura must use its authenticated, tenant-bound policy endpoint instead.
let mode = "enabled";
let policyCalls = 0;
let policyStartedAt = 0;
let policyCompletedAt = 0;
const server = createServer(async (request, response) => {
  const url = new URL(request.url, "http://localhost");
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const body = Buffer.concat(chunks).toString();
  let status = 200;
  let payload = {};
  if (url.pathname.startsWith("/policy/")) {
    mode = url.pathname.split("/").pop();
  } else if (url.pathname === "/calls") {
    payload = { policyCalls, policyStartedAt, policyCompletedAt };
  } else if (url.pathname === "/_internal/kura/cache-policy") {
    policyCalls++;
    policyStartedAt = Date.now();
    if (request.headers.authorization !== `Basic ${Buffer.from("test:test").toString("base64")}` ||
        url.searchParams.get("tenant_id") !== "acme") {
      status = 401;
    } else if (mode === "outage") {
      status = 503;
    } else {
      if (mode === "delayed") await new Promise((resolve) => setTimeout(resolve, 2000));
      payload = { tenant_id: "acme", network_trusted_cache_access: mode === "enabled" || mode === "delayed" };
    }
    policyCompletedAt = Date.now();
  } else if (url.pathname === "/oauth2/introspect") {
    payload = {
      active: JSON.parse(body).token === "valid",
      sub: "test", principal_kind: "account",
      cache_grants: {
        account: { read: ["acme"], write: ["acme"] },
        project: { read: ["acme/ios"], write: ["acme/ios"] },
      },
    };
  } else if (url.pathname === "/api/cache/access") {
    status = 401;
  } else if (url.pathname === "/.well-known/tuist.json") {
    payload = { network_trusted_report_publishing: true };
  } else {
    payload = { peers: [], refresh_interval_seconds: 60, replication_pull: false };
  }
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(payload));
});

const listen = (socket) => new Promise((resolve, reject) => {
  socket.once("error", reject);
  socket.listen(0, "127.0.0.1", () => resolve(socket.address().port));
});
const publicSocket = createSocket();
const internalSocket = createSocket();
const [controlPort, publicPort, internalPort] = await Promise.all([
  listen(server), listen(publicSocket), listen(internalSocket),
]);
await Promise.all([publicSocket, internalSocket].map((socket) => new Promise((resolve) => socket.close(resolve))));
await writeFile(join(process.argv[2], "ports"), `${controlPort} ${publicPort} ${internalPort}\n`);
