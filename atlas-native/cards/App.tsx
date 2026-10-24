import { mount, signal, Text, View, type YNode } from "nsh";
import { nativeComponent } from "nsh/native";

type Payload = {
  card: {
    type: string;
    data: { title: string; columns: string[]; rows: string[][] };
    actions: { id: string; label: string }[];
  };
  colors: { text: string; secondary: string; surface: string; accent: string; border: string };
};

// The host supplies only Rust-validated data, never credentials, URLs or code.
// All events cross the native adapter and are checked against the current Rust session.
const Host = nativeComponent<{ ready: boolean }, { data: Payload }>("atlas.thread-card", {
  props: ["ready"],
  events: ["data"],
});

function Card() {
  const payload = signal<Payload | undefined>(undefined);
  let host: YNode | undefined;
  return (
    <View style={{ width: "100%" }}>
      <Host ref={(node) => (host = node)} ready={true} onData={(value) => payload.set(value)} style={{ width: 0, height: 0 }} />
      {payload() && (
        <View
          testID={payload()!.card.type === "account_card" ? "thread-account-card" : "thread-result-table"}
          style={{ padding: 16, gap: 12, backgroundColor: payload()!.colors.surface, borderRadius: 12,
            borderWidth: 1, borderColor: payload()!.colors.border }}
          onLayout={({ size }) => host?.command("height", size.height)}
        >
          {payload()!.card.type === "account_card" && (
            <Text style={{ fontSize: 12, fontWeight: "600", color: payload()!.colors.secondary }}>ACCOUNT</Text>
          )}
          <Text style={{ fontSize: 17, fontWeight: "600", color: payload()!.colors.text }}>{payload()!.card.data.title}</Text>
          {payload()!.card.data.rows.map((row, index) => (
            <View style={{ gap: 8, paddingTop: 8 }}>
              {payload()!.card.type === "account_card" ? (
                <View style={{ gap: 4, paddingTop: 8, borderTopWidth: 1, borderColor: payload()!.colors.border }}>
                  <Text style={{ fontSize: 12, color: payload()!.colors.secondary }}>{row[0]}</Text>
                  <Text selectable={true} style={{ fontSize: 15, color: payload()!.colors.text }}>{row[1]}</Text>
                </View>
              ) : <Text style={{ fontSize: 12, color: payload()!.colors.secondary }}>{`Result ${index + 1}`}</Text>}
              {payload()!.card.type !== "account_card" && row.map((value, column) => (
                <View style={{ gap: 2 }}>
                  <Text style={{ fontSize: 12, fontWeight: "600", color: payload()!.colors.secondary }}>
                    {payload()!.card.data.columns[column]}
                  </Text>
                  <Text selectable={true} style={{ fontSize: 15, color: payload()!.colors.text }}>{value}</Text>
                </View>
              ))}
            </View>
          ))}
          {payload()!.card.actions.map((action) => (
            <View
              testID="thread-card-source"
              accessibilityLabel={action.label}
              onPress={() => host?.command("action", action.id)}
              style={{ minHeight: 64, justifyContent: "center", padding: 8 }}
              activeStyle={{ opacity: 0.6 }}
            >
              <Text style={{ fontSize: 15, fontWeight: "600", color: payload()!.colors.accent }}>{action.label}</Text>
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

mount(Card);
