defmodule Tuist.Accounts.Workers.CredentialRotationNoticeWorker do
  @moduledoc """
  Delivers one admin's credential rotation notice for one account, so a failed
  delivery retries without resending it to the admins who already got theirs.
  `notice_id` names one sending (see `Tuist.Release.send_credential_rotation_notice/2`),
  so rerunning that sending queues nothing twice. Arguments hold no credentials.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [keys: [:notice_id, :account_id, :user_id], period: :infinity]

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "user_id" => user_id, "kind" => kind} = args}) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         %User{active: true} = user <- Accounts.get_user_by_id(user_id),
         true <- Accounts.owns_account_or_is_admin_to_account_organization?(user, account) do
      case UserNotifier.deliver_credential_rotation_notice(
             user,
             account,
             String.to_existing_atom(kind),
             args["details_url"]
           ) do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> :ok
    end
  end
end
