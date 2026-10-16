export const vint = (value) => {
  const out = [];
  do {
    let b = value & 127;
    value = Math.floor(value / 128);
    if (value) b |= 128;
    out.push(b);
  } while (value);
  return Buffer.from(out);
};
export const field = (id, data) => {
  data = Buffer.from(data);
  return Buffer.concat([vint(id * 8 + 2), vint(data.length), data]);
};
export const number = (id, value) => Buffer.concat([vint(id * 8), vint(value)]);
export const frame = (body) => {
  const header = Buffer.alloc(5);
  header.writeUInt32BE(body.length, 1);
  return Buffer.concat([header, body]);
};
export function request(session, path, method = "GET", body, grpc = false) {
  return new Promise((resolve, reject) => {
    const stream = session.request({
      ":path": path,
      ":method": method,
      ...(grpc
        ? { "content-type": "application/grpc", te: "trailers" }
        : body
          ? { "content-type": "application/json" }
          : {}),
    });
    stream.setTimeout(30_000, () =>
      stream.destroy(new Error("request deadline exceeded")),
    );
    let headers = {},
      trailers = {},
      chunks = [];
    stream.on("response", (value) => (headers = value));
    stream.on("trailers", (value) => (trailers = value));
    stream.on("data", (chunk) => chunks.push(chunk));
    stream.on("error", reject);
    stream.on("end", () =>
      resolve({
        status: headers[":status"],
        grpc: trailers["grpc-status"] ?? headers["grpc-status"],
        body: Buffer.concat(chunks),
      }),
    );
    stream.end(body);
  });
}
