import { expect, open, test } from "nsh/test";

test("session entry uses the canonical customer and does not offer edits without a grant", async () => {
  const id = "11111111-1111-4111-8111-111111111111";
  const app = await open("./App.tsx", { host: { params: {
    entry: { model: "accounts.customer", id },
    record: { id, name: "Canonical customer", email: null, status: "paused", revision: 9 },
    items: [{ id, name: "Old list row", email: null, status: "active", revision: 8 }],
    capabilities: { queries: ["accounts.customer.get"], actions: [] },
  }, handlers: { workspace: null } } });
  expect(app.texts()).toContain("Canonical customer");
  expect(app.texts()).toContain("Status: paused · revision 9");
  expect(app.texts()).not.toContain("Change status (paused)");
  expect(app.texts()).not.toContain("Old list row");
  expect(app.host.calls()).toEqual([]);
  await app.press("Refresh customer");
  expect(app.host.calls()[0].data).toEqual({ kind: "open", model: "accounts.customer", id });
});

test("customers request data only through the bounded host", async () => {
  const app = await open("./App.tsx", { host: { handlers: { workspace: null } } });
  expect(app.texts()).toContain("Local workspace preview · fixture data");
  expect(app.texts()).toContain("Loading customers…");
  expect(app.host.calls()).toEqual([{ name: "workspace", data: { kind: "query", name: "accounts.customer.list", input: {} } }]);
  await app.press("Add customer");
  await app.press("Create customer");
  expect(app.host.calls().length).toBe(2);
  expect(app.host.calls()[1]).toEqual({ name: "workspace", data: { kind: "action", name: "accounts.customer.create", input: { values: { name: "", email: null, status: "lead" } } } });
});

test("customer rows and revision-aware status edits come from the core snapshot", async () => {
  const app = await open("./App.tsx", { host: {
    params: { items: [{ id: "11111111-1111-4111-8111-111111111111", revision: 7, name: "Fixture from core", email: null, status: "lead" }] },
    handlers: { workspace: null },
  } });
  expect(app.texts()).toContain("Fixture from core");
  expect(app.host.calls()).toEqual([]);
  await app.press("Open Fixture from core");
  expect(app.texts()).toContain("Status: lead · revision 7");
  expect(app.host.calls()).toEqual([]);
  await app.back();
  expect(app.texts()).toContain("Local workspace preview · fixture data");
  await app.press("Open Fixture from core");
  app.onDialog(() => null);
  await app.press("Change status (lead)");
  expect(app.host.calls()).toEqual([]);
  app.onDialog(() => "active");
  await app.press("Change status (lead)");
  expect(app.host.calls()).toEqual([{ name: "workspace", data: { kind: "action", name: "accounts.customer.update", input: {
    id: "11111111-1111-4111-8111-111111111111", expected_revision: 7, values: { status: "active" },
  } } }]);
  await app.host.send("workspace", { items: [{ id: "11111111-1111-4111-8111-111111111111", revision: 8, name: "Fixture from core", email: null, status: "active" }] });
  expect(app.texts()).toContain("Status: active · revision 8");
  await app.press("Change status (active)");
  expect(app.host.calls()[1].data.input.expected_revision).toBe(8);
});

test("create form submits entered values, not fixture rows", async () => {
  const app = await open("./App.tsx", { host: { params: { items: [] }, handlers: { workspace: null } } });
  await app.press("Add customer");
  await app.type("Customer name", "New studio");
  await app.type("Customer email", "hello@studio.example");
  app.onDialog(() => "paused");
  await app.press("Change status (lead)");
  await app.press("Create customer");
  expect(app.host.calls()).toEqual([{ name: "workspace", data: { kind: "action", name: "accounts.customer.create", input: {
    values: { name: "New studio", email: "hello@studio.example", status: "paused" },
  } } }]);
  await app.host.send("workspace", { items: [], error: "Check the record fields and values." });
  expect(app.texts()).toContain("Check the record fields and values.");
  await app.press("Create customer");
  expect(app.host.calls()[1].data.input.values).toEqual({ name: "New studio", email: "hello@studio.example", status: "paused" });
});

test("safe validation and retry states remain actionable", async () => {
  const app = await open("./App.tsx", { host: {
    params: { items: [], error: "Check the customer name, email and status.", can_retry: true }, handlers: { workspace: null },
  } });
  expect(app.texts()).toContain("Check the customer name, email and status.");
  expect(app.host.calls()).toEqual([]);
  await app.press("Retry submission");
  expect(app.host.calls()).toEqual([{ name: "workspace", data: { kind: "retry" } }]);
});
