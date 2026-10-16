import fs from "node:fs";
import https from "node:https";

// Terminate fixture mTLS so the test can distinguish body traffic from status
// probes. Only the regional private network can reach this listener.
const tls = {
  ca: fs.readFileSync("/certs/ca.pem"),
  cert: fs.readFileSync("/certs/peer.pem"),
  key: fs.readFileSync("/certs/peer.key"),
};
https.createServer({ ...tls, requestCert: true, rejectUnauthorized: true }, (req, res) => {
  const upstream = https.request({
    ...tls,
    hostname: process.env.KURA_UPSTREAM,
    port: 7443,
    path: req.url,
    method: req.method,
    headers: req.headers,
  }, (response) => {
    res.writeHead(response.statusCode, response.headers);
    response.pipe(res);
    response.on("end", () => console.log(`${response.statusCode} ${req.method} ${req.url}`));
  });
  upstream.on("error", (error) => {
    console.error(error.message);
    res.destroy(error);
  });
  req.on("aborted", () => upstream.destroy());
  req.pipe(upstream);
}).listen(7443, "0.0.0.0");
