defmodule Tuist.Runners.InteractiveSessions do
  @moduledoc """
  Creates and closes interactive runner access sessions.

  This context deliberately stores only server/control-plane session
  state. Browser clients receive short-lived session tokens through the
  eventual gateway path, while relay metadata and Tart VNC credentials
  remain host/server data.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.InteractiveSession

  require Logger

  @default_ttl_seconds 60 * 60

  def request_vnc(%{workflow_job_id: workflow_job_id, account_id: account_id} = job, %Account{id: account_id}, %User{
        id: user_id
      }) do
    with :ok <- validate_vnc_job(job) do
      case current_for_job(account_id, workflow_job_id, :vnc) do
        %InteractiveSession{} = session ->
          {:ok, session}

        nil ->
          create_session(job, user_id, :vnc)
      end
    end
  end

  def request_vnc(_job, _account, _user), do: {:error, :account_mismatch}

  def current_for_job(account_id, workflow_job_id, kind)
      when is_integer(account_id) and is_integer(workflow_job_id) and kind in [:vnc, :shell] do
    InteractiveSession
    |> where(
      [session],
      session.account_id == ^account_id and session.workflow_job_id == ^workflow_job_id and
        session.kind == ^kind and is_nil(session.closed_at)
    )
    |> order_by([session], desc: session.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def validate_token(token) when is_binary(token) and token != "" do
    now = now()
    hash = token_hash(token)

    InteractiveSession
    |> where([session], session.token_hash == ^hash and is_nil(session.closed_at) and session.expires_at > ^now)
    |> Repo.one()
    |> case do
      %InteractiveSession{} = session -> {:ok, session}
      nil -> {:error, :invalid_or_expired}
    end
  end

  def close(%InteractiveSession{} = session, reason \\ "user") do
    closed_at = now()

    session
    |> InteractiveSession.changeset(%{
      state: :closed,
      closed_at: closed_at,
      close_reason: reason,
      updated_at: closed_at
    })
    |> Repo.update()
  end

  def close_for_job(account_id, workflow_job_id, kind, reason \\ "user")
      when is_integer(account_id) and is_integer(workflow_job_id) and kind in [:vnc, :shell] do
    case current_for_job(account_id, workflow_job_id, kind) do
      nil -> {:ok, :no_open_session}
      %InteractiveSession{} = session -> close(session, reason)
    end
  end

  def close_by_pod_name(pod_name, %DateTime{} = closed_at, reason \\ "pod_exit")
      when is_binary(pod_name) and pod_name != "" do
    sessions =
      InteractiveSession
      |> where([session], session.pod_name == ^pod_name and is_nil(session.closed_at))
      |> Repo.all()

    Enum.reduce_while(sessions, {:ok, :no_open_session}, fn session, _acc ->
      result =
        session
        |> InteractiveSession.changeset(%{
          state: :closed,
          closed_at: DateTime.truncate(closed_at, :second),
          close_reason: reason,
          updated_at: now()
        })
        |> Repo.update()

      case result do
        {:ok, updated} ->
          {:cont, {:ok, updated}}

        {:error, changeset} ->
          Logger.warning("runners: failed to close interactive session",
            pod_name: pod_name,
            changeset_errors: inspect(changeset.errors)
          )

          {:halt, {:error, changeset}}
      end
    end)
  end

  def close_expired(now \\ now()) do
    {count, _} =
      InteractiveSession
      |> where([session], is_nil(session.closed_at) and session.expires_at <= ^now)
      |> Repo.update_all(
        set: [
          state: :closed,
          closed_at: now,
          close_reason: "expired",
          updated_at: now
        ]
      )

    {:ok, count}
  end

  def vnc_requestable?(%{fleet_name: fleet_name, status: status, pod_name: pod_name}) do
    Catalog.fleet_platform(fleet_name) == :macos and status in ["claimed", "running"] and
      is_binary(pod_name) and pod_name != ""
  end

  def vnc_requestable?(_), do: false

  defp validate_vnc_job(job) do
    cond do
      Catalog.fleet_platform(job.fleet_name) != :macos ->
        {:error, :unsupported_platform}

      job.status not in ["claimed", "running"] ->
        {:error, :job_not_running}

      not is_binary(job.pod_name) or job.pod_name == "" ->
        {:error, :pod_unavailable}

      true ->
        :ok
    end
  end

  defp create_session(job, user_id, kind) do
    {token, hash} = build_token()
    now = now()

    attrs = %{
      account_id: job.account_id,
      workflow_job_id: job.workflow_job_id,
      pod_name: job.pod_name,
      fleet_name: job.fleet_name,
      kind: kind,
      state: :requested,
      token_hash: hash,
      requested_by_user_id: user_id,
      expires_at: DateTime.add(now, @default_ttl_seconds, :second),
      last_activity_at: now
    }

    %InteractiveSession{}
    |> InteractiveSession.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, session} ->
        {:ok, %{session | token: token}}

      {:error, changeset} ->
        case current_for_job(job.account_id, job.workflow_job_id, kind) do
          %InteractiveSession{} = session -> {:ok, session}
          nil -> {:error, changeset}
        end
    end
  end

  defp build_token do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {token, token_hash(token)}
  end

  defp token_hash(token), do: :crypto.hash(:sha256, token)

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
