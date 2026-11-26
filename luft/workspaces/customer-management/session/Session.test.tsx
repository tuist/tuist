import { expect, open, test } from "nsh/test";

const conversation = { id: "33333333-3333-4333-8333-333333333333", subject: "Cache setup", status: "open", revision: 4, customer: "11111111-1111-4111-8111-111111111111" };
const customer = { id: conversation.customer, name: "Northstar Labs", email: "ops@northstar.example", status: "active", revision: 2 };
const historical = "Historical fixture: original summary — Cache setup, open, revision 1.";
const reference = { kind: "open", model: "support.conversation", id: conversation.id };

test("session opens shared record and canonical customer, native Back preserves historical text and reopens fresh", async () => {
  let current = conversation;
  let account = customer;
  const app = await open("./App.tsx", { host: {
    params: { items: [conversation] },
    handlers: { workspace: (data: any) => ({ record: data.kind === "open" ? current : account }) },
  } });
  expect(app.texts()).toContain("Support handoff");
  expect(app.texts()).toContain(historical);
  expect(app.texts()).toContain("Local-only fixture harness · not a live session");
  expect(app.host.calls()).toEqual([]);
  await app.press("Open support record");
  await app.host.send("workspace", { items: [conversation], record: current });
  expect(app.host.calls()).toEqual([{ name: "workspace", data: reference }]);
  expect(app.texts()).toContain("Status: open · revision 4");
  await app.press("View customer details");
  expect(app.host.calls()[1].data).toEqual({ kind: "query", name: "accounts.customer.get", input: { id: customer.id } });
  expect(app.texts()).toContain("ACCOUNT MANAGEMENT · READ ONLY");
  expect(app.texts()).toContain("Northstar Labs");
  await app.back();
  expect(app.texts()).toContain("Status: open · revision 4");
  account = { ...customer, revision: 3 };
  await app.press("View customer details");
  expect(app.texts()).toContain("Status: active · revision 3");
  expect(app.host.calls()[2].data).toEqual(app.host.calls()[1].data);
  await app.back();
  await app.press("Close conversation");
  expect(app.host.calls()[3].data).toEqual({ kind: "action", name: "support.conversation.update", input: {
    id: conversation.id, expected_revision: 4, values: { status: "closed" },
  } });
  current = { ...conversation, status: "closed", revision: 5 };
  await app.host.send("workspace", { items: [conversation], record: current });
  expect(app.texts()).toContain("Status: closed · revision 5");
  await app.back();
  expect(app.texts()).toContain(historical);
  current = { ...current, revision: 6 };
  await app.press("Open support record");
  await app.host.send("workspace", { items: [conversation], record: current });
  expect(app.host.calls()[4].data).toEqual(reference);
  expect(app.texts()).toContain("Status: closed · revision 6");
  await app.press("Refresh conversation");
  expect(app.host.calls()[5].data).toEqual(reference);
  current = { ...current, revision: 7 };
  await app.host.send("workspace", { items: [conversation], record: current });
  expect(app.texts()).toContain("Status: closed · revision 7");
  await app.press("Reopen conversation");
  expect(app.host.calls()[6].data.input).toEqual({ id: conversation.id, expected_revision: 7, values: { status: "open" } });
  await app.back();
  expect(app.texts()).toContain(historical);
});

test("failed reference open stays on session and browsing fallback uses the shared inbox", async () => {
  const app = await open("./App.tsx", { host: {
    params: { items: [conversation] }, handlers: { workspace: null },
  } });
  await app.press("Open support record");
  await app.host.send("workspace", { items: [conversation], error: "Record not found. Reload the list." });
  expect(app.texts()).toContain("Record not found. Reload the list.");
  expect(app.texts()).toContain(historical);
  expect(app.texts()).toContain("Open support record");
  expect(app.texts()).not.toContain("Close conversation");
  await app.press("Open support inbox");
  expect(app.texts()).toContain("Local workspace preview · fixture data");
  await app.press("Open Cache setup");
  expect(app.texts()).toContain("Status: open · revision 4");
  await app.back();
  await app.back();
  expect(app.texts()).toContain(historical);
});

test("rejected reference open never navigates", async () => {
  const app = await open("./App.tsx", { host: { handlers: { workspace: () => { throw new Error("Unavailable"); } } } });
  await app.press("Open support record");
  expect(app.texts()).toContain(historical);
  expect(app.texts()).toContain("Open support inbox");
});
