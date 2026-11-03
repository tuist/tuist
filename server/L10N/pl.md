---
locale: pl
glossary:
  tests: testy
  features: funkcje
  cache hit: trafienie w pamięci podręcznej
  cache miss: nietrafienie w pamięci podręcznej
  flaky tests: niestabilne testy
  test run: uruchomienie testów
  test case: przypadek testowy
  selective testing: testy selektywne
---

## Polish-specific translation rules

## Voice and Typography

- Write natural Polish for developers. Prefer direct, concise wording and omit unnecessary personal pronouns. Avoid bureaucratic abstractions and literal English sentence structure.
- Use sentence case and omit final periods in headings, navigation, buttons, and short labels. Keep normal sentence punctuation in body copy. Inflect technical nouns, case endings, and counts naturally around preserved names and placeholders.

## Developer Vocabulary and Marketing

- A CI runner is a "runner CI", not a "procesor". A software build can be a "build" or "kompilacja" according to context, never a building ("budynek"). Do not collapse build and compilation when the source distinguishes them. A newsletter issue is a "wydanie", not a "problem".
- Cache misses describe data not found for reuse, not skipped work or failed execution. Retain the reason in labels, for example "Nietrafienia po zmianie danych wejściowych" for changed misses.
- "Shipping" means releasing updates or delivering software, not parcel delivery. Prefer a direct benefit such as "Mniej czekania, więcej czasu na rozwój" for the hero and "Więcej narzędzi dla Twojego zespołu" for the toolbox section, adapting to the actual message.
- Read split headings together. "Faster tests you can" / "actually trust." can be "Szybsze testy, którym możesz" / "naprawdę zaufać", without a final period. The relative pronoun must agree with the verb across the split.
