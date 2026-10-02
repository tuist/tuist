defmodule Atlas.Nudges.Workers.EvaluateSignalForAccount do
  @moduledoc """
  Runs one signal against one account. On `{:ok, proposal}` inserts a
  pending nudge; on `{:recovered, _}` closes the open episode; on `:skip`
  does nothing.

  Deduped so a slow evaluator does not stack behind itself.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      period: 3600,
      fields: [:worker, :args],
      keys: [:signal, :account_id],
      states: :incomplete
    ]

  alias Atlas.Accounts.Query
  alias Atlas.Nudges
  alias Atlas.Nudges.Proposal
  alias Atlas.Nudges.Workers.EvaluateSignals
  alias Atlas.Nudges.Workers.PostNudgeCard

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"signal" => signal_string, "account_id" => account_id}}) do
    with {:ok, signal_module} <- resolve_signal(signal_string),
         %_{} = account <- Query.get_account(account_id) do
      case signal_module.evaluate(account) do
        {:ok, %Proposal{} = proposal} ->
          handle_proposal(account, signal_module.name(), proposal)

        {:recovered, _evidence} ->
          Nudges.close_episode(account, signal_module.name())
          :ok

        :skip ->
          :ok
      end
    else
      {:error, :unknown_signal} -> {:cancel, :unknown_signal}
      nil -> {:cancel, :account_not_found}
    end
  end

  defp handle_proposal(account, signal_name, proposal) do
    case Nudges.propose(account, signal_name, proposal) do
      {:ok, nudge} ->
        %{"nudge_id" => nudge.id}
        |> PostNudgeCard.new()
        |> Oban.insert()

        :ok

      {:skip, reason} ->
        Logger.info("Nudge skipped for account=#{account.id} signal=#{signal_name}: #{inspect(reason)}")

        :ok

      {:error, reason} ->
        Logger.warning("Nudge insert failed for account=#{account.id} signal=#{signal_name}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp resolve_signal(signal_string) do
    if signal_string in Enum.map(EvaluateSignals.signals(), &to_string/1) do
      {:ok, String.to_existing_atom(signal_string)}
    else
      {:error, :unknown_signal}
    end
  end
end
