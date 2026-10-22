---
{
  "title": "Code Coverage",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the line coverage of every file and commit from your test runs, even when the binary cache and selective testing skip work."
}
---
# Code Coverage {#code-coverage}

Code coverage tells you which lines of your code your tests executed. Tuist uploads the coverage of every test run and folds the runs of a commit into one figure, per file and for the whole project, so you can follow it on the dashboard commit after commit. When the binary cache or selective testing skip work, Tuist still measures the code they reuse and carries forward the coverage of the tests they skip.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Upload the code coverage of Xcode projects tested with tuist xcodebuild test."
    link="/guides/features/test-insights/code-coverage/xcode"
/>
  <.home_card
    title="Generated projects"
    details="Measure code coverage in Tuist generated projects with tuist test, the binary cache, and selective testing."
    link="/guides/features/test-insights/code-coverage/generated-xcode-project"
/>
</.home_cards>
