// Spike: a card a model could write. Guild shows it in a conversation at a
// fixed size the Rust core chose, so it fills its frame and never measures
// itself. Its only way out is `host.call("reply", text)`, which puts the
// text in the conversation's composer for the person to send.
import { host, mount, Text, View } from "nsh";

const targets = [
  { name: "TuistKit", seconds: 412, hit: 0.31 },
  { name: "TuistCore", seconds: 188, hit: 0.74 },
  { name: "TuistSupport", seconds: 96, hit: 0.92 },
];

function Row(props: { name: string; seconds: number; hit: number }) {
  return (
    <View class="flex-row items-center gap-3">
      <Text class="w-28 text-sm text-foreground">{props.name}</Text>
      <View class="h-2 flex-1 rounded-full bg-muted">
        <View class="h-2 rounded-full bg-primary" style={{ width: `${Math.round(props.hit * 100)}%` }} />
      </View>
      <Text class="w-12 text-right text-sm text-muted-foreground">{props.seconds}s</Text>
    </View>
  );
}

function App() {
  return (
    <View class="flex-1 gap-3 rounded-xl border border-border bg-card p-4">
      <View class="gap-0.5">
        <Text class="text-base font-semibold text-card-foreground">Slowest targets this week</Text>
        <Text class="text-xs text-muted-foreground">Bar: cache hit rate · right: median build time</Text>
      </View>
      <View class="gap-2">
        {targets.map((target) => (
          <Row {...target} />
        ))}
      </View>
      <View class="flex-1" />
      <View
        role="button"
        onPress={() => {
          if (host.available()) void host.call("reply", "Why does TuistKit miss the cache so often?");
        }}
        class="items-center rounded-lg bg-primary px-4 py-2 active:bg-primary/90"
      >
        <Text class="text-sm font-medium text-primary-foreground">Ask why TuistKit misses</Text>
      </View>
    </View>
  );
}

mount(App);
