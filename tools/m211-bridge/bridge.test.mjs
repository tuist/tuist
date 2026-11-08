import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readFile, writeFile, stat, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import sharp from "sharp";
import { createBridge } from "./server.mjs";

async function setup(t, options = {}) {
  const server = createBridge(options).listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (path, token, method = "GET", data) =>
    fetch(base + path, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(data === undefined ? {} : { body: JSON.stringify(data) }),
    });
  const session =
    options.restoredSession ||
    (await (await call("/api/sessions", null, "POST")).json());
  return { base, call, session, path: `/api/sessions/${session.id}` };
}

test("scoped sessions queue real PNG previews and never accept print operations", async (t) => {
  const { call, session: s, path } = await setup(t);
  const other = await (await call("/api/sessions", null, "POST")).json();
  assert.equal((await call(path)).status, 401);
  assert.equal((await call(path, other.controlToken)).status, 401);
  assert.equal(
    (
      await call(path + "/jobs", s.relayToken, "POST", {
        items: [{ text: "wrong role" }],
      })
    ).status,
    403,
  );
  const data = {
    items: [{ text: "BER1-R02-SW07" }, { text: '<rack & "port">' }],
    widthMm: 73,
    heightMm: 9,
  };
  assert.equal(
    (await call(path + "/jobs", s.controlToken, "POST", data)).status,
    201,
  );
  const state = await (await call(path, s.relayToken)).json();
  assert.equal(state.printingEnabled, false);
  assert.deepEqual(
    state.jobs.map((j) => j.title),
    ["BER1-R02-SW07", '<rack & "port">'],
  );
  assert.ok(!JSON.stringify(state).includes(s.controlToken));
  const imagePath = path + `/jobs/${state.jobs[0].id}.png`;
  assert.equal((await call(imagePath, other.relayToken)).status, 401);
  const image = Buffer.from(
    await (await call(imagePath, s.relayToken)).arrayBuffer(),
  );
  const meta = await sharp(image).metadata();
  assert.equal(meta.format, "png");
  assert.equal(meta.width, 583);
  assert.equal(meta.height, 72);
  const stats = await sharp(image).stats();
  assert.ok(
    stats.channels[0].min < 50 && stats.channels[0].max === 255,
    "Image has dark label text on white background",
  );
  assert.equal(
    (
      await call(path + "/jobs", s.controlToken, "POST", {
        items: [{ text: "valid" }, { png: "broken" }],
      })
    ).status,
    400,
  );
  assert.equal(
    (await (await call(path, s.controlToken)).json()).jobs.length,
    2,
    "Invalid batch is atomic",
  );
  assert.equal(
    (
      await call(path + "/jobs", s.controlToken, "POST", {
        items: [{ png: image.toString("base64") }],
      })
    ).status,
    201,
  );
  assert.equal(
    (await call(path + "/print", s.controlToken, "POST", {})).status,
    403,
  );
  assert.equal(
    (await call(path + "/cut", s.controlToken, "POST", {})).status,
    403,
  );
  for (const action of ["feed", "reset", "settings"])
    assert.equal(
      (await call(path + "/" + action, s.controlToken, "POST", {})).status,
      404,
    );
});

test("relay lease, heartbeat staleness and session expiry do not imply a live connection", async (t) => {
  const { call, session: s, path } = await setup(t);
  const now = Date.now();
  let clock = now;
  t.mock.method(Date, "now", () => clock);
  const status = {
    clientId: "relay-client-one",
    connected: true,
    model: "M211",
    supply: "M21-750-499",
  };
  assert.equal(
    (await call(path + "/relay", s.controlToken, "POST", status)).status,
    403,
  );
  assert.equal(
    (await call(path + "/relay", s.relayToken, "POST", status)).status,
    200,
  );
  assert.equal(
    (await (await call(path, s.controlToken)).json()).relay.connected,
    true,
  );
  assert.equal(
    (
      await call(path + "/relay", s.relayToken, "POST", {
        ...status,
        clientId: "relay-client-two",
      })
    ).status,
    409,
  );
  clock = now + 35_001;
  const stale = await (await call(path, s.controlToken)).json();
  assert.equal(stale.relay.stale, true);
  assert.equal(stale.relay.connected, false);
  assert.equal(
    (
      await call(path + "/relay", s.relayToken, "POST", {
        ...status,
        clientId: "relay-client-two",
        connected: false,
      })
    ).status,
    200,
  );
  clock = now + 8 * 60 * 60 * 1000 + 1;
  assert.equal((await call(path, s.controlToken)).status, 401);
});

