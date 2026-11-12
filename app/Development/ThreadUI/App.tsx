import { host, mount, signal, Text, View } from "nsh";

type Fact = { label: string; value: string };
const data = host.params as {
  kind: string;
  title: string;
  summary: string;
  facts: Fact[];
  details: string[];
};

function App() {
  const expanded = signal(false);
  return (
    <View style={{ width: "100%" }}>
      <View
        class="gap-3 rounded-2xl border border-zinc-200 bg-zinc-50 p-4 dark:border-zinc-700 dark:bg-zinc-900"
        style={{ flexShrink: 0 }}
        onLayout={(bounds) => host.post("layout.height", bounds.size.height)}
      >
        <Text class="text-xs font-semibold text-zinc-500 dark:text-zinc-400">
          {data.kind === "test_results" ? "TEST RESULTS · SAMPLE" : "CHANGE SUMMARY · SAMPLE"}
        </Text>
        <Text class="text-lg font-semibold text-zinc-950 dark:text-zinc-50">{data.title}</Text>
        <Text class="text-sm text-zinc-600 dark:text-zinc-300">{data.summary}</Text>
        <View class="gap-2">
          {data.facts.map((fact) => (
            <View class="gap-1">
              <Text class="text-xs text-zinc-500 dark:text-zinc-400">{fact.label}</Text>
              <Text class="text-sm font-semibold text-zinc-950 dark:text-zinc-50">{fact.value}</Text>
            </View>
          ))}
        </View>
        <View
          role="button"
          accessibilityLabel={expanded() ? "Hide card details" : "Show card details"}
          class="justify-center rounded-xl bg-zinc-200 px-3 dark:bg-zinc-800"
          style={{ minHeight: 44, paddingVertical: 10 }}
          onPress={() => expanded.set(!expanded())}
        >
          <Text class="text-sm font-semibold text-zinc-950 dark:text-zinc-50">
            {expanded() ? "Hide details ↑" : "Show details ↓"}
          </Text>
        </View>
        {expanded() && (
          <View class="gap-3">
            {data.details.map((detail) => (
              <Text class="text-sm text-zinc-600 dark:text-zinc-300">{detail}</Text>
            ))}
          </View>
        )}
      </View>
    </View>
  );
}

mount(App);
