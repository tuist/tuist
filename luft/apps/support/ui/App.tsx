import { host, mount } from "nsh";
import { NavStack } from "nsh/base";
import { nav, SupportPage } from "./Support";

nav.push(host.params.entry?.model === "support.conversation" ?
  { name: "conversation", id: host.params.entry.id } : { name: "inbox" });
function App() {
  return <NavStack state={nav} class="flex-1">{route => <SupportPage route={route} />}</NavStack>;
}
mount(App);
