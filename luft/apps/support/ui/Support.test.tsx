import { expect, open, test } from "nsh/test";

const conversation = { id: "33333333-3333-4333-8333-333333333333", subject: "Cache setup", status: "open", revision: 4, customer: "11111111-1111-4111-8111-111111111111" };
const customer = { id: conversation.customer, name: "Northstar Labs", email: "ops@northstar.example", status: "active", revision: 2 };

test("session entry opens current record directly and independent grants control customer and write affordances", async () => {
  const app = await open("./App.tsx", { host: { params: {
    entry: { model: "support.conversation", id: conversation.id }, record: conversation,
    capabilities: { queries: ["support.conversation.get"], actions: [] },
  }, handlers: { workspace: null } } });
  expect(app.texts()).toContain("Status: open · revision 4");
  expect(app.texts()).toContain("Customer details unavailable");
  expect(app.texts()).not.toContain("View customer details");
  expect(app.texts()).not.toContain("Close conversation");
  expect(app.host.calls()).toEqual([]);
  await app.host.send("workspace", { record: conversation, capabilities: {
    queries: ["support.conversation.get", "accounts.customer.get"], actions: ["support.conversation.update"],
  } });
  expect(app.texts()).toContain("View customer details");
  expect(app.texts()).toContain("Close conversation");
  await app.press("Refresh conversation");
  expect(app.host.calls()[0].data).toEqual({ kind: "open", model: "support.conversation", id: conversation.id });
});

test("conversation reference opens canonical customer details and returns through native history", async () => {
  const app = await open("./App.tsx", { host: {
    params: { items: [conversation] }, handlers: { workspace: { record: customer } },
  } });
  await app.press("Open Cache setup");
  expect(app.texts()).toContain("Status: open · revision 4");
  expect(app.host.calls()).toEqual([]);
  await app.press("View customer details");
  expect(app.host.calls()).toEqual([{ name: "workspace", data: { kind: "query", name: "accounts.customer.get", input: { id: conversation.customer } } }]);
  expect(app.texts()).toContain("Northstar Labs");
  expect(app.texts()).toContain("ops@northstar.example");
  expect(app.texts()).toContain("Status: active · revision 2");
  expect(app.texts()).toContain("ACCOUNT MANAGEMENT · READ ONLY");
  await app.back();
  expect(app.texts()).toContain("Status: open · revision 4");
  await app.back();
  expect(app.texts()).toContain("open · Customer linked");
  expect(app.host.calls().length).toBe(1);
});

test("unlinked conversations have no customer navigation and refreshes preserve the detail page", async () => {
  const unlinked = { ...conversation, customer: null };
  const app = await open("./App.tsx", { host: { params: { items: [unlinked] }, handlers: { workspace: null } } });
  await app.press("Open Cache setup");
  expect(app.texts()).toContain("No customer linked");
  expect(app.texts()).not.toContain("View customer details");
  await app.press("Close conversation");
  expect(app.host.calls()).toEqual([{ name: "workspace", data: { kind: "action", name: "support.conversation.update", input: {
    id: conversation.id, expected_revision: 4, values: { status: "closed" },
  } } }]);
  await app.host.send("workspace", { items: [{ ...unlinked, status: "closed", revision: 5 }] });
  expect(app.texts()).toContain("Status: closed · revision 5");
  await app.press("Reopen conversation");
  expect(app.host.calls()[1].data.input.expected_revision).toBe(5);
  await app.back();
  expect(app.texts()).toContain("closed · No customer linked");
});

test("a failed customer lookup leaves the conversation visible with a safe error", async () => {
  const app = await open("./App.tsx", { host: { params: { items: [conversation] }, handlers: { workspace: null } } });
  await app.press("Open Cache setup");
  await app.press("View customer details");
  await app.host.send("workspace", { items: [conversation], error: "Record not found. Reload the list." });
  expect(app.texts()).toContain("Record not found. Reload the list.");
  expect(app.texts()).toContain("Status: open · revision 4");
  expect(app.texts()).not.toContain("ACCOUNT MANAGEMENT · READ ONLY");
});

test("own-model record wins only for the matching route and refresh uses typed open", async () => {
  const app = await open("./App.tsx", { host: { params: {
    items: [conversation], record: { ...conversation, status: "closed", revision: 8 },
  }, handlers: { workspace: null } } });
  await app.press("Open Cache setup");
  expect(app.texts()).toContain("Status: closed · revision 8");
  await app.press("Refresh conversation");
  expect(app.host.calls()[0].data).toEqual({ kind: "open", model: "support.conversation", id: conversation.id });
  await app.host.send("workspace", { items: [conversation], record: { ...conversation, id: "other", revision: 99 } });
  expect(app.texts()).toContain("Status: open · revision 4");
});

test("warnings preserve saved results and unknown outcomes offer retry rather than a fresh mutation", async () => {
  const app = await open("./App.tsx", { host: { params: {
    items: [conversation], record: { ...conversation, status: "closed", revision: 5 },
    warning: "Saved, but refresh failed.",
  }, handlers: { workspace: null } } });
  await app.press("Open Cache setup");
  expect(app.texts()).toContain("Saved, but refresh failed.");
  expect(app.texts()).toContain("Status: closed · revision 5");
  await app.press("Reopen conversation");
  await app.host.send("workspace", {
    items: [conversation], record: { ...conversation, status: "closed", revision: 5 },
    can_retry: true, error: "Submission outcome unknown. Retry safely.",
  });
  expect(app.texts()).toContain("Submission outcome unknown. Retry safely.");
  expect(app.texts()).toContain("Retry submission");
  expect(app.texts()).not.toContain("Reopen conversation");
  expect(app.texts()).not.toContain("Close conversation");
  await app.press("Retry submission");
  expect(app.host.calls()[1].data).toEqual({ kind: "retry" });
  expect(app.host.calls().length).toBe(2);
  await app.host.send("workspace", { items: [conversation], record: { ...conversation, revision: 6 }, can_retry: false });
  expect(app.texts()).not.toContain("Retry submission");
  expect(app.texts()).toContain("Status: open · revision 6");
});

test("in-flight submissions suppress fresh mutations and duplicate retries", async () => {
  const pendingScreens: string[][] = [];
  const app = await open("./App.tsx", { host: {
    params: { items: [conversation] },
    handlers: { workspace: async () => {
      // Leave the bridge call outstanding while its pending UI is presented.
      await new Promise(resolve => setTimeout(resolve, 100));
      pendingScreens.push(app.texts());
      return null;
    } },
  } });
  await app.press("Open Cache setup");
  await app.press("Close conversation");
  expect(app.host.calls().length).toBe(1);
  await app.host.send("workspace", { items: [conversation], can_retry: true, error: "Outcome unknown." });
  await app.press("Retry submission");
  expect(app.host.calls()[1].data).toEqual({ kind: "retry" });
  expect(app.host.calls().length).toBe(2);
  expect(pendingScreens.length).toBe(2);
  for (const texts of pendingScreens) {
    expect(texts).toContain("Submission pending…");
    expect(texts).not.toContain("Close conversation");
    expect(texts).not.toContain("Reopen conversation");
    expect(texts).not.toContain("Retry submission");
  }
  await app.host.send("workspace", { items: [{ ...conversation, status: "closed", revision: 5 }], can_retry: false });
  expect(app.texts()).toContain("Reopen conversation");
});
