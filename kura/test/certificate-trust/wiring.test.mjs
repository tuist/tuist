// Bounded source inventory from #14511, not a Rust alias/macro/data-flow proof.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { X509Certificate } from "node:crypto";
import { fileURLToPath } from "node:url";

const kura = fileURLToPath(new URL("../../", import.meta.url));
const read = name => fs.readFileSync(path.join(kura, name), "utf8");
const foundation = "../infra/certificate-trust/";

test("embedded policy and real fixtures match the independent foundation", () => {
  const policy = JSON.parse(read(foundation + "policy.json"));
  const source = read("src/certificate_trust.rs");
  assert.ok(source.includes(`pub const POLICY_ID: &str = "${policy.id}";`));
  const hashes = [...source.matchAll(/"([a-f0-9]{64})"/g)].map(match => match[1]);
  assert.equal(policy.key_count, 12);
  assert.deepEqual(hashes.sort(), [...policy.distrusted_spki_sha256].sort());
  for (const [hash, der] of Object.entries(policy.spki_der_base64)) {
    assert.equal(createHash("sha256").update(Buffer.from(der, "base64")).digest("hex"), hash);
  }
  const found = new Set();
  for (const name of ["issuer-roots.pem", "distrusted-intermediates.pem"]) {
    const pem = read("test/certificate-trust/" + name);
    assert.equal(pem, read(foundation + "controls/" + name));
    for (const [certificate] of pem.matchAll(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g)) {
      const spki = new X509Certificate(certificate).publicKey.export({ type: "spki", format: "der" });
      found.add(createHash("sha256").update(spki).digest("hex"));
    }
  }
  assert.deepEqual([...found].sort(), hashes);
});

test("production factories retain protected backends and qualified native versions", () => {
  const expected = { "certificate_trust.rs": 1, "peer_tls.rs": 1, "serving_authority.rs": 1, "telemetry.rs": 1 };
  const root = path.join(kura, "src");
  for (const name of fs.readdirSync(root, { recursive: true })) {
    if (!name.endsWith(".rs") || name.endsWith("_tests.rs") || ["tests.rs", "test_support.rs"].includes(path.basename(name))) continue;
    let source = read("src/" + name);
    // Test keys can precede production factories. Exclude only the named module,
    // retaining any production code after it. Ambiguous literals fail closed.
    source = source.replace(/^#\[cfg\(test\)\]\s*\nmod tests\s*\{[\s\S]*?^}\s*$/m, "");
    assert.doesNotMatch(source, /\b(?:Client|ClientBuilder)\s+as\s+/, `review aliased client: ${name}`);
    if (name !== "certificate_trust.rs") assert.ok(!source.includes("ClientConfig::builder"), `unprotected Rustls: ${name}`);
    assert.equal([...source.matchAll(/\b(?:Client|ClientBuilder)::(?:new|builder|default)\(/g)].length, expected[name] ?? 0, `constructor inventory: ${name}`);
    assert.equal(source.split(".tls_backend_preconfigured(").length - 1, expected[name] ?? 0, `backend inventory: ${name}`);
    for (const forbidden of ["danger_accept_invalid_", "tls_backend_rustls(", "tls_backend_native(", "use_preconfigured_tls(", ".tls_certs_only(", ".tls_certs_merge(", ".add_root_certificate(", ".identity(", ".http1_only(", ".http2_prior_knowledge(", "reqwest::get(", "reqwest::blocking::get(", "ClientTlsConfig", ".tls_config(", "with_native_roots(", "hyper_rustls::", "TlsConnector"]) {
      if (forbidden === ".identity(" && !expected[name] && !source.includes("client_builder(")) continue;
      assert.ok(!source.includes(forbidden), `TLS bypass or ignored setting ${forbidden}: ${name}`);
    }
  }
  for (const [name, required] of Object.entries({
    "auth/tuist.rs": ["certificate_trust::client_builder()?", "certificate_trust::failure_category(error)"],
    "control_plane_http.rs": ["certificate_trust::client_builder()?"],
    "enrollment.rs": ["certificate_trust::client_builder()?"],
    "registration.rs": ["certificate_trust::client_builder()"],
    "reapi/asset/http.rs": ["certificate_trust::client_builder()", ".no_proxy()", "reqwest::redirect::Policy::none()"],
    "peer_tls.rs": ["certificate_trust::config(", "Roots::Explicit(", "Roots::Native(", "certificate_trust::client_auth_verifier(", "self.identity.load_full()"],
    "telemetry.rs": ["transport: Some(", "sentry_http_client_builder(options)", "ReqwestHttpTransport::with_client", "certificate_trust::native_config()?"],
    "certificate_trust_apple.rs": ["set_trust_anchor_certificates_only(false)", "set_trust_ocsp_response", "set_trust_verify_date", "trust.evaluate_with_error()", ".certificate_at_index(index)"],
  })) {
    for (const token of required) assert.ok(read("src/" + name).includes(token), `missing ${token}: ${name}`);
  }
  const lock = read("Cargo.lock");
  for (const [name, version] of Object.entries({ reqwest: "0.13.2", rustls: "0.23.46", "rustls-platform-verifier": "0.6.2", "rustls-native-certs": "0.8.3", "rustls-webpki": "0.103.16", "security-framework": "3.7.0" })) {
    assert.ok(lock.includes(`name = "${name}"\nversion = "${version}"`), `requalify native parity: ${name}`);
  }
  const otlp = read("Cargo.toml").match(/^opentelemetry-otlp\s*=.*$/m)?.[0];
  assert.ok(otlp && !otlp.includes('"tls'), "OTLP gRPC TLS requires an explicitly protected channel");
});
