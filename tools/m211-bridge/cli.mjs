#!/usr/bin/env node
import { readFile, mkdir, chmod, open, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const file =
  process.env.M211_SESSION ||
  join(
    process.env.M211_STATE_DIR || join(homedir(), ".config/m211-bridge"),
    "session.json",
  );
const [command, ...args] = process.argv.slice(2);
async function request(base, path, method = "GET", token, data) {
  const response = await fetch(base + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(data ? { body: JSON.stringify(data) } : {}),
  });
  if (!response.headers.get("content-type")?.includes("application/json"))
    throw new Error(
      "Bridge did not return JSON. Check the URL and portal access.",
    );
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
  return result;
}
function links(session) {
  const browserBase = session.browserBase || session.base;
  const control = new URLSearchParams({
    session: session.id,
    token: session.controlToken,
    relayToken: session.relayToken,
  });
  const relay = new URLSearchParams({
    session: session.id,
    token: session.relayToken,
  });
  console.log(
    `Private control / preview link:\n${browserBase}/#${control}\n\nPrivate Chrome relay link:\n${browserBase}/relay#${relay}\n\nLinks expire with this 8-hour session. Do not share them publicly.`,
  );
}
try {
  if (command === "init") {
    if (!args[0])
      throw new Error(
        "Usage: node cli.mjs init <API origin> [browser HTTPS portal origin]",
      );
    const url = new URL(args[0]);
    if (
      url.protocol !== "https:" &&
      !(
        url.protocol === "http:" &&
        ["localhost", "127.0.0.1"].includes(url.hostname)
      )
    )
      throw new Error("Use HTTPS (or localhost for software testing).");
    if (
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      url.pathname !== "/"
    )
      throw new Error(
        "Use the bridge origin URL, without a path, query or credentials.",
      );
    const base = url.origin;
    const browserUrl = new URL(args[1] || base);
    if (
      browserUrl.username ||
      browserUrl.password ||
      browserUrl.search ||
      browserUrl.hash ||
      browserUrl.pathname !== "/" ||
      (args[1] && browserUrl.protocol !== "https:")
    )
      throw new Error(
        "The optional browser portal URL must be an HTTPS origin.",
      );
    // Exclusive creation avoids silently discarding credentials for an active session.
    await mkdir(dirname(file), { recursive: true, mode: 0o700 });
    const handle = await open(file, "wx", 0o600);
    try {
      const session = {
        ...(await request(base, "/api/sessions", "POST")),
        base,
        browserBase: browserUrl.origin,
      };
      await handle.writeFile(JSON.stringify(session));
      console.log(
        `Created preview-only session. Credentials saved with mode 0600 at ${file}.`,
      );
      links(session);
    } catch (error) {
      await unlink(file);
      throw error;
    } finally {
      await handle.close();
    }
  } else if (
    [
      "status",
      "submit-text",
      "submit-png",
      "links",
      "print-one",
      "cut-once",
    ].includes(command)
  ) {
    const session = JSON.parse(await readFile(file, "utf8"));
    await chmod(file, 0o600);
    const path = `/api/sessions/${session.id}`;
    if (command === "links") links(session);
    else if (command === "cut-once") {
      if (args.length) throw new Error("Usage: node cli.mjs cut-once");
      console.log(
        JSON.stringify(
          await request(
            session.base,
            path + "/cut",
            "POST",
            session.controlToken,
            {},
          ),
          null,
          2,
        ),
      );
    } else if (command === "print-one") {
      if (args.length !== 1)
        throw new Error("Usage: node cli.mjs print-one <job-id>");
      console.log(
        JSON.stringify(
          await request(
            session.base,
            path + "/print",
            "POST",
            session.controlToken,
            { jobId: args[0] },
          ),
          null,
          2,
        ),
      );
    } else if (command === "status")
      console.log(
        JSON.stringify(
          await request(session.base, path, "GET", session.controlToken),
          null,
          2,
        ),
      );
    else {
      if (!args.length)
        throw new Error(
          `Usage: node cli.mjs ${command} <${command === "submit-text" ? "text-file> [width-mm height-mm]" : "png-file> [png-file ...]"}`,
        );
      const items =
        command === "submit-text"
          ? (await readFile(args[0], "utf8"))
              .split(/\r?\n/)
              .filter((s) => s.trim())
              .map((text) => ({ text }))
          : await Promise.all(
              args.map(async (name) => ({
                png: (await readFile(name)).toString("base64"),
              })),
            );
      const size =
        command === "submit-text"
          ? { widthMm: Number(args[1] || 50), heightMm: Number(args[2] || 12) }
          : {};
      console.log(
        JSON.stringify(
          await request(
            session.base,
            path + "/jobs",
            "POST",
            session.controlToken,
            { items, ...size },
          ),
          null,
          2,
        ),
      );
    }
  } else {
    console.log(
      "M211 bridge — CLI with local Chrome Bluetooth relay\n\n  init <API-origin> [browser-HTTPS-portal-origin]\n  links\n  submit-text <text-file> [width-mm height-mm]\n  submit-png <png-file> [png-file ...]\n  status\n  print-one <job-id>\n  cut-once\n\nPrinting/cutting require server-side single-use authorization. No retries. Set M211_STATE_DIR or M211_SESSION for private runtime state.",
    );
    if (command) process.exitCode = 1;
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
