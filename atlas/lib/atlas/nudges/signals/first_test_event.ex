defmodule Atlas.Nudges.Signals.FirstTestEvent do
  @moduledoc "Fires once when we detect the account's first-ever test-analytics activity."

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Signals.FirstFeatureEvent

  def name, do: FirstFeatureEvent.name("test_analytics")

  def candidate_account_ids, do: FirstFeatureEvent.candidate_account_ids()

  def evaluate(%Account{} = account) do
    FirstFeatureEvent.evaluate(account, "test_analytics",
      label: "test insights",
      walkthrough:
        "Happy to walk through the test insights: flaky-test detection, selective testing setup, " <>
          "and which dashboards catch a regression fastest."
    )
  end
end
