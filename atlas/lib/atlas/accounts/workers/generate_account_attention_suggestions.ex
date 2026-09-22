defmodule Atlas.Accounts.Workers.GenerateAccountAttentionSuggestions do
  @moduledoc """
  Generates and delivers account follow-up suggestions for one account.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Accounts
  alias Atlas.Audit
  alias Atlas.LLMs.Errors, as: LLMErrors

  @impl true
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args}) do
    Audit.with_context(
      %{interface: "worker", metadata: %{"trigger" => Map.get(args, "source", "system")}},
      fn ->
        case Accounts.generate_account_attention_suggestions(account_id) do
          {:ok, suggestions} -> deliver(suggestions)
          {:error, :not_found} -> {:cancel, :account_not_found}
          {:error, :llm_not_configured} -> {:cancel, :llm_not_configured}
          {:error, reason} -> LLMErrors.oban_error(reason)
        end
      end
    )
  end

  defp deliver(suggestions) do
    suggestions
    |> Enum.reduce_while(:ok, fn suggestion, :ok ->
      case Accounts.deliver_account_attention_suggestion(suggestion) do
        {:ok, _delivered} -> {:cont, :ok}
        {:error, :account_attention_slack_channel_not_configured} -> {:halt, {:cancel, :slack_channel_not_configured}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
