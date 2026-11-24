defmodule Tuist.Pulse.Workers.SyncSymptomsWorker do
  @moduledoc """
  Pulls the symptoms evaluator's log into the mirror every minute
  (`Tuist.Pulse.Symptoms.sync/1`) for the account Pulse is configured for. A
  run that fails or overlaps another only delays the mirror: revisions apply
  if newer, and the cursor moves in the same transaction as what it covers.
  """
  use Oban.Worker, queue: :pulse_symptoms, max_attempts: 1, unique: [period: 50]

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Pulse.Symptoms

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    with id when is_integer(id) and id > 0 <- Keyword.get(Environment.pulse_config(), :account_id),
         {:ok, account} <- Accounts.get_account_by_id(id) do
      case Symptoms.sync(account) do
        {:ok, _summary} -> :ok
        {:error, :not_configured} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> :ok
    end
  end
end
