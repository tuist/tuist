defmodule Symptoms.State do
  @moduledoc """
  Reads human and agent state back from the Tuist server (README "Systems of
  record"): `GET {base_url}/api/internal/symptoms/state?after=<cursor>`
  with a projected Kubernetes ServiceAccount token (audience
  `tuist-symptoms-state`) as the bearer token. The token file is read on
  every call because the kubelet rotates it.

  Each page is applied in one transaction with the cursor: acks, mutes and
  outcomes are upserted (the server sends each row's latest state),
  investigations are kept as sent. Then `Symptoms.Labels.derive/2` turns new
  outcomes into labels, and re-derives the labels of every symptom a newly
  applied investigation touches (its symptom, its members and its root), so
  an investigation marked `"reverted": true` after the outcome still makes
  the outcome system-caused. It reads up to 10 pages while the cursor moves.

  Config (`:state`): `base_url`, `token_path` and `req_options` (extra
  `Req` options, for tests).
  """
  use Oban.Worker, queue: :state, max_attempts: 1, unique: [period: 50]

  import Ecto.Query

  alias Symptoms.Labels
  alias Symptoms.Log
  alias Symptoms.Repo
  alias Symptoms.Store
  alias Symptoms.Store.HumanAck
  alias Symptoms.Store.HumanEvent
  alias Symptoms.Store.HumanMute
  alias Symptoms.Store.HumanOutcome
  alias Symptoms.Store.StateCursor
  alias Symptoms.Store.Symptom

  require Logger

  @cursor "state"
  @max_pages 10

  @impl Oban.Worker
  def perform(_job) do
    case readback(DateTime.utc_now()) do
      {:ok, _} -> :ok
      {:error, :not_configured} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reads and applies state changes. Returns `{:ok, %{changes: n, outcomes:
  [symptom_id]}}`, `{:error, :not_configured}` or `{:error, reason}`.
  """
  @spec readback(DateTime.t()) :: {:ok, map()} | {:error, term()}
  def readback(now) do
    with {:ok, client} <- client() do
      pull(client, now, @max_pages, %{changes: 0, outcomes: []})
    end
  end

  defp client do
    config = Application.get_env(:symptoms, :state, [])
    url = config[:base_url]
    path = config[:token_path]

    with true <- is_binary(url) and url != "" and is_binary(path),
         {:ok, token} <- File.read(path),
         token = String.trim(token),
         true <- token != "" do
      {:ok,
       %{
         url: String.trim_trailing(url, "/") <> "/api/internal/symptoms/state",
         token: token,
         options: config[:req_options] || []
       }}
    else
      {:error, reason} -> {:error, {:token, reason}}
      false -> {:error, :not_configured}
    end
  end

  defp pull(_client, _now, 0, summary), do: {:ok, summary}

  defp pull(client, now, pages, summary) do
    cursor = cursor()

    case fetch(client, cursor) do
      {:ok, body} ->
        {count, outcomes, next} = apply_page(body, cursor, now)
        summary = %{changes: summary.changes + count, outcomes: summary.outcomes ++ outcomes}
        if next > cursor, do: pull(client, now, pages - 1, summary), else: {:ok, summary}

      {:error, _} = error ->
        error
    end
  end

  @doc "The read-back cursor (0 before the first read)."
  @spec cursor() :: non_neg_integer()
  def cursor, do: Repo.one(from(c in StateCursor, where: c.name == @cursor, select: c.cursor)) || 0

  defp fetch(client, cursor) do
    options =
      [
        params: [after: cursor],
        auth: {:bearer, client.token},
        headers: [{"accept", "application/json"}],
        receive_timeout: 15_000,
        retry: false
      ] ++ client.options

    case Req.get(client.url, options) do
      {:ok, %Req.Response{status: 200, body: %{"next" => next} = body}} when is_integer(next) -> {:ok, body}
      {:ok, %Req.Response{status: 200}} -> {:error, :malformed_response}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Applies one state page (the server's JSON body) whose request cursor was
  `cursor`. Returns `{changes applied, outcome symptom ids, next cursor}`.
  """
  @spec apply_page(map(), non_neg_integer(), DateTime.t()) :: {non_neg_integer(), [String.t()], non_neg_integer()}
  def apply_page(body, cursor, now) do
    {:ok, result} =
      Repo.transaction(fn ->
        # The log lock first: `Symptoms.Labels.derive/2` appends revisions,
        # and every revision writer locks the log before any row.
        Log.lock!()
        current = cursor()

        # Another replica may have applied a newer response while this
        # request was in flight. Refetch from its cursor, without replacing
        # any human state with this older snapshot.
        if current > cursor do
          {0, [], current}
        else
          next = max(body["next"], cursor)
          acks = Enum.flat_map(list(body, "acks"), &ack_row/1)
          mutes = Enum.flat_map(list(body, "mutes"), &mute_row/1)
          outcomes = Enum.flat_map(list(body, "outcomes"), &outcome_row/1)

          events = Enum.flat_map(list(body, "investigations"), &event_row("investigation", &1))

          Repo.insert_all(HumanAck, acks,
            on_conflict: {:replace, [:revision, :acked_at, :change_seq]},
            conflict_target: [:symptom_id]
          )

          Repo.insert_all(HumanMute, mutes,
            on_conflict: {:replace, [:expires_at, :symptom_id, :change_seq]},
            conflict_target: [:environment, :service, :kind, :key, :phenomenon]
          )

          Repo.insert_all(HumanOutcome, outcomes,
            on_conflict: {:replace, [:outcome, :confirmed_at, :change_seq]},
            conflict_target: [:symptom_id]
          )

          {_, applied} =
            Repo.insert_all(HumanEvent, events,
              on_conflict: :nothing,
              conflict_target: [:kind, :change_seq],
              returning: [:symptom_id, :data]
            )

          Repo.insert_all(StateCursor, [%{name: @cursor, cursor: next, updated_at: now}],
            on_conflict: {:replace, [:cursor, :updated_at]},
            conflict_target: [:name]
          )

          ids = Enum.map(outcomes, & &1.symptom_id)
          Labels.derive(Enum.uniq(ids ++ event_symptom_ids(applied)), now)
          {length(acks) + length(mutes) + length(outcomes) + length(events), ids, next}
        end
      end)

    result
  end

  # The symptoms whose labels an applied investigation event can change: its
  # symptom, the members the server lists, the members the evaluator knows
  # under it, and its symptom's root.
  defp event_symptom_ids([]), do: []

  defp event_symptom_ids(events) do
    ids = for %{symptom_id: id} <- events, id != nil, uniq: true, do: id
    listed = Enum.flat_map(events, &Enum.map(List.wrap(&1.data["member_symptom_ids"]), fn id -> uuid_or_nil(id) end))

    related =
      Repo.all(
        from(s in Symptom,
          where: s.id in ^ids or fragment("(?->'root'->>'root_symptom_id') = ANY(?)", s.document, ^ids),
          select: {s.id, fragment("(?->'root'->>'root_symptom_id')", s.document)}
        )
      )

    roots = for {_, root} <- related, root != nil, do: root
    Enum.uniq(ids ++ Enum.reject(listed, &is_nil/1) ++ Enum.map(related, &elem(&1, 0)) ++ roots)
  end

  defp list(body, key), do: if(is_list(body[key]), do: body[key], else: [])

  defp ack_row(%{"symptom_id" => id, "acked_at" => at, "change_seq" => seq} = ack) when is_integer(seq) do
    with {:ok, uuid} <- Ecto.UUID.cast(id), {:ok, at} <- timestamp(at) do
      [%{symptom_id: uuid, revision: integer(ack, "revision"), acked_at: at, change_seq: seq}]
    else
      _ -> skip(:ack)
    end
  end

  defp ack_row(_), do: skip(:ack)

  defp mute_row(
         %{"entity" => %{} = entity, "phenomenon" => phenomenon, "expires_at" => expires, "change_seq" => seq} = mute
       )
       when is_binary(phenomenon) and is_integer(seq) do
    with {:ok, expires_at} <- timestamp(expires),
         true <- Enum.all?(~w(environment service kind key), &is_binary(entity[&1])) do
      [
        %{
          environment: entity["environment"],
          service: entity["service"],
          kind: entity["kind"],
          key: entity["key"],
          phenomenon: phenomenon,
          expires_at: expires_at,
          symptom_id: uuid_or_nil(mute["symptom_id"]),
          change_seq: seq
        }
      ]
    else
      _ -> skip(:mute)
    end
  end

  defp mute_row(_), do: skip(:mute)

  defp outcome_row(%{"symptom_id" => id, "outcome" => outcome, "confirmed_at" => at, "change_seq" => seq})
       when outcome in ["bad", "fine"] and is_integer(seq) do
    with {:ok, uuid} <- Ecto.UUID.cast(id), {:ok, at} <- timestamp(at) do
      [%{symptom_id: uuid, outcome: outcome, confirmed_at: at, change_seq: seq}]
    else
      _ -> skip(:outcome)
    end
  end

  defp outcome_row(_), do: skip(:outcome)

  defp event_row(kind, %{"change_seq" => seq} = data) when is_integer(seq) do
    [%{kind: kind, symptom_id: uuid_or_nil(data["symptom_id"]), data: data, change_seq: seq}]
  end

  defp event_row(kind, _), do: skip(kind)

  defp skip(kind) do
    Logger.warning("symptoms: skipped a malformed #{kind} in the state read-back")
    []
  end

  defp integer(map, key), do: if(is_integer(map[key]), do: map[key])

  defp uuid_or_nil(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> {:ok, Store.usec(at)}
      _ -> :error
    end
  end

  defp timestamp(_), do: :error
end
