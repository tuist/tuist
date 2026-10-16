import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: Object.fromEntries(
    [
      "context",
      "namespace",
      "node",
      "output",
      "source-image",
      "warm-image",
      "candidate-image",
    ].map((name) => [name, { type: "string" }]),
  ),
});
assert(
  values.output && path.isAbsolute(values.output),
  "absolute matrix output required",
);
assert.equal(values.context, "tuist-k8s-staging.taild6d7bb.ts.net");
assert.equal(values.namespace, "kura-spec98");
assert(!fs.existsSync(values.output), "use a new matrix output directory");
fs.mkdirSync(values.output, { recursive: true });
const results = [];
for (let repetition = 1; repetition <= 2; repetition++) {
  for (const scenario of ["fresh", "fragmented"]) {
    const output = `${values.output}/${scenario}-${repetition}`;
    const args = Object.entries({
      ...values,
      output,
      profile: "production",
      scenario,
      expect: "pass",
    }).flatMap(([key, value]) => [`--${key}`, value]);
    const child = spawn(
      process.execPath,
      [new URL("staging.mjs", import.meta.url).pathname, ...args],
      { stdio: "inherit" },
    );
    const interrupt = () => child.kill("SIGINT");
    process.once("SIGINT", interrupt);
    process.once("SIGTERM", interrupt);
    const code = await new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("exit", resolve);
    });
    process.removeListener("SIGINT", interrupt);
    process.removeListener("SIGTERM", interrupt);
    results.push({ scenario, repetition, output, exitCode: code });
    fs.writeFileSync(
      `${values.output}/matrix.json`,
      JSON.stringify(results, null, 2),
    );
    if (code !== 0) process.exit(1);
  }
}
console.log(JSON.stringify({ qualifiedRuntimeMatrix: true, results }));
