import http from "node:http";
import fs from "node:fs";
import { once } from "node:events";
import { setTimeout as sleep } from "node:timers/promises";
import { performance } from "node:perf_hooks";

// One aggregate scheduler across both peer listeners, not one allowance per GET.
let next = 0;
async function pace(bytes, signal) {
  if (!fs.existsSync("/fixture/measure")) return;
  const now = performance.now();
  next = Math.max(now, next) + (bytes / 62500000) * 1000;
  // Coalesce sub-millisecond waits instead of limiting each small TCP chunk
  // to Node's timer granularity. Burst allowance is at most 250 kB.
  if (next - now > 4) await sleep(next - now - 2, undefined, { signal });
}
const config = JSON.parse(fs.readFileSync("/fixture/config.json"));
http
  .createServer((req, res) => {
    const replica =
      req.headers.host === `${config.name}-source-peer:7443`
        ? "source"
        : req.headers.host === `${config.name}-target-peer:7443`
          ? "target"
          : null;
    if (!replica) {
      res.writeHead(400).end();
      return;
    }
    const target = `${config.name}-${replica}`;
    const started = Date.now();
    const abort = new AbortController();
    let bytes = 0,
      completed = false;
    const shaped = /^\/_internal\/backfill\/(artifacts\/|bodies)/.test(req.url);
    const upstream = http.request(
      {
        host: target,
        port: 7443,
        path: req.url,
        method: req.method,
        headers: { ...req.headers, host: `${target}:7443` },
      },
      async (response) => {
        res.writeHead(response.statusCode, response.headers);
        try {
          for await (const chunk of response) {
            if (shaped) await pace(chunk.length, abort.signal);
            if (res.destroyed) break;
            bytes += chunk.length;
            if (!res.write(chunk))
              await once(res, "drain", { signal: abort.signal });
          }
          completed = response.complete;
          res.end();
        } catch (error) {
          res.destroy(error);
        }
      },
    );
    upstream.on("error", (error) => {
      if (!res.headersSent) res.writeHead(502);
      res.end();
    });
    req.on("aborted", () => upstream.destroy());
    res.on("close", () => {
      abort.abort();
      upstream.destroy();
      if (fs.existsSync("/fixture/measure"))
        fs.appendFileSync(
          "/fixture/proxy.jsonl",
          JSON.stringify({
            started,
            ms: Date.now() - started,
            target,
            method: req.method,
            route: req.url.split("?")[0],
            status: res.statusCode,
            bytes,
            completed,
          }) + "\n",
        );
    });
    req.pipe(upstream);
  })
  .listen(7443, "0.0.0.0");
