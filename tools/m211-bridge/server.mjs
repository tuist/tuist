import http from "node:http";
import { randomBytes, randomUUID } from "node:crypto";
import { readFile, open, mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = fileURLToPath(new URL(".", import.meta.url));
const token = () => randomBytes(32).toString("base64url");
const escape = (s) =>
  s.replace(
    /[&<>"']/g,
    (c) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&apos;",
      })[c],
  );
const TTL = 8 * 60 * 60 * 1000;
const STALE = 35_000;

export function createBridge({
  restoredSession,
  authorization,
  journalPath,
} = {}) {
  const sessions = new Map();
  const creations = new Map();
  if (restoredSession)
    sessions.set(restoredSession.id, {
      ...restoredSession,
      jobs: [],
      relay: null,
    });
  const permitted = (session) => authorization?.sessionId === session.id;
  const files = {
    "/": ["index.html", "text/html"],
    "/relay": ["index.html", "text/html"],
    "/app.js": ["app.js", "text/javascript"],
    "/style.css": ["style.css", "text/css"],
    "/sdk/bundle.js": [
      "node_modules/@bradycorporation/brady-web-sdk/dist/bundle.js",
      "text/javascript",
    ],
    "/sdk/brady_printing_core_web.wasm": [
      "node_modules/@bradycorporation/brady-web-sdk/dist/brady_printing_core_web.wasm",
      "application/wasm",
    ],
  };
  return http.createServer(async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Permissions-Policy", "bluetooth=(self)");
    res.setHeader(
      "Content-Security-Policy",
      "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; img-src 'self' blob: data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
    );
    const send = (status, value) => {
      res.writeHead(status, { "Content-Type": "application/json" });
      res.end(JSON.stringify(value));
    };
    const fail = (status, message) =>
      Object.assign(new Error(message), { status });
    try {
      const path = new URL(req.url, "http://bridge").pathname;
      if (req.method === "GET" && path === "/health")
        return send(200, { ok: true });
      if (req.method === "GET" && files[path]) {
        const [name, type] = files[path];
        res.writeHead(200, { "Content-Type": type });
        return res.end(await readFile(root + name));
      }
      let body;
      const json = async () => {
        if (body !== undefined) return body;
        if (!req.headers["content-type"]?.startsWith("application/json"))
          throw fail(415, "Use application/json.");
        let size = 0;
        const chunks = [];
        for await (const chunk of req) {
          size += chunk.length;
          if (size > 12 * 1024 * 1024)
            throw fail(413, "Request too large (12 MB maximum).");
          chunks.push(chunk);
        }
        try {
          body = JSON.parse(Buffer.concat(chunks).toString());
        } catch {
          throw fail(400, "Invalid JSON.");
        }
        if (!body || typeof body !== "object" || Array.isArray(body))
          throw fail(400, "Expected a JSON object.");
        return body;
      };
      if (path === "/api/sessions" && req.method === "POST") {
        const now = Date.now();
        for (const [id, session] of sessions)
          if (session.expiresAt <= now) sessions.delete(id);
        for (const [ip, attempts] of creations)
          if (attempts.at < now - 60_000) creations.delete(ip);
        const ip = req.socket.remoteAddress;
        const attempt = creations.get(ip) || { at: now, count: 0 };
        if (++attempt.count > 10 || sessions.size >= 50)
          throw fail(429, "Session limit reached. Try later.");
        creations.set(ip, attempt);
        const session = {
          id: randomUUID(),
          controlToken: token(),
          relayToken: token(),
          expiresAt: now + TTL,
          jobs: [],
          relay: null,
        };
        sessions.set(session.id, session);
        return send(201, {
          id: session.id,
          controlToken: session.controlToken,
          relayToken: session.relayToken,
          expiresAt: session.expiresAt,
        });
      }
      const match = path.match(/^\/api\/sessions\/([\w-]+)(.*)$/);
      if (!match) throw fail(404, "Not found.");
      const session = sessions.get(match[1]);
      if (!session || session.expiresAt <= Date.now())
        throw fail(401, "Session missing or expired. Create a new session.");
      const auth = req.headers.authorization;
      const role =
        auth === `Bearer ${session.controlToken}`
          ? "control"
          : auth === `Bearer ${session.relayToken}`
            ? "relay"
            : null;
      if (!role) throw fail(401, "Session credential required.");
      const tail = match[2];
      const requireRole = (wanted) => {
        if (role !== wanted)
          throw fail(
            403,
            "This session credential cannot perform that action.",
          );
      };
      if (tail === "/cut" && req.method === "POST") {
        requireRole("control");
        if (!permitted(session) || authorization.allowCut !== true)
          throw fail(403, "No single-use cut authorization for this session.");
        const existing = session.jobs.find((j) => j.action === "cut");
        if (existing)
          return send(200, { jobId: existing.id, state: existing.state });
        const printed = await readFile(journalPath, "utf8")
          .then(JSON.parse)
          .catch((error) => {
            if (error.code === "ENOENT")
              throw fail(
                409,
                "No print attempt for this authorization to cut.",
              );
            throw error;
          });
        const concurrent = session.jobs.find((j) => j.action === "cut");
        if (concurrent)
          return send(200, { jobId: concurrent.id, state: concurrent.state });
        if (printed.sessionId !== session.id)
          throw fail(409, "No print attempt in this session to cut.");
        const status = session.relay;
        if (
          !status?.connected ||
          !status.cutReady ||
          Date.now() - status.seenAt >= STALE ||
          status.name !== authorization.printer ||
          status.supply !== authorization.supply
        )
          throw fail(
            409,
            "Updated cut-capable relay must be connected to the authorized printer and supply.",
          );
        const job = {
          id: randomUUID(),
          action: "cut",
          title: "Cut existing label only",
          state: "queued",
          printer: authorization.printer,
          supply: authorization.supply,
        };
        session.jobs.push(job);
        return send(200, { jobId: job.id, state: job.state });
      }
      if (tail === "/print" && req.method === "POST") {
        requireRole("control");
        if (!permitted(session))
          throw fail(403, "No print authorization for this session.");
        const { jobId } = await json();
        const job = session.jobs.find((j) => j.id === jobId);
        if (!job || job.title !== authorization.text)
          throw fail(403, "Only the explicitly authorized label may print.");
        if (job.state !== "preview-only")
          return send(200, { jobId, state: job.state });
        const live = session.relay && Date.now() - session.relay.seenAt < STALE;
        if (
          !live ||
          !session.relay.connected ||
          session.relay.name !== authorization.printer ||
          session.relay.supply !== authorization.supply
        )
          throw fail(
            409,
            "Authorized printer and supply must be connected with fresh status.",
          );
        if (session.jobs.some((j) => j.state !== "preview-only"))
          throw fail(409, "The single print authorization is already in use.");
        job.state = "queued";
        job.printer = authorization.printer;
        job.supply = authorization.supply;
        return send(200, { jobId, state: job.state });
      }
      const operation = tail.match(/^\/jobs\/([\w-]+)\/(claim|result)$/);
      if (operation && req.method === "POST") {
        requireRole("relay");
        const data = await json();
        const job = session.jobs.find((j) => j.id === operation[1]);
        if (!job) throw fail(404, "Job not found.");
        if (operation[2] === "claim") {
          if (
            !session.relay ||
            session.relay.clientId !== data.clientId ||
            Date.now() - session.relay.seenAt >= STALE
          )
            throw fail(409, "Only the active relay may dispatch a job.");
          if (
            !permitted(session) ||
            (job.action === "cut" && authorization.allowCut !== true) ||
            !session.relay.connected ||
            job.state !== "queued" ||
            session.relay.name !== job.printer ||
            session.relay.supply !== job.supply
          )
            throw fail(
              409,
              "Job cannot be claimed. Never retry an uncertain print.",
            );
          // A durable exclusive marker is written BEFORE granting dispatch. Even a lost
          // HTTP response, tab refresh or server restart must not allow another attempt.
          let handle;
          try {
            handle = await open(
              job.action === "cut" ? journalPath + ".cut" : journalPath,
              "wx",
              0o600,
            );
            await handle.writeFile(
              JSON.stringify({
                sessionId: session.id,
                jobId: job.id,
                title: job.title,
                at: Date.now(),
              }),
            );
            await handle.sync();
          } catch (error) {
            if (error.code === "EEXIST")
              throw fail(
                409,
                "Single-use authorization already consumed; inspect the physical printer.",
              );
            throw error;
          } finally {
            await handle?.close();
          }
          job.state = "dispatched";
          job.dispatchedBy = data.clientId;
          return send(200, { jobId: job.id, state: job.state });
        }
        if (job.state !== "dispatched" || job.dispatchedBy !== data.clientId)
          throw fail(409, "No dispatched job belongs to this relay.");
        job.state = data.success === true ? "sdk-confirmed" : "uncertain";
        job.result = String(data.message || "").slice(0, 300);
        return send(200, { jobId: job.id, state: job.state });
      }
      if (!tail && req.method === "GET") {
        const live = session.relay && Date.now() - session.relay.seenAt < STALE;
        return send(200, {
          id: session.id,
          expiresAt: session.expiresAt,
          printingEnabled: permitted(session),
          printAuthorization: permitted(session)
            ? { text: authorization.text, copies: 1, cut: false }
            : null,
          cutAuthorized: permitted(session) && authorization.allowCut === true,
          relay: session.relay
            ? {
                ...session.relay,
                connected: !!live && session.relay.connected,
                stale: !live,
              }
            : null,
          jobs: session.jobs.map(({ png, ...job }) => job),
        });
      }
      const image = tail.match(/^\/jobs\/([\w-]+)\.png$/);
      if (image && req.method === "GET") {
        const job = session.jobs.find((j) => j.id === image[1]);
        if (!job?.png) throw fail(404, "Label image not found.");
        res.writeHead(200, { "Content-Type": "image/png" });
        return res.end(job.png);
      }
      if (tail === "/jobs" && req.method === "POST") {
        requireRole("control");
        const { items, widthMm = 50, heightMm = 12 } = await json();
        if (
          !Array.isArray(items) ||
          !items.length ||
          items.length > 50 ||
          items.length + session.jobs.length > 100
        )
          throw fail(400, "Submit 1–50 labels; at most 100 per session.");
        if (
          !Number.isFinite(widthMm) ||
          widthMm < 10 ||
          widthMm > 200 ||
          !Number.isFinite(heightMm) ||
          heightMm < 5 ||
          heightMm > 20
        )
          throw fail(400, "Preview size must be 10–200 mm × 5–20 mm.");
        const jobs = [];
        for (const item of items) {
          if (!item || typeof item !== "object")
            throw fail(400, "Invalid label.");
          let png, title;
          if (
            typeof item.text === "string" &&
            item.text.trim() &&
            item.text.length <= 120
          ) {
            title = item.text.trim();
            const w = Math.round((widthMm * 203) / 25.4),
              h = Math.round((heightMm * 203) / 25.4);
            const text = await sharp({
              text: {
                text: escape(title),
                font: "DejaVu Sans Bold",
                width: w - 24,
                height: h - 20,
                align: "centre",
                rgba: true,
              },
            })
              .png()
              .toBuffer();
            png = await sharp({
              create: {
                width: w,
                height: h,
                channels: 3,
                background: "#ffffff",
              },
            })
              .composite([{ input: text, gravity: "centre" }])
              .png()
              .toBuffer();
          } else if (
            typeof item.png === "string" &&
            item.png.length <= 3_000_000
          ) {
            title = "Uploaded PNG";
            try {
              const data = Buffer.from(item.png, "base64");
              const image = sharp(data, { limitInputPixels: 4_000_000 });
              const meta = await image.metadata();
              if (meta.format !== "png" || meta.pages > 1) throw new Error();
              png = await image
                .flatten({ background: "#ffffff" })
                .png()
                .toBuffer();
            } catch {
              throw fail(
                400,
                "Provide a valid single-frame PNG (maximum 4 megapixels).",
              );
            }
          } else
            throw fail(
              400,
              "Each label needs text (1–120 characters) or a PNG.",
            );
          jobs.push({
            id: randomUUID(),
            title,
            widthMm,
            heightMm,
            state: "preview-only",
            png,
          });
        }
        if (session.jobs.length + jobs.length > 100)
          throw fail(400, "At most 100 labels per session.");
        if (
          session.jobs.reduce((n, j) => n + (j.png?.length || 0), 0) +
            jobs.reduce((n, j) => n + j.png.length, 0) >
          16_000_000
        )
          throw fail(413, "Session image limit reached (16 MB).");
        session.jobs.push(...jobs);
        return send(201, { queued: jobs.length, state: "preview-only" });
      }
      if (tail === "/relay" && req.method === "POST") {
        requireRole("relay");
        const data = await json();
        if (
          typeof data.clientId !== "string" ||
          !/^[\w-]{10,80}$/.test(data.clientId)
        )
          throw fail(400, "Relay client ID required.");
        if (
          session.relay &&
          session.relay.clientId !== data.clientId &&
          Date.now() - session.relay.seenAt < STALE
        )
          throw fail(
            409,
            "Another Chrome relay tab is active. Close it and wait 35 seconds.",
          );
        const clean = (name) => String(data[name] ?? "").slice(0, 300);
        session.relay = {
          clientId: data.clientId,
          seenAt: Date.now(),
          connected: data.connected === true,
          message: clean("message"),
          model: clean("model"),
          name: clean("name"),
          supply: clean("supply"),
          dimensions: clean("dimensions"),
          printerStatus: clean("printerStatus"),
          zoneDimensions: JSON.stringify(data.zoneDimensions ?? []).slice(
            0,
            3000,
          ),
          supplyWidth: clean("supplyWidth"),
          supplyHeight: clean("supplyHeight"),
          cutReady: data.cutReady === true,
        };
        return send(200, { ok: true });
      }
      throw fail(404, "Not found.");
    } catch (error) {
      if (!res.headersSent)
        send(error.status || 500, {
          error: error.status ? error.message : "Bridge server error.",
        });
      else res.end();
    }
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const stateDir =
    process.env.M211_STATE_DIR || join(homedir(), ".config/m211-bridge");
  // No authorization file is loaded implicitly: a fresh checkout is preview-only.
  const authorization = process.env.M211_AUTHORIZATION
    ? JSON.parse(await readFile(process.env.M211_AUTHORIZATION, "utf8"))
    : undefined;
  let restoredSession, journalPath;
  if (authorization) {
    if (
      !/^[a-zA-Z0-9_-]{1,80}$/.test(authorization.id || "") ||
      !["sessionId", "text", "printer", "supply"].every(
        (key) =>
          typeof authorization[key] === "string" && authorization[key].trim(),
      ) ||
      (authorization.allowCut !== undefined &&
        typeof authorization.allowCut !== "boolean")
    )
      throw new Error(
        "Authorization needs an id (letters, digits, _ or -), sessionId, text, printer, supply and optional boolean allowCut.",
      );
    restoredSession = JSON.parse(
      await readFile(
        process.env.M211_SESSION || join(stateDir, "session.json"),
        "utf8",
      ),
    );
    if (
      restoredSession.id !== authorization.sessionId ||
      restoredSession.expiresAt <= Date.now()
    )
      throw new Error(
        "Authorization must match the saved, unexpired CLI session.",
      );
    await mkdir(stateDir, { recursive: true, mode: 0o700 });
    journalPath = join(stateDir, `dispatch-${authorization.id}.json`);
  }
  const server = createBridge({ restoredSession, authorization, journalPath });
  server.listen(
    Number(process.env.PORT || 3077),
    process.env.HOST || "127.0.0.1",
    () =>
      console.log(
        `M211 bridge listening on port ${server.address().port}; ${authorization ? "single-use authorization loaded" : "preview only"}.`,
      ),
  );
}
