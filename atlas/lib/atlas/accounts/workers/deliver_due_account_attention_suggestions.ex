defmodule Atlas.Accounts.Workers.DeliverDueAccountAttentionSuggestions do
  @moduledoc """
  Delivers suggestions that were not posted or whose snooze period has elapsed.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Accounts
  alias Atlas.Audit

  @impl true
  def perform(%Oban.Job{}) do
    Audit.with_context(%{interface: "worker", metadata: %{"trigger" => "scheduled_delivery"}}, fn ->
      Accounts.list_due_account_attention_suggestions()
      |> Enum.reduce_while(:ok, fn suggestion, :ok ->
        case Accounts.deliver_account_attention_suggestion(suggestion) do
          {:ok, _delivered} ->
            {:cont, :ok}

          {:error, :account_attention_slack_channel_not_configured} ->
            {:halt, {:cancel, :slack_channel_not_configured}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    end)
  end
end
