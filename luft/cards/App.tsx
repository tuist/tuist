// A card as a model writes it: composed from Luft's card kit
// (`../../server/priv/threads/card_kit.tsx`, imported as "./luft"), which the
// server bundles into every card. Luft shows it at a fixed size the Rust
// core chose, on the app's glass, so it fills its frame and never measures
// itself. Its only way out is the kit's `Action`, which puts its reply in the
// conversation's composer for the person to send.
import { Action, Caption, HStack, Meter, mount, Spacer, Title, VStack } from "./luft";

const targets = [
  { name: "TuistKit", seconds: 412, hit: 0.31 },
  { name: "TuistCore", seconds: 188, hit: 0.74 },
  { name: "TuistSupport", seconds: 96, hit: 0.92 },
];

function App() {
  return (
    <VStack grow>
      <VStack gap="tight">
        <Title>Slowest targets this week</Title>
        <Caption>Bar: cache hit rate · right: median build time</Caption>
      </VStack>
      {targets.map((target) => (
        <Meter label={target.name} value={target.hit} trailing={`${target.seconds}s`} />
      ))}
      <Spacer />
      <HStack>
        <Action prominent reply="Why does TuistKit miss the cache so often?">
          Ask why TuistKit misses
        </Action>
      </HStack>
    </VStack>
  );
}

mount(App);
