// Luft's card kit: the only module a thread card may import, as "./luft".
// `LuftServer.Threads.Cards` writes it beside the card and bundles it in. Cards
// compose these components and style nothing themselves, so every card
// looks like the app around it: the theme's tokens, the system's type
// sizes, and Liquid Glass actions on iOS and macOS 26 and later.
import { host, mount as mountApp, platform, Scroll, signal, Text, token, View } from "nsh";

export { signal };

type Children = JSX.Element | string | number | (JSX.Element | string | number)[];

const glass = (platform.os === "ios" || platform.os === "macos") && Number.parseFloat(platform.version) >= 26;

const gaps = { tight: "gap-1", normal: "gap-2", loose: "gap-4" } as const;
type Gap = keyof typeof gaps;

/** Shows the card. The app draws its glass surface; the kit pads it. */
export function mount(App: () => JSX.Element) {
  mountApp(() => (
    <View class="flex-1 gap-3 p-4">
      <App />
    </View>
  ));
}

/** Children in a column. `grow` takes the space left, such as to push actions down. */
export function VStack(props: { gap?: Gap; grow?: boolean; children?: Children }) {
  return <View class={`${gaps[props.gap ?? "normal"]}${props.grow ? " flex-1" : ""}`}>{props.children}</View>;
}

/** Children in a row, centered vertically unless `align` says otherwise. */
export function HStack(props: { gap?: Gap; align?: "start" | "center" | "end"; grow?: boolean; children?: Children }) {
  const align = { start: "items-start", center: "items-center", end: "items-end" }[props.align ?? "center"];
  return (
    <View class={`flex-row ${align} ${gaps[props.gap ?? "normal"]}${props.grow ? " flex-1" : ""}`}>
      {props.children}
    </View>
  );
}

/** Takes the space left in a stack. */
export function Spacer() {
  return <View class="flex-1" />;
}

/** A thin line between groups. */
export function Divider() {
  return <View class="h-px bg-border" />;
}

/** The card's headline, at most two lines. */
export function Title(props: { children: Children }) {
  return <Text class="line-clamp-2 text-base font-semibold text-foreground">{props.children}</Text>;
}

/** Body text. */
export function Body(props: { children: Children }) {
  return <Text class="text-sm text-foreground">{props.children}</Text>;
}

/** Secondary text: a subtitle, a unit, a footnote. */
export function Caption(props: { children: Children }) {
  return <Text class="text-xs text-muted-foreground">{props.children}</Text>;
}

/** One number that matters, with what it is and, optionally, how it changed. */
export function Stat(props: { label: string; value: string | number; detail?: string }) {
  return (
    <View class="flex-1 gap-0.5 self-start">
      <Text class="truncate text-xs text-muted-foreground">{props.label}</Text>
      <Text class="truncate text-2xl font-semibold tabular-nums text-foreground">{props.value}</Text>
      {props.detail ? <Text class="truncate text-xs text-muted-foreground">{props.detail}</Text> : null}
    </View>
  );
}

/** A labelled bar: `value` from 0 to 1, with an optional figure after it. */
export function Meter(props: { label: string; value: number; trailing?: string }) {
  const percent = Math.round(Math.min(1, Math.max(0, props.value)) * 100);
  return (
    <View class="flex-row items-center gap-3">
      <Text class="w-24 truncate text-sm text-foreground">{props.label}</Text>
      <View class="h-1.5 flex-1 rounded-full bg-muted">
        <View class="h-1.5 rounded-full bg-primary" style={{ width: `${percent}%` }} />
      </View>
      {props.trailing ? (
        <Text class="w-14 text-right text-sm tabular-nums text-muted-foreground">{props.trailing}</Text>
      ) : null}
    </View>
  );
}

/** A list row: a title, an optional line under it, and an optional value at its end. */
export function Row(props: { title: string; detail?: string; trailing?: string }) {
  return (
    <View class="min-h-11 flex-row items-center gap-3">
      <View class="flex-1 gap-0.5">
        <Text class="truncate text-sm text-foreground">{props.title}</Text>
        {props.detail ? <Text class="truncate text-xs text-muted-foreground">{props.detail}</Text> : null}
      </View>
      {props.trailing ? <Text class="text-sm tabular-nums text-muted-foreground">{props.trailing}</Text> : null}
    </View>
  );
}

/** A short status label. */
export function Badge(props: { tone?: "neutral" | "accent" | "danger"; children: string }) {
  const tone = {
    neutral: ["bg-muted", "text-foreground"],
    accent: ["bg-primary", "text-primary-foreground"],
    danger: ["bg-destructive", "text-destructive-foreground"],
  }[props.tone ?? "neutral"];
  return (
    <View class={`self-start rounded-full px-2 py-0.5 ${tone[0]}`}>
      <Text class={`text-xs font-medium ${tone[1]}`}>{props.children}</Text>
    </View>
  );
}

/**
 * A button that puts `reply` in the composer for the person to send. On iOS
 * and macOS 26 it is Liquid Glass, tinted with the accent when `prominent`;
 * elsewhere a filled capsule.
 */
export function Action(props: { reply: string; prominent?: boolean; children: string }) {
  const press = () => {
    if (host.available()) void host.call("reply", props.reply);
  };
  const fill = glass ? "" : props.prominent ? " bg-primary" : " bg-muted";
  return (
    <View
      role="button"
      onPress={press}
      class={`min-h-11 items-center justify-center rounded-full px-4 active:opacity-70${fill}`}
      style={glass ? { glassEffect: "regular", glassTintColor: props.prominent ? token("primary") : null } : undefined}
    >
      <Text
        class={`truncate text-sm font-semibold ${props.prominent ? "text-primary-foreground" : "text-foreground"}`}
      >
        {props.children}
      </Text>
    </View>
  );
}

/** A server-authored question. Only decision cards receive the answer capability. */
export function Decision(props: {
  question: string;
  options: { id: string; label: string }[];
  allowOther: boolean;
}) {
  return (
    <Scroll class="flex-1">
      <View class="gap-3">
        <Text class="text-base font-semibold text-foreground">{props.question}</Text>
        {props.options.map((option) => (
          <View
            role="button"
            onPress={() => {
              if (host.available()) void host.call("answer", option.id);
            }}
            class="min-h-11 justify-center rounded-xl bg-muted px-4 py-3 active:opacity-70"
          >
            <Text class="text-sm font-semibold text-foreground">{option.label}</Text>
          </View>
        ))}
      </View>
    </Scroll>
  );
}