test("CLI creates private credentials, submits ordered labels and reports preview-only status", async (t) => {
  const { base } = await setup(t);
  const dir = await mkdtemp(join(tmpdir(), "m211-test-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const env = { ...process.env, M211_SESSION: join(dir, "session.json") };
  const cli = (...args) =>
    promisify(execFile)(
      process.execPath,
      [new URL("./cli.mjs", import.meta.url).pathname, ...args],
      { env },
    );
  const created = await cli("init", base);
  assert.match(created.stdout, /Private Chrome relay link/);
  assert.equal((await stat(env.M211_SESSION)).mode & 0o777, 0o600);
  const saved = await readFile(env.M211_SESSION, "utf8");
  await assert.rejects(cli("init", base));
  assert.equal(
    await readFile(env.M211_SESSION, "utf8"),
    saved,
    "Second init cannot overwrite an active credential",
  );
  const labels = join(dir, "labels.txt");
  await writeFile(labels, "BER1-R02-P09\r\n\r\nBER1-R02-SW03\r\n");
  const submitted = JSON.parse(
    (await cli("submit-text", labels, "61", "11")).stdout,
  );
  assert.deepEqual(submitted, { queued: 2, state: "preview-only" });
  const state = JSON.parse((await cli("status")).stdout);
  assert.deepEqual(
    state.jobs.map((j) => j.title),
    ["BER1-R02-P09", "BER1-R02-SW03"],
  );
  assert.equal(state.relay, null);
  assert.equal(state.printingEnabled, false);
  await assert.rejects(cli("print"));
});

test("one authorized label dispatches once, even with concurrent claims or a server restart", async (t) => {
  const dir = await mkdtemp(join(tmpdir(), "m211-print-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const session = {
    id: "test-session",
    controlToken: "control",
    relayToken: "relay",
    expiresAt: Date.now() + 60_000,
  };
  const options = {
    restoredSession: session,
    authorization: {
      sessionId: session.id,
      text: "ASYMMETRIC-TEST",
      printer: "M211-ONE",
      supply: "TEST-SUPPLY",
    },
    journalPath: join(dir, "dispatched.json"),
  };
  const { call, path } = await setup(t, options);
  const report = {
    clientId: "test-relay-client",
    connected: true,
    name: "M211-ONE",
    supply: "TEST-SUPPLY",
  };
  await call(path + "/relay", "relay", "POST", report);
  await call(path + "/jobs", "control", "POST", {
    items: [{ text: "WRONG-LABEL" }, { text: "ASYMMETRIC-TEST" }],
  });
  const jobs = (await (await call(path, "control")).json()).jobs;
  assert.equal(
    (await call(path + "/print", "control", "POST", { jobId: jobs[0].id }))
      .status,
    403,
  );
  assert.equal(
    (await call(path + "/print", "relay", "POST", { jobId: jobs[1].id }))
      .status,
    403,
  );
  await call(path + "/relay", "relay", "POST", {
    ...report,
    supply: "WRONG-SUPPLY",
  });
  assert.equal(
    (await call(path + "/print", "control", "POST", { jobId: jobs[1].id }))
      .status,
    409,
  );
  await call(path + "/relay", "relay", "POST", report);
  const print = () =>
    call(path + "/print", "control", "POST", { jobId: jobs[1].id });
  assert.equal((await print()).status, 200);
  assert.equal(
    (await print()).status,
    200,
    "Repeated submission is idempotent",
  );
  const claim = () =>
    call(path + `/jobs/${jobs[1].id}/claim`, "relay", "POST", {
      clientId: report.clientId,
    });
  assert.deepEqual(
    (await Promise.all([claim(), claim()])).map((r) => r.status).sort(),
    [200, 409],
  );
  assert.equal((await stat(options.journalPath)).mode & 0o777, 0o600);
  assert.equal(
    JSON.parse(await readFile(options.journalPath, "utf8")).title,
    "ASYMMETRIC-TEST",
  );
  assert.equal(
    (await (await print()).json()).state,
    "dispatched",
    "Lost dispatch result never requeues",
  );
  const later = Date.now() + 40_000;
  t.mock.method(Date, "now", () => later);
  assert.equal(
    (
      await call(path + `/jobs/${jobs[1].id}/result`, "relay", "POST", {
        clientId: report.clientId,
        success: false,
        message: "Transport lost",
      })
    ).status,
    200,
    "A slow print can report after heartbeat staleness",
  );
  assert.equal((await (await print()).json()).state, "uncertain");
  assert.equal((await claim()).status, 409);
  const restarted = await setup(t, options);
  await restarted.call(path + "/relay", "relay", "POST", report);
  await restarted.call(path + "/jobs", "control", "POST", {
    items: [{ text: "ASYMMETRIC-TEST" }],
  });
  const newJob = (await (await restarted.call(path, "control")).json()).jobs[0];
  await restarted.call(path + "/print", "control", "POST", {
    jobId: newJob.id,
  });
  assert.equal(
    (
      await restarted.call(path + `/jobs/${newJob.id}/claim`, "relay", "POST", {
        clientId: report.clientId,
      })
    ).status,
    409,
    "Restart cannot reuse consumed authorization",
  );
});

test("separately authorized cut consumes its own single-use marker without creating any print job", async (t) => {
  const dir = await mkdtemp(join(tmpdir(), "m211-cut-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const s = {
    id: "cut-session",
    controlToken: "control",
    relayToken: "relay",
    expiresAt: Date.now() + 60_000,
  };
  const journalPath = join(dir, "printed.json");
  await writeFile(journalPath, JSON.stringify({ sessionId: s.id }));
  const options = {
    restoredSession: s,
    authorization: {
      sessionId: s.id,
      text: "PRINTED",
      printer: "M211-TEST",
      supply: "SUPPLY",
      allowCut: true,
    },
    journalPath,
  };
  const { call, path } = await setup(t, options);
  assert.equal((await call(path + "/cut", "relay", "POST", {})).status, 403);
  assert.equal((await call(path + "/cut", "control", "POST", {})).status, 409);
  const report = {
    clientId: "cut-relay-client",
    connected: true,
    name: "M211-TEST",
    supply: "SUPPLY",
    cutReady: true,
  };
  await call(path + "/relay", "relay", "POST", report);
  const cut = await (await call(path + "/cut", "control", "POST", {})).json();
  const again = await (await call(path + "/cut", "control", "POST", {})).json();
  assert.equal(again.jobId, cut.jobId);
  const claim = () =>
    call(path + `/jobs/${cut.jobId}/claim`, "relay", "POST", {
      clientId: report.clientId,
    });
  assert.deepEqual(
    (await Promise.all([claim(), claim()])).map((r) => r.status).sort(),
    [200, 409],
  );
  assert.equal(
    (await (await call(path, "control")).json()).jobs[0].action,
    "cut",
  );
  assert.equal((await (await call(path, "control")).json()).jobs.length, 1);
  assert.equal(
    JSON.parse(await readFile(journalPath, "utf8")).sessionId,
    s.id,
    "Original print marker is not touched",
  );
  assert.equal((await stat(journalPath + ".cut")).mode & 0o777, 0o600);
  const restarted = await setup(t, options);
  await restarted.call(path + "/relay", "relay", "POST", report);
  const next = await (
    await restarted.call(path + "/cut", "control", "POST", {})
  ).json();
  assert.equal(
    (
      await restarted.call(
        path + `/jobs/${next.jobId}/claim`,
        "relay",
        "POST",
        { clientId: report.clientId },
      )
    ).status,
    409,
  );
});

test("server entrypoint defaults to preview and only restores an explicitly authorized session", async (t) => {
  const dir = await mkdtemp(join(tmpdir(), "m211-startup-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const env = {
    ...process.env,
    PORT: "0",
    HOST: "127.0.0.1",
    M211_STATE_DIR: dir,
    M211_SESSION: "",
    M211_AUTHORIZATION: "",
  };
  const entry = new URL("./server.mjs", import.meta.url).pathname;
  async function start(overrides = {}) {
    const child = spawn(process.execPath, [entry], {
      env: { ...env, ...overrides },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stop = async () => {
      if (child.exitCode === null && child.signalCode === null) {
        const exited = once(child, "exit");
        child.kill();
        await exited;
      }
    };
    t.after(stop);
    const base = await new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("Startup timed out")),
        10_000,
      );
      child.stdout.on("data", (chunk) => {
        const port = chunk.toString().match(/listening on port (\d+)/)?.[1];
        if (port) {
          clearTimeout(timer);
          resolve(`http://127.0.0.1:${port}`);
        }
      });
      child.once("exit", () => {
        clearTimeout(timer);
        reject(new Error("Server exited before readiness"));
      });
    });
    return { base, stop };
  }
  const preview = await start();
  const cli = promisify(execFile);
  await cli(
    process.execPath,
    [new URL("./cli.mjs", import.meta.url).pathname, "init", preview.base],
    { env },
  );
  const s = JSON.parse(await readFile(join(dir, "session.json"), "utf8"));
  const get = (base) =>
    fetch(base + `/api/sessions/${s.id}`, {
      headers: { Authorization: `Bearer ${s.controlToken}` },
    }).then((r) => r.json());
  assert.equal((await get(preview.base)).printingEnabled, false);
  await preview.stop();
  const file = join(dir, "authorization.json");
  const auth = {
    id: "review-1",
    sessionId: s.id,
    text: "SAMPLE-ONE",
    printer: "TEST-M211",
    supply: "TEST-SUPPLY",
    allowCut: false,
  };
  await writeFile(file, JSON.stringify({ ...auth, id: "../unsafe" }));
  await assert.rejects(
    cli(process.execPath, [entry], {
      env: { ...env, M211_AUTHORIZATION: file },
    }),
    /Authorization needs an id/,
  );
  await writeFile(
    file,
    JSON.stringify({ ...auth, sessionId: "wrong-session" }),
  );
  await assert.rejects(
    cli(process.execPath, [entry], {
      env: { ...env, M211_AUTHORIZATION: file },
    }),
    /match the saved, unexpired CLI session/,
  );
  await writeFile(file, JSON.stringify(auth));
  const authorized = await start({ M211_AUTHORIZATION: file });
  const state = await get(authorized.base);
  assert.equal(state.printingEnabled, true);
  assert.equal(state.printAuthorization.text, "SAMPLE-ONE");
  assert.equal(state.cutAuthorized, false);
  await authorized.stop();
});
