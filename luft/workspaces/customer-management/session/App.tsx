import { mount, Scroll, Text, View } from "nsh";
import { NavPage, NavStack } from "nsh/base";
import { Action, nav, openConversation, Recovery, SupportPage } from "../../../apps/support/ui/Support";

// Fixed trusted local harness reference; never interpreted from prose or selected by a model.
const reference: { model: "support.conversation"; id: string } = {
  model: "support.conversation", id: "33333333-3333-4333-8333-333333333333",
};
function Session() {
  return <NavPage title="Support handoff" headerBackTitle="Session">
    <Scroll class="flex-1 bg-background"><View class="p-4 gap-4">
      <Text class="text-2xl font-semibold text-foreground">Support handoff</Text>
      <Text class="text-sm text-muted-foreground">Local-only fixture harness · not a live session</Text>
      <Text class="text-foreground">Historical fixture: original summary — Cache setup, open, revision 1.</Text>
      <Recovery />
      <Action label="Open support record" press={async () => {
        const result: any = await openConversation(reference.id);
        if (result?.record) nav.push({ name: "conversation", id: reference.id });
      }} />
      <Action label="Open support inbox" press={() => nav.push({ name: "inbox" })} />
    </View></Scroll>
  </NavPage>;
}
nav.push({ name: "session" });
function App() {
  return <NavStack state={nav} class="flex-1">{route => route.name === "session" ?
    <Session /> : <SupportPage route={route} />}</NavStack>;
}
mount(App);
