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
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.InteractiveSession
  alias Tuist.Runners.InteractiveSessionConnection
  alias Tuist.Runners.Workers.CloseDisconnectedInteractiveSessionWorker

  require Logger

  @default_ttl_seconds 60 * 60
  @disconnect_grace_seconds 60
  @vnc_session_id_annotation "tuist.dev/vnc-session-id"
  @vnc_requested_at_annotation "tuist.dev/vnc-requested-at"
  @vnc_relay_token_hash_annotation "tuist.dev/vnc-relay-token-hash"
  @vnc_state_annotation "tuist.dev/vnc-state"
  @vnc_relay_host_annotation "tuist.dev/vnc-relay-host"
  @vnc_relay_port_annotation "tuist.dev/vnc-relay-port"
  @vnc_relay_ready_at_annotation "tuist.dev/vnc-relay-ready-at"

  def vnc_session_id_annotation, do: @vnc_session_id_annotation
  def vnc_requested_at_annotation, do: @vnc_requested_at_annotation
  def vnc_relay_token_hash_annotation, do: @vnc_relay_token_hash_annotation
  def vnc_state_annotation, do: @vnc_state_annotation
  def vnc_relay_host_annotation, do: @vnc_relay_host_annotation
  def vnc_relay_port_annotation, do: @vnc_relay_port_annotation
  def vnc_relay_ready_at_annotation, do: @vnc_relay_ready_at_annotation

  def request_vnc(%{workflow_job_id: workflow_job_id, account_id: account_id} = job, %Account{id: account_id}, %User{
        id: user_id
      }) do
    with :ok <- validate_vnc_job(job) do
      case current_for_job(account_id, workflow_job_id, :vnc) do
        %InteractiveSession{} = session ->
          refresh_token(session, user_id)

        nil ->
          create_session(job, user_id, :vnc)
      end
    end
  end

  def request_vnc(_job, _account, _user), do: {:error, :account_mismatch}

  def request_shell(%{workflow_job_id: workflow_job_id, account_id: account_id} = job, %Account{id: account_id}, %User{
        id: user_id
      }) do
    with :ok <- validate_shell_job(job) do
      case current_for_job(account_id, workflow_job_id, :shell) do
        %InteractiveSession{} = session ->
          refresh_token(session, user_id)

        nil ->
          create_session(job, user_id, :shell)
      end
    end
  end

  def request_shell(_job, _account, _user), do: {:error, :account_mismatch}

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

  def current_shell_for_pod(pod_name) when is_binary(pod_name) and pod_name != "" do
    now = now()

    InteractiveSession
    |> where(
      [session],
      session.pod_name == ^pod_name and session.kind == :shell and is_nil(session.closed_at) and
        session.expires_at > ^now
    )
    |> order_by([session], desc: session.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def current_shell_for_pod(_pod_name), do: nil

  def validate_token(token, %Account{id: account_id}, %User{id: user_id}) when is_binary(token) and token != "" do
    now = now()
    hash = token_hash(token)

    InteractiveSession
    |> where(
      [session],
      session.token_hash == ^hash and session.account_id == ^account_id and
        session.requested_by_user_id == ^user_id and is_nil(session.closed_at) and session.expires_at > ^now
    )
    |> Repo.one()
    |> case do
      %InteractiveSession{} = session -> {:ok, session}
      nil -> {:error, :invalid_or_expired}
    end
  end

  def validate_token(_token, %Account{}, %User{}), do: {:error, :invalid_or_expired}

  def validate_token(token, %User{id: user_id}) when is_binary(token) and token != "" do
    now = now()
    hash = token_hash(token)

    InteractiveSession
    |> where(
      [session],
      session.token_hash == ^hash and session.requested_by_user_id == ^user_id and is_nil(session.closed_at) and
        session.expires_at > ^now
    )
    |> Repo.one()
    |> case do
      %InteractiveSession{} = session -> {:ok, session}
      nil -> {:error, :invalid_or_expired}
    end
  end

  def validate_token(_token, %User{}), do: {:error, :invalid_or_expired}

  def validate_shell_pod(session_id, pod_name) when is_integer(session_id) and is_binary(pod_name) and pod_name != "" do
    now = now()

    InteractiveSession
    |> where(
      [session],
      session.id == ^session_id and session.kind == :shell and session.pod_name == ^pod_name and
        is_nil(session.closed_at) and session.expires_at > ^now
    )
    |> Repo.one()
    |> case do
      %InteractiveSession{} = session -> {:ok, session}
      nil -> {:error, :not_found}
    end
  end

  def validate_shell_pod(_session_id, _pod_name), do: {:error, :not_found}

  def mark_shell_ready(%InteractiveSession{kind: :shell, closed_at: nil} = session) do
    now = now()

    attrs =
      maybe_put_ready_state(
        %{
          last_activity_at: now,
          updated_at: now
        },
        session
      )

    session
    |> InteractiveSession.changeset(attrs)
    |> Repo.update()
  end

  def mark_shell_ready(%InteractiveSession{}), do: {:error, :closed_session}

  def request_vnc_relay(%InteractiveSession{kind: :vnc, closed_at: nil} = session) do
    now = now()

    Environment.runners_namespace()
    |> K8sClient.patch_pod(session.pod_name, %{
      "metadata" => %{
        "annotations" => %{
          @vnc_session_id_annotation => Integer.to_string(session.id),
          @vnc_requested_at_annotation => DateTime.to_iso8601(now),
          @vnc_relay_token_hash_annotation => Base.url_encode64(session.token_hash, padding: false)
        }
      }
    })
    |> case do
      {:ok, _pod} ->
        :ok

      {:error, :not_found} ->
        _ = close(session, "pod_not_found")
        {:error, :pod_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def request_vnc_relay(_session), do: {:error, :unsupported_session}

  def sync_vnc_relay_state(%InteractiveSession{kind: :vnc, closed_at: nil} = session) do
    case K8sClient.get_pod(Environment.runners_namespace(), session.pod_name) do
      {:ok, pod} ->
        sync_vnc_relay_state_from_pod(session, pod)

      {:error, :not_found} ->
        close(session, "pod_not_found")

      {:error, reason} ->
        {:error, reason}
    end
  end

  def sync_vnc_relay_state(%InteractiveSession{} = session), do: {:ok, session}

  def mark_vnc_relay_ready(%InteractiveSession{kind: :vnc, closed_at: nil} = session, relay_host, relay_port)
      when is_binary(relay_host) and relay_host != "" and is_integer(relay_port) and relay_port > 0 and
             relay_port <= 65_535 do
    mark_relay_ready(session, relay_host, relay_port)
  end

  def mark_vnc_relay_ready(%InteractiveSession{}, _relay_host, _relay_port), do: {:error, :closed_session}

  def disconnect_grace_seconds, do: @disconnect_grace_seconds

  def mark_active(session, connection_id \\ Ecto.UUID.generate())

  def mark_active(%InteractiveSession{closed_at: nil, id: session_id}, connection_id)
      when is_binary(connection_id) and connection_id != "" do
    now = now()

    Repo.transaction(fn ->
      session =
        InteractiveSession
        |> where([candidate], candidate.id == ^session_id and is_nil(candidate.closed_at))
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %InteractiveSession{} <- session,
           {:ok, active} <-
             session
             |> InteractiveSession.changeset(%{
               state: :active,
               connected_at: session.connected_at || now,
               last_activity_at: now,
               updated_at: now
             })
             |> Repo.update(),
           {:ok, _connection} <- create_connection(active.id, connection_id, now) do
        active
      else
        nil -> Repo.rollback(:closed_session)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def mark_active(%InteractiveSession{}, _connection_id), do: {:error, :closed_session}

  def schedule_disconnect_close(session, connection_id, opts \\ [])

  def schedule_disconnect_close(%InteractiveSession{id: id}, connection_id, opts)
      when is_binary(connection_id) and connection_id != "" do
    now = now()
    grace_seconds = Keyword.get(opts, :grace_seconds, @disconnect_grace_seconds)

    InteractiveSessionConnection
    |> where(
      [connection],
      connection.interactive_session_id == ^id and connection.connection_id == ^connection_id and
        is_nil(connection.disconnected_at)
    )
    |> Repo.update_all(set: [disconnected_at: now, updated_at: now])

    %{session_id: id, connection_id: connection_id}
    |> CloseDisconnectedInteractiveSessionWorker.new(schedule_in: grace_seconds)
    |> Oban.insert()
  end

  def schedule_disconnect_close(%InteractiveSession{}, _connection_id, _opts), do: {:ok, :inactive_session}

  def close_if_disconnected(session_id, connection_id)
      when is_integer(session_id) and is_binary(connection_id) and connection_id != "" do
    case close_disconnected(session_id, connection_id) do
      {:ok, %InteractiveSession{} = closed} ->
        with :ok <- clear_vnc_relay_request(closed) do
          {:ok, closed}
        end

      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def close(%InteractiveSession{} = session, reason \\ "user") do
    close(session, reason, now())
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
    sessions =
      InteractiveSession
      |> where([session], is_nil(session.closed_at) and session.expires_at <= ^now)
      |> Repo.all()

    Enum.reduce_while(sessions, {:ok, 0}, fn session, {:ok, count} ->
      result =
        with :ok <- clear_vnc_relay_request(session) do
          close(session, "expired", now)
        end

      case result do
        {:ok, _session} ->
          {:cont, {:ok, count + 1}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def vnc_requestable?(%{fleet_name: fleet_name, status: status, pod_name: pod_name}) do
    Catalog.fleet_platform(fleet_name) == :macos and status in ["claimed", "running"] and
      is_binary(pod_name) and pod_name != ""
  end

  def vnc_requestable?(_), do: false

  def shell_requestable?(%{fleet_name: fleet_name, status: status, pod_name: pod_name}) do
    Catalog.fleet_platform(fleet_name) in [:macos, :linux] and status in ["claimed", "running"] and
      is_binary(pod_name) and pod_name != ""
  end

  def shell_requestable?(_), do: false

  defp sync_vnc_relay_state_from_pod(session, pod) do
    annotations = get_in(pod, ["metadata", "annotations"]) || %{}
    session_id = Integer.to_string(session.id)

    with ^session_id <- annotations[@vnc_session_id_annotation],
         "ready" <- annotations[@vnc_state_annotation],
         relay_host when is_binary(relay_host) and relay_host != "" <- annotations[@vnc_relay_host_annotation],
         relay_port_raw when is_binary(relay_port_raw) <- annotations[@vnc_relay_port_annotation],
         {relay_port, ""} when relay_port > 0 and relay_port <= 65_535 <- Integer.parse(relay_port_raw) do
      mark_relay_ready(session, relay_host, relay_port)
    else
      _ -> {:ok, session}
    end
  end

  defp mark_relay_ready(session, relay_host, relay_port) do
    now = now()

    attrs =
      maybe_put_ready_state(
        %{
          relay_host: relay_host,
          relay_port: relay_port,
          relay_ready_at: session.relay_ready_at || now,
          last_activity_at: now,
          updated_at: now
        },
        session
      )

    session
    |> InteractiveSession.changeset(attrs)
    |> Repo.update()
  end

  defp maybe_put_ready_state(attrs, %{state: :requested}), do: Map.put(attrs, :state, :ready)
  defp maybe_put_ready_state(attrs, _session), do: attrs

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

  defp validate_shell_job(job) do
    cond do
      Catalog.fleet_platform(job.fleet_name) not in [:macos, :linux] ->
        {:error, :unsupported_platform}

      job.status not in ["claimed", "running"] ->
        {:error, :job_not_running}

      not is_binary(job.pod_name) or job.pod_name == "" ->
        {:error, :pod_unavailable}

      true ->
        :ok
    end
  end

  defp close(%InteractiveSession{} = session, reason, %DateTime{} = closed_at) do
    session
    |> InteractiveSession.changeset(%{
      state: :closed,
      closed_at: DateTime.truncate(closed_at, :second),
      close_reason: reason,
      updated_at: DateTime.truncate(closed_at, :second)
    })
    |> Repo.update()
  end

  defp close_disconnected(session_id, connection_id) do
    Repo.transaction(fn ->
      session =
        InteractiveSession
        |> where([candidate], candidate.id == ^session_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(session) ->
          :no_open_session

        not is_nil(session.closed_at) and session.close_reason == "browser_disconnect" ->
          session

        not is_nil(session.closed_at) ->
          :no_open_session

        true ->
          close_if_last_disconnected_connection(session, connection_id)
      end
    end)
  end

  defp close_if_last_disconnected_connection(%InteractiveSession{} = session, connection_id) do
    connection =
      Repo.get_by(InteractiveSessionConnection,
        interactive_session_id: session.id,
        connection_id: connection_id
      )

    cond do
      is_nil(connection) ->
        :no_open_connection

      is_nil(connection.disconnected_at) ->
        :still_connected

      active_connection?(session.id) ->
        :active_connections

      newer_disconnected_connection?(connection) ->
        :newer_disconnect_pending

      true ->
        case close(session, "browser_disconnect") do
          {:ok, closed} -> closed
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp active_connection?(interactive_session_id) do
    InteractiveSessionConnection
    |> where(
      [connection],
      connection.interactive_session_id == ^interactive_session_id and is_nil(connection.disconnected_at)
    )
    |> Repo.exists?()
  end

  defp newer_disconnected_connection?(%InteractiveSessionConnection{
         id: id,
         interactive_session_id: interactive_session_id,
         disconnected_at: disconnected_at
       }) do
    InteractiveSessionConnection
    |> where(
      [connection],
      connection.interactive_session_id == ^interactive_session_id and not is_nil(connection.disconnected_at) and
        (connection.disconnected_at > ^disconnected_at or
           (connection.disconnected_at == ^disconnected_at and connection.id > ^id))
    )
    |> Repo.exists?()
  end

  defp clear_vnc_relay_request(%InteractiveSession{kind: :vnc, pod_name: pod_name} = session)
       when is_binary(pod_name) and pod_name != "" do
    case K8sClient.get_pod(Environment.runners_namespace(), pod_name) do
      {:ok, pod} ->
        annotations = get_in(pod, ["metadata", "annotations"]) || %{}

        if annotations[@vnc_session_id_annotation] == Integer.to_string(session.id) do
          clear_vnc_relay_annotations(pod_name)
        else
          :ok
        end

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp clear_vnc_relay_request(%InteractiveSession{}), do: :ok

  defp clear_vnc_relay_annotations(pod_name) do
    Environment.runners_namespace()
    |> K8sClient.patch_pod(pod_name, %{
      "metadata" => %{
        "annotations" => %{
          @vnc_session_id_annotation => nil,
          @vnc_requested_at_annotation => nil,
          @vnc_relay_token_hash_annotation => nil,
          @vnc_state_annotation => nil,
          @vnc_relay_host_annotation => nil,
          @vnc_relay_port_annotation => nil,
          @vnc_relay_ready_at_annotation => nil
        }
      }
    })
    |> case do
      {:ok, _pod} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
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
          %InteractiveSession{} = session -> refresh_token(session, user_id)
          nil -> {:error, changeset}
        end
    end
  end

  defp refresh_token(%InteractiveSession{} = session, user_id) do
    {token, hash} = build_token()
    now = now()

    session
    |> InteractiveSession.changeset(%{
      token_hash: hash,
      requested_by_user_id: user_id,
      expires_at: DateTime.add(now, @default_ttl_seconds, :second),
      last_activity_at: now,
      updated_at: now
    })
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, %{updated | token: token}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp create_connection(interactive_session_id, connection_id, connected_at) do
    %InteractiveSessionConnection{}
    |> InteractiveSessionConnection.changeset(%{
      interactive_session_id: interactive_session_id,
      connection_id: connection_id,
      connected_at: connected_at
    })
    |> Repo.insert()
  end

  defp build_token do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {token, token_hash(token)}
  end

  defp token_hash(token), do: :crypto.hash(:sha256, token)

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
