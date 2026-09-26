defmodule Tuist.OnceEvents.RunEventService do
  @moduledoc """
  gRPC server implementation of `once.events.v1.RunEventService` for the
  Tuist server.

  Handles the four RPCs the client uses to negotiate capabilities, obtain a
  project-scoped argv hash key, stream run events, and probe run
  acknowledgement state on reconnect. Auth resolution is v0: the bearer
  token in the `authorization` metadata is matched against a project token;
  a follow-up folds full OAuth in through the shared HTTP interceptor.
  """
  use GRPC.Server, service: Once.Events.V1.RunEventService.Service

  alias Once.Events.V1.AckDisposition
  alias Once.Events.V1.ArgvHashKey
  alias Once.Events.V1.BatchAck
  alias Once.Events.V1.RunEventAck
  alias Once.Events.V1.RunFinalization
  alias Once.Events.V1.ServerCapabilities
  alias Tuist.Environment
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector
  alias Tuist.Projects
  alias Tuist.Projects.Project

  require Logger

  @protocol_version "1.0"
  # Bumped alongside RFC 0009. `v2` clients may emit `SafeLiteral` for
  # workspace-manifest tokens (target labels, feature names) in
  # addition to the frozen tool/verb allowlist. Older clients keep
  # declaring `v1` and continue to hash those tokens.
  @safe_literal_allowlist_version "2026.09.15-v2"
  @max_batch_bytes 4 * 1024 * 1024
  @max_event_bytes 512 * 1024
  @max_unacked_events 4096
  @max_log_chunk_bytes 64 * 1024
  @finalization_grace_ms 15_000
  @dedup_retention_seconds 86_400
  @argv_hash_key_ttl_ms 24 * 60 * 60 * 1000
  @argv_hash_key_grace_ms 24 * 60 * 60 * 1000

  # ---- GetServerCapabilities -----------------------------------------

  def get_server_capabilities(_req, _stream) do
    %ServerCapabilities{
      supported_protocol_versions: [@protocol_version],
      max_batch_bytes: @max_batch_bytes,
      max_event_bytes: @max_event_bytes,
      max_unacked_events: @max_unacked_events,
      max_log_chunk_bytes: @max_log_chunk_bytes,
      required_features: [],
      log_ingestion_available: false,
      raw_event_retention_available: false,
      finalization_grace_ms: @finalization_grace_ms,
      dedup_retention_seconds: @dedup_retention_seconds,
      safe_literal_allowlist_version: @safe_literal_allowlist_version
    }
  end

  # ---- GetArgvHashKey ------------------------------------------------

  def get_argv_hash_key(req, stream) do
    case resolve_project(stream, req.project_id) do
      {:ok, project} ->
        key = derive_argv_hash_key(project)

        %ArgvHashKey{
          key_id: key.key_id,
          key_bytes: key.key_bytes,
          expires_at_epoch_ms: key.expires_at_epoch_ms,
          grace_after_expiry_ms: @argv_hash_key_grace_ms
        }

      {:error, reason} ->
        raise GRPC.RPCError, status: :unauthenticated, message: to_string(reason)
    end
  end

  # ---- PublishRunEvents ---------------------------------------------

  def publish_run_events(request_stream, stream) do
    project = require_project!(stream)

    Enum.each(request_stream, fn batch ->
      ack = handle_batch(batch, project)
      GRPC.Server.send_reply(stream, ack)
    end)
  end

  defp handle_batch(batch, project) do
    # An empty batch carries `gap_advances` instead of events, and its
    # `seq_from` is one past the last dropped sequence, so the arithmetic
    # below lands on that sequence and lets the client retire the lost
    # range. Either way the ack never regresses below what we already
    # hold, which the client treats as a fatal protocol violation.
    stored_seq = OnceEvents.acked_seq(project.id, batch.run_id)
    batch_last_seq = batch.seq_from + length(batch.events) - 1

    case project_events(batch, project) do
      :ok ->
        {:ok, committed_seq} =
          OnceEvents.observe_acked_seq(project.id, batch.run_id, max(stored_seq, batch_last_seq))

        if committed_seq >= batch_last_seq do
          ack(batch, project, :ACK_DISPOSITION_ACCEPTED, committed_seq)
        else
          # Nothing was stored, so there is no run row holding the mark.
          # Acking a sequence the database does not have would make the next
          # `GetRunAck` regress, which the client treats as fatal.
          ack(batch, project, :ACK_DISPOSITION_NEEDS_RESYNC, committed_seq)
        end

      {:error, _reason} ->
        # Nothing durable happened for the failing event, so the ack must
        # not move the high-water mark past it. `NEEDS_RESYNC` makes the
        # client reopen the stream and resend from where it last saw us,
        # and every projector write is idempotent, so the events in this
        # batch that did land simply replay.
        # Exactly what the database holds. `seq_from - 1` invents a mark that
        # was never persisted, which the next `GetRunAck` contradicts, and
        # `min/2` would regress below the stored mark when the client is
        # replaying an earlier batch. Resending from the stored mark is safe
        # because every projector write is idempotent.
        ack(batch, project, :ACK_DISPOSITION_NEEDS_RESYNC, stored_seq)
    end
  end

  defp ack(batch, project, disposition, acked_seq) do
    %BatchAck{
      run_id: batch.run_id,
      batch_id: batch.batch_id,
      disposition: AckDisposition.value(disposition),
      acked_seq: acked_seq,
      expected_next_seq: acked_seq + 1,
      observed_high_water_seq: acked_seq,
      retry_after_ms: 0,
      max_in_flight_batches: 0,
      finalization: finalization_state(batch.run_id, project.id),
      dashboard_url: dashboard_url(project, batch.run_id)
    }
  end

  defp project_events(batch, project) do
    Enum.reduce_while(batch.events, :ok, fn event, _acc ->
      case project_event(event, project.id, batch.run_id) do
        :ok ->
          {:cont, :ok}

        {:error, error} ->
          Logger.error(
            "Once event projector failed: " <>
              inspect(error) <>
              " (run_id=" <> to_string(batch.run_id) <> ")"
          )

          {:halt, {:error, error}}
      end
    end)
  end

  # The projector reaches Ecto, which raises rather than returning a tagged
  # tuple. This is the transport boundary, so an unexpected crash is turned
  # into a retryable ack instead of taking the stream (and the run) down.
  defp project_event(event, project_id, run_id) do
    Projector.project(event, project_id, run_id)
    :ok
  rescue
    error -> {:error, error}
  end

  # ---- GetRunAck -----------------------------------------------------

  def get_run_ack(req, stream) do
    project = require_project!(stream)

    acked_seq = OnceEvents.acked_seq(project.id, req.run_id)

    %RunEventAck{
      run_id: req.run_id,
      acked_seq: acked_seq,
      expected_next_seq: acked_seq + 1,
      observed_high_water_seq: acked_seq,
      finalization: finalization_state(req.run_id, project.id),
      dashboard_url: dashboard_url(project, req.run_id)
    }
  end

  # ---- Support ------------------------------------------------------

  defp finalization_state(run_id, project_id) do
    case OnceEvents.get_run(project_id, run_id) do
      %{finalization: "finalized"} ->
        RunFinalization.value(:RUN_FINALIZATION_FINALIZED)

      %{finalization: "finalizing"} ->
        RunFinalization.value(:RUN_FINALIZATION_FINALIZING)

      %{finalization: "finalization_pending"} ->
        RunFinalization.value(:RUN_FINALIZATION_FINALIZATION_PENDING)

      %{finalization: "lost"} ->
        RunFinalization.value(:RUN_FINALIZATION_LOST)

      %{} ->
        RunFinalization.value(:RUN_FINALIZATION_ACTIVE)

      nil ->
        RunFinalization.value(:RUN_FINALIZATION_ACTIVE)
    end
  end

  # v0 auth: expect a `authorization: Bearer <token>` header and match it to
  # a project token. Follow-up: reuse `TuistWeb.API.Authentication` so this
  # accepts the same OAuth surface as the HTTP API.
  defp require_project!(stream) do
    case resolve_project(stream, nil) do
      {:ok, project} -> project
      {:error, reason} -> raise GRPC.RPCError, status: :unauthenticated, message: to_string(reason)
    end
  end

  defp resolve_project(stream, hint_project_id) do
    headers =
      try do
        GRPC.Stream.get_headers(stream) || %{}
      rescue
        _ -> %{}
      end

    bearer = extract_bearer(headers)

    with token when is_binary(token) <- bearer,
         %Project{} = project <- Projects.get_project_by_full_token(token) do
      cond do
        is_nil(hint_project_id) or hint_project_id == "" -> {:ok, project}
        to_string(project.id) == hint_project_id -> {:ok, project}
        "#{project.account.name}/#{project.name}" == hint_project_id -> {:ok, project}
        true -> {:error, "project token does not match requested project"}
      end
    else
      _ -> {:error, "missing or invalid bearer"}
    end
  end

  defp extract_bearer(map) when is_map(map) do
    value =
      Enum.find_value(map, fn
        {"authorization", v} -> v
        {"Authorization", v} -> v
        _ -> nil
      end)

    case value do
      "Bearer " <> token -> String.trim(token)
      "bearer " <> token -> String.trim(token)
      _ -> nil
    end
  end

  defp extract_bearer(_), do: nil

  defp derive_argv_hash_key(project) do
    salt = System.get_env("TUIST_ONCE_ARGV_HASH_SALT") || "once-events-argv-salt"

    key_bytes = :crypto.mac(:hmac, :sha256, salt, "argv:#{project.id}")
    key_id = "argv-v1-#{key_bytes |> Base.url_encode64(padding: false) |> binary_part(0, 16)}"

    %{
      key_id: key_id,
      key_bytes: binary_part(key_bytes, 0, 32),
      expires_at_epoch_ms: System.system_time(:millisecond) + @argv_hash_key_ttl_ms
    }
  end

  # The client prints this as the run's "See it live" link. It replaced the
  # templated `ServerCapabilities.live_url_template`, which the protocol
  # reserved so the server, not the client, owns the path shape.
  defp dashboard_url(%Project{} = project, run_id) do
    origin = Environment.app_url(route_type: :app)
    "#{origin}/#{project.account.name}/#{project.name}/once/runs/#{run_id}"
  end
end
