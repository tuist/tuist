defmodule Atlas.Nudges.Signals.FirstCacheEvent do
  @moduledoc "Fires once when we detect the account's first-ever cache activity."

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Signals.FirstFeatureEvent

  def name, do: FirstFeatureEvent.name("cache")

  def candidate_account_ids, do: FirstFeatureEvent.candidate_account_ids()

  def evaluate(%Account{} = account) do
    FirstFeatureEvent.evaluate(account, "cache",
      label: "cache",
      walkthrough:
        "We can walk through the cache analytics dashboard, what to look for when hit rate " <>
          "moves, and how to catch a regression before it costs CI time."
    )
  end
end
