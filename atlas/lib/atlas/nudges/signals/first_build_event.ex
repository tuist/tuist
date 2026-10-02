defmodule Atlas.Nudges.Signals.FirstBuildEvent do
  @moduledoc "Fires once when we detect the account's first-ever build activity."

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Signals.FirstFeatureEvent

  def name, do: FirstFeatureEvent.name("builds")

  def candidate_account_ids, do: FirstFeatureEvent.candidate_account_ids()

  def evaluate(%Account{} = account) do
    FirstFeatureEvent.evaluate(account, "builds",
      label: "build insights",
      walkthrough:
        "Happy to walk through build insights: how to spot slow targets, when to set up build-" <>
          "time alerts, and which patterns catch a regression before shipping."
    )
  end
end
