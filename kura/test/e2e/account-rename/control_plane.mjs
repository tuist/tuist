import { writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createServer as createSocket } from "node:net";
import { join } from "node:path";

// Loopback-only control plane for the account rename ShellSpec.
let handle = "original";
const aliases = [handle];

const server = createServer((request, response) => {
  request.resume();
  let payload;
  if (request.method === "GET") {
    payload = {
      peers: [],
      account_handle: handle,
      account_aliases: aliases,
      endpoint_redirects: Object.fromEntries(
        aliases
          .filter((name) => name !== handle)
          .map((name) => [`${name}.example.com`, `https://${handle}.example.com`]),
      ),
      refresh_interval_seconds: 1,
      replication_pull: false,
    };
  } else if (request.method === "POST") {
    const renamed = new Map([
      ["/rename", "renamed"],
      ["/rename-again", "latest"],
      ["/rename-back", "original"],
    ]).get(request.url);
    if (renamed) {
      handle = renamed;
      if (!aliases.includes(handle)) aliases.push(handle);
      payload = {};
    } else if (request.url === "/oauth2/introspect") {
      payload = {
        active: true,
        sub: "test",
        principal_kind: "account",
        cache_grants: {
          account: { read: [], write: [] },
          project: { read: [`${handle}/ios`], write: [`${handle}/ios`] },
        },
      };
    } else {
      payload = { accepted: 1 };
    }
  } else {
    response.writeHead(405).end();
    return;
  }
  const body = JSON.stringify(payload);
  response.writeHead(200, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  response.end(body);
});

const listen = (socket) =>
  new Promise((resolve, reject) => {
    socket.once("error", reject);
    socket.listen(0, "127.0.0.1", () => resolve(socket.address().port));
  });

// Hold both Kura ports until allocated so the OS cannot return the same one.
const publicSocket = createSocket();
const internalSocket = createSocket();
const [controlPort, publicPort, internalPort] = await Promise.all([
  listen(server),
  listen(publicSocket),
  listen(internalSocket),
]);
await Promise.all(
  [publicSocket, internalSocket].map(
    (socket) => new Promise((resolve) => socket.close(resolve)),
  ),
);
const directory = process.argv[2];
await writeFile(join(directory, "kura-ports"), `${publicPort} ${internalPort}\n`);
await writeFile(join(directory, "control-port"), String(controlPort));
