---
{
  "title": "Code Coverage",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Track the line coverage of every file and commit from your test runs."
}
---
# Code Coverage {#code-coverage}

Code coverage tells you which lines of your code your tests executed. Tuist uploads the coverage of every test run and folds the runs of a commit into one figure, per file and for the whole project, so you can follow it on the dashboard commit after commit.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Upload the code coverage of Xcode projects tested with tuist xcodebuild test."
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="Generated projects"
    details="Measure code coverage in Tuist generated projects with tuist test, the binary cache, and selective testing."
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="Upload the line coverage of Elixir projects tested with mix test --cover."
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="Upload the line coverage of Rust projects tested with cargo test."
    link="/guides/features/test-code-coverage/rust"
/>
</.home_cards>
