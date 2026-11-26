// Presentation only. The host routes declared operations through the Rust core;
// this source has neither credentials, networking, nor a persistence implementation.
import { host, mount, Scroll, signal, Text, View } from "nsh";
import { AlertDialog, Button as Pressable, createNavStack, Input, NavPage, NavStack } from "nsh/base";

const state = signal<any>({ items: null, ...host.params });
host.on("workspace", snapshot => state.set(snapshot));
const command = (kind: string, name?: string, input?: unknown) => host.call("workspace", { kind, name, input }).catch(() => null);
const permitted = (kind: string, name: string) => !state().capabilities || state().capabilities[kind]?.includes(name);
// Page history is disposable presentation state, never a source of records or permissions.
type Route = { name: "list" } | { name: "create" } | { name: "detail"; id: string };
const nav = createNavStack<Route>([host.params.entry?.model === "accounts.customer" ?
  { name: "detail", id: host.params.entry.id } : { name: "list" }]);
const statuses = ["lead", "active", "paused"];

function Button(props: { label: string; press: () => void }) {
  return <Pressable onPress={props.press} class="rounded-lg bg-primary px-4 py-3">
    <Text class="text-primary-foreground">{props.label}</Text>
  </Pressable>;
}

function StatusChoice(props: { value: string; change: (value: string) => void }) {
  return <Button label={`Change status (${props.value})`} press={async () => {
    const { action } = await AlertDialog.show({
      title: "Customer status", presentation: "actionSheet",
      actions: [...statuses.map(id => ({ id, label: id })), { id: "cancel", label: "Cancel", role: "cancel" }],
    });
    if (statuses.includes(action)) props.change(action);
  }} />;
}

function CreateCustomer() {
  const name = signal("");
  const email = signal("");
  const status = signal("lead");
  return <NavPage title="New customer"><Scroll class="flex-1 bg-background"><View class="p-4 gap-4">
    {state().error ? <Text class="text-destructive">{state().error}</Text> : null}
    <Text class="text-muted-foreground">CUSTOMER DETAILS</Text>
    <Input accessibilityLabel="Customer name" placeholder="Customer name (required)" value={name()} onChange={event => name.set(event.value)} class="border border-border p-3 rounded-lg text-foreground" />
    <Input accessibilityLabel="Customer email" placeholder="Email (optional)" value={email()} onChange={event => email.set(event.value)} autoCapitalize="none" keyboardType="email-address" class="border border-border p-3 rounded-lg text-foreground" />
    <Text class="text-muted-foreground">Initial status: {status()}</Text>
    <StatusChoice value={status()} change={value => status.set(value)} />
    <Button label="Create customer" press={async () => {
      const saved = await command("action", "accounts.customer.create", {
        values: { name: name(), email: email().trim() || null, status: status() },
      });
      if (saved) nav.popToRoot();
    }} />
  </View></Scroll></NavPage>;
}

function CustomerDetail(props: { id: string }) {
  const customer = () => state().record?.id === props.id ? state().record :
    (state().items ?? []).find((item: any) => item.id === props.id);
  return <NavPage title={customer()?.name ?? "Customer"}><Scroll class="flex-1 bg-background"><View class="p-4 gap-4">
    {state().error ? <Text class="text-destructive">{state().error}</Text> : null}
    {customer() ? <View class="gap-4">
      <Text class="text-2xl font-semibold text-foreground">{customer().name}</Text>
      <Text class="text-muted-foreground">{customer().email ?? "No email"}</Text>
      <Text class="text-muted-foreground">Status: {customer().status} · revision {customer().revision}</Text>
      {permitted("actions", "accounts.customer.update") ? <StatusChoice value={customer().status} change={status => command("action", "accounts.customer.update", {
        id: customer().id, expected_revision: customer().revision, values: { status },
      })} /> : null}
    </View> : <Text class="text-muted-foreground">Customer unavailable. Reload the list.</Text>}
    {host.params.entry ? <Button label="Refresh customer" press={() => host.call("workspace", {
      kind: "open", model: "accounts.customer", id: props.id,
    }).catch(() => null)} /> : null}
  </View></Scroll></NavPage>;
}

function Customers() {
  if (state().items === null && !state().error) command("query", "accounts.customer.list", {});
  return <NavPage title="Customers" headerBackTitle="Customers"><Scroll class="flex-1 bg-background"><View class="p-4 gap-4">
    <Text class="text-sm text-muted-foreground">Local workspace preview · fixture data</Text>
    {state().error ? <View class="gap-2">
      <Text class="text-destructive">{state().error}</Text>
      <Button label="Reload customers" press={() => command("query", "accounts.customer.list", {})} />
      {state().can_retry ? <Button label="Retry submission" press={() => command("retry")} /> : null}
    </View> : null}
    {state().items === null ? <Text class="text-muted-foreground">Loading customers…</Text> : null}
    {state().items?.length === 0 ? <Text class="text-muted-foreground">No customers yet. Add the first one.</Text> : null}
    {(state().items ?? []).map((customer: any) => <Pressable accessibilityLabel={`Open ${customer.name}`} onPress={() => nav.push({ name: "detail", id: customer.id })} class="gap-2 p-4 rounded-lg border border-border">
      <Text class="text-lg font-semibold text-foreground">{customer.name}</Text>
      <Text class="text-muted-foreground">{customer.email ?? "No email"}</Text>
      <View class="flex-row justify-between"><Text class="text-sm text-muted-foreground">{customer.status} · revision {customer.revision}</Text><Text class="text-muted-foreground">›</Text></View>
    </Pressable>)}
    {permitted("actions", "accounts.customer.create") ? <Button label="Add customer" press={() => nav.push({ name: "create" })} /> : null}
    <Button label="Refresh list" press={() => command("query", "accounts.customer.list", {})} />
  </View></Scroll></NavPage>;
}

function App() {
  return <NavStack state={nav} class="flex-1">{route => route.name === "create" ? <CreateCustomer /> :
    route.name === "detail" ? <CustomerDetail id={route.id} /> : <Customers />}</NavStack>;
}

mount(App);
