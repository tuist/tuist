import { host, Scroll, signal, Text, View } from "nsh";
import { Button, createNavStack, NavPage } from "nsh/base";

export const state = signal<any>({ items: null, ...host.params });
host.on("workspace", snapshot => state.set(snapshot));
export const command = (kind: string, name: string, input: unknown) =>
  host.call("workspace", { kind, name, input }).catch(() => null);
export type Route = { name: "session" } | { name: "inbox" } | { name: "conversation"; id: string } | { name: "customer"; record: any };
export const nav = createNavStack<Route>([]);
const submitting = signal(false);
const permitted = (kind: string, name: string) => !state().capabilities || state().capabilities[kind]?.includes(name);

export const openConversation = (id: string) =>
  host.call("workspace", { kind: "open", model: "support.conversation", id }).catch(() => null);

async function submit(record: any, retry = false) {
  if (submitting() || (!retry && state().can_retry)) return;
  submitting.set(true);
  try {
    if (retry) await host.call("workspace", { kind: "retry" });
    else await command("action", "support.conversation.update", {
      id: record.id, expected_revision: record.revision,
      values: { status: record.status === "open" ? "closed" : "open" },
    });
  } catch {
    // The host owns the pending identity and publishes recovery state.
  } finally {
    submitting.set(false);
  }
}

export function Recovery() {
  return <View class="gap-4">
    {state().error ? <Text class="text-destructive">{state().error}</Text> : null}
    {state().warning ? <Text class="text-muted-foreground">{state().warning}</Text> : null}
    {state().can_retry && !submitting() ? <Action label="Retry submission" press={() => submit(null, true)} /> : null}
    {submitting() ? <Text class="text-muted-foreground">Submission pending…</Text> : null}
  </View>;
}

export function Action(props: { label: string; press: () => void }) {
  return <Button onPress={props.press} class="rounded-lg bg-primary px-4 py-3">
    <Text class="text-primary-foreground">{props.label}</Text>
  </Button>;
}

function Customer(props: { record: any }) {
  return <NavPage title={props.record.name}><Scroll class="flex-1 bg-background"><View class="p-4 gap-4">
    <Text class="text-sm text-muted-foreground">ACCOUNT MANAGEMENT · READ ONLY</Text>
    <Text class="text-2xl font-semibold text-foreground">{props.record.name}</Text>
    <Text class="text-muted-foreground">{props.record.email ?? "No email"}</Text>
    <Text class="text-muted-foreground">Status: {props.record.status} · revision {props.record.revision}</Text>
    <Text class="text-sm text-muted-foreground">Loaded from the linked customer record. Support cannot edit this customer.</Text>
  </View></Scroll></NavPage>;
}

function Conversation(props: { id: string }) {
  const record = () => state().record?.id === props.id ? state().record :
    (state().items ?? []).find((item: any) => item.id === props.id);
  return <NavPage title={record()?.subject ?? "Conversation"} headerBackTitle="Conversation">
    <Scroll class="flex-1 bg-background"><View class="p-4 gap-4">
      <Recovery />
      {record() ? <View class="gap-4">
        <Text class="text-2xl font-semibold text-foreground">{record().subject}</Text>
        <Text class="text-muted-foreground">Status: {record().status} · revision {record().revision}</Text>
        <Text class="text-sm text-muted-foreground">LINKED CUSTOMER</Text>
        {record().customer && permitted("queries", "accounts.customer.get") ? <Action label="View customer details" press={async () => {
          const result: any = await command("query", "accounts.customer.get", { id: record().customer });
          if (result?.record) nav.push({ name: "customer", record: result.record });
        }} /> : <Text class="text-muted-foreground">{record().customer ? "Customer details unavailable" : "No customer linked"}</Text>}
        {permitted("actions", "support.conversation.update") && !state().can_retry && !submitting() ?
          <Action label={record().status === "open" ? "Close conversation" : "Reopen conversation"}
            press={() => submit(record())} /> : null}
      </View> : <Text class="text-muted-foreground">Conversation unavailable. Reload the inbox.</Text>}
      <Action label="Refresh conversation" press={() => openConversation(props.id)} />
    </View></Scroll>
  </NavPage>;
}

function Inbox() {
  if (state().items === null && !state().error) command("query", "support.conversation.list", {});
  return <NavPage title="Support inbox" headerBackTitle="Inbox"><Scroll class="flex-1 bg-background"><View class="p-4 gap-4">
    <Text class="text-sm text-muted-foreground">Local workspace preview · fixture data</Text>
    <Recovery />
    {state().items === null ? <Text class="text-muted-foreground">Loading conversations…</Text> : null}
    {state().items?.length === 0 ? <Text class="text-muted-foreground">No conversations yet.</Text> : null}
    {(state().items ?? []).map((record: any) => <Button accessibilityLabel={`Open ${record.subject}`}
      onPress={() => nav.push({ name: "conversation", id: record.id })} class="p-4 gap-2 rounded-lg border border-border">
      <Text class="text-lg font-semibold text-foreground">{record.subject}</Text>
      <Text class="text-muted-foreground">{record.status} · {record.customer ? "Customer linked" : "No customer linked"}</Text>
      <Text class="text-sm text-muted-foreground">revision {record.revision} ›</Text>
    </Button>)}
    <Action label="Refresh inbox" press={() => command("query", "support.conversation.list", {})} />
  </View></Scroll></NavPage>;
}

export function SupportPage(props: { route: Route }) {
  return props.route.name === "conversation" ? <Conversation id={props.route.id} /> :
    props.route.name === "customer" ? <Customer record={props.route.record} /> : <Inbox />;
}
