import http from "node:http";
import { setTimeout as sleep } from "node:timers/promises";
import { Readable } from "node:stream";

export async function upload(url, bodyFactory, size, onRetry = () => {}) {
  for (let attempt = 0; ; attempt++) {
    try {
      return await send(
        url,
        typeof bodyFactory === "function" ? bodyFactory() : bodyFactory,
        size,
      );
    } catch (error) {
      if (attempt >= 2 || !["EPIPE", "ECONNRESET"].includes(error.code))
        throw error;
      if (typeof bodyFactory !== "function" && !Buffer.isBuffer(bodyFactory))
        throw error;
      onRetry({ code: error.code, attempt: attempt + 1 });
      await sleep(100 * (attempt + 1));
    }
  }
}
function send(url, body, size) {
  // A concurrent pull may install this version before the direct PUT arrives.
  // The legacy endpoint then returns 204 without draining the upload. Consume
  // that early response instead of letting fetch turn it into an EPIPE failure.
  return new Promise((resolve, reject) => {
    const input = Buffer.isBuffer(body)
      ? Readable.from([body])
      : Readable.from(body, { objectMode: false });
    let responded = false;
    const req = http.request(
      url,
      {
        method: "PUT",
        headers: { "content-length": String(size) },
        timeout: 120000,
      },
      (res) => {
        responded = true;
        input.unpipe(req);
        input.destroy();
        res.resume();
        res.on("end", () => {
          req.destroy();
          if (res.statusCode === 204) resolve();
          else reject(new Error(`seed status ${res.statusCode} for ${url}`));
        });
        res.on("error", reject);
      },
    );
    req.on("timeout", () => req.destroy(new Error("seed deadline")));
    req.on("error", (error) => {
      input.destroy();
      if (!responded) reject(error);
    });
    input.on("error", reject);
    input.pipe(req);
  });
}
