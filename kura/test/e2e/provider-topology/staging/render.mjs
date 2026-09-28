import fs from "node:fs";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";

const [image, out, nodeA, nodeB, nodeC] = process.argv.slice(2);
if (!nodeC) throw Error("usage: node render.mjs IMAGE OUTPUT NODE_A NODE_B NODE_C");
fs.mkdirSync(out, { recursive: true, mode: 0o700 });
const prefix = "kura-topology-e2e";
const nodes = ["a", "b", "c", "d"];
const host = (id, privatePath = false) => `${prefix}-${privatePath ? "private-" : ""}${id}.kura.svc.cluster.local`;
const url = (id, privatePath = false) => `https://${host(id, privatePath)}:7443`;
const openssl = (...args) => execFileSync("openssl", args, { stdio: "ignore" });
openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", `${out}/ca.key`, "-out", `${out}/ca.pem`, "-days", "2", "-subj", "/CN=kura-topology-staging-test-ca");
openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", `${out}/peer.key`, "-out", `${out}/peer.csr`, "-subj", "/CN=kura-topology-staging-test-peer");
fs.writeFileSync(`${out}/extensions`, "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=" + nodes.flatMap(id => ["DNS:" + host(id), "DNS:" + host(id, true)]).join(",") + "\n");
openssl("x509", "-req", "-in", `${out}/peer.csr`, "-CA", `${out}/ca.pem`, "-CAkey", `${out}/ca.key`, "-CAcreateserial", "-out", `${out}/peer.pem`, "-days", "2", "-extfile", `${out}/extensions`);
const secret = crypto.randomBytes(32).toString("hex");
const encode = obj => Buffer.from(JSON.stringify(obj)).toString("base64url");
const unsigned = encode({ alg: "HS256", typ: "JWT" }) + "." + encode({ sub: "staging-e2e", type: "user", scopes: ["project_cache_write"], cache_grants: { project: { read: ["topology-staging-e2e/validation"], write: ["topology-staging-e2e/validation"] } }, exp: Math.floor(Date.now() / 1000) + 86400 });
const token = unsigned + "." + crypto.createHmac("sha256", secret).update(unsigned).digest("base64url");
const labels = { "tuist.dev/test": prefix };
const metadata = name => ({ name, namespace: "kura", labels });
const items = [{ apiVersion: "v1", kind: "Secret", metadata: metadata(prefix), type: "Opaque", stringData: {
  "ca.pem": fs.readFileSync(`${out}/ca.pem`, "utf8"),
  "peer.pem": fs.readFileSync(`${out}/peer.pem`, "utf8"),
  "peer.key": fs.readFileSync(`${out}/peer.key`, "utf8"),
  "jwt-secret": secret, "client-token": token,
} }];
for (const id of nodes) {
  const name = `${prefix}-${id}`;
  const selector = { ...labels, "tuist.dev/test-node": id };
  const nginx = `events {}
http {
  log_format audit escape=json '{"source":"$remote_addr","path":"$uri","status":$status,"bytes":$body_bytes_sent}';
  access_log /dev/stdout audit;
  client_max_body_size 64m;
  server {
    listen 8443 ssl;
    ssl_certificate /tls/peer.pem;
    ssl_certificate_key /tls/peer.key;
    ssl_client_certificate /tls/ca.pem;
    ssl_verify_client on;
    location / {
      proxy_pass https://127.0.0.1:7443;
      proxy_ssl_server_name on;
      proxy_ssl_name ${host(id, true)};
      proxy_ssl_trusted_certificate /tls/ca.pem;
      proxy_ssl_certificate /tls/peer.pem;
      proxy_ssl_certificate_key /tls/peer.key;
      proxy_ssl_verify on;
      proxy_http_version 1.1;
      proxy_set_header Connection "";
      proxy_request_buffering off;
      proxy_buffering off;
      proxy_read_timeout 90s;
    }
  }
}
`;
  items.push({ apiVersion: "v1", kind: "ConfigMap", metadata: metadata(name), data: { "nginx.conf": nginx } });
  for (const privatePath of [false, true]) items.push({ apiVersion: "v1", kind: "Service", metadata: metadata(`${prefix}-${privatePath ? "private-" : ""}${id}`), spec: {
    selector, publishNotReadyAddresses: true, ports: [{ name: "peer", port: 7443, targetPort: privatePath ? 7443 : 8443 }],
  } });
  const env = {
    KURA_PORT: "4000", KURA_INTERNAL_PORT: "7443", KURA_TENANT_ID: "topology-staging-e2e",
    KURA_REGION: id === "d" ? "a" : id, KURA_NODE_URL: url(id),
    KURA_PEERS: nodes.map(n => url(n)).join(","),
    KURA_PEER_TOPOLOGY: JSON.stringify({ provider: id === "c" ? "test-provider-b" : "test-provider-a", private_network: id === "c" ? "test-domain-b" : "test-domain-a", private_url: url(id, true) }),
    KURA_INTERNAL_TLS_CA_CERT_PATH: "/tls/ca.pem", KURA_INTERNAL_TLS_CERT_PATH: "/tls/peer.pem", KURA_INTERNAL_TLS_KEY_PATH: "/tls/peer.key",
    KURA_DATA_DIR: "/data", KURA_TMP_DIR: "/data/tmp", KURA_TMP_DIR_MAX_BYTES: "134217728", KURA_CAS_CAPACITY_BYTES: "2684354560",
    KURA_MEMORY_LIMIT_BYTES: "1073741824", KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND: "10485760",
    KURA_SYNC_LONG_POLL_SECS: "2", KURA_OTEL_SERVICE_NAME: "kura-topology-staging-e2e", KURA_OTEL_DEPLOYMENT_ENVIRONMENT: "staging",
  };
  items.push({ apiVersion: "apps/v1", kind: "Deployment", metadata: metadata(name), spec: { replicas: 1, strategy: { type: "Recreate" }, selector: { matchLabels: selector }, template: { metadata: { labels: selector }, spec: {
    automountServiceAccountToken: false,
    nodeSelector: { "kubernetes.io/hostname": id === "b" ? nodeB : id === "c" ? nodeC : nodeA },
    tolerations: [{ key: "tuist.dev/kura-cache", operator: "Exists", effect: "NoSchedule" }, { key: "tuist.dev/runner-cache", operator: "Exists", effect: "NoSchedule" }],
    terminationGracePeriodSeconds: 10,
    containers: [
      { name: "kura", image, env: [...Object.entries(env).map(([name, value]) => ({ name, value })), { name: "KURA_AUTH_JWT_SECRET", valueFrom: { secretKeyRef: { name: prefix, key: "jwt-secret" } } }],
        resources: { requests: { cpu: "100m", memory: "512Mi" }, limits: { cpu: "2", memory: "1536Mi" } },
        readinessProbe: { httpGet: { path: "/ready", port: 4000 }, periodSeconds: 3, failureThreshold: 60 },
        volumeMounts: [{ name: "data", mountPath: "/data" }, { name: "tls", mountPath: "/tls", readOnly: true }] },
      { name: "canonical-audit", image: "public.ecr.aws/docker/library/nginx:stable-alpine", resources: { requests: { cpu: "20m", memory: "32Mi" }, limits: { cpu: "500m", memory: "96Mi" } }, volumeMounts: [{ name: "nginx", mountPath: "/etc/nginx/nginx.conf", subPath: "nginx.conf" }, { name: "tls", mountPath: "/tls", readOnly: true }] },
    ], volumes: [{ name: "data", emptyDir: { sizeLimit: "3Gi" } }, { name: "tls", secret: { secretName: prefix } }, { name: "nginx", configMap: { name } }],
  } } } });
}
for (const id of nodes) items.push({ apiVersion: "networking.k8s.io/v1", kind: "NetworkPolicy", metadata: metadata(`${prefix}-${id}`), spec: { podSelector: { matchLabels: { ...labels, "tuist.dev/test-node": id } }, policyTypes: ["Ingress"], ingress: [{ from: [{ podSelector: { matchLabels: labels } }], ports: [4000, 7443, 8443].map(port => ({ protocol: "TCP", port })) }] } });
fs.writeFileSync(`${out}/manifest.json`, JSON.stringify({ apiVersion: "v1", kind: "List", items }, null, 2), { mode: 0o600 });
console.log(`Rendered ${items.length} isolated resources to ${out}/manifest.json`);
