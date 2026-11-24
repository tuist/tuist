defmodule Symptoms.Log do
  @moduledoc """
  The append-only symptom log (README "Symptom log").

  - `append!/3` writes one revision: a full snapshot with the next global
    `seq` from the `symptom_revision_seq` sequence. It takes a
    transaction-level advisory lock before drawing `seq`, so revisions commit
    in `seq` order and a reader's `after` cursor never skips a late commit,
    then reads the symptom's current revision `FOR UPDATE`, so a caller
    holding a stale struct never reuses a revision. Call it inside
    `Symptoms.Repo.transaction/1`, and deliver pages only after it commits.
  - `fit/1` keeps a snapshot within #{16_384} bytes of JSON by trimming lists
    and dropping the optional evidence before anything the contract needs.
  - `page/2`, `latest/1` and `board/1` back the API.
  """

  import Ecto.Query

  alias Symptoms.Repo
  alias Symptoms.Store.AuditEvent
  alias Symptoms.Store.Revision
  alias Symptoms.Store.Symptom

  @schema_version "1.0"
  @max_bytes 16_384
  @lock 7_301_116_190_001
  @max_limit 500

  @doc """
  Takes the log's transaction-level advisory lock (`append!/3` takes it
  too). A writer that also locks symptom rows takes this first, so every
  writer locks in the same order and none deadlocks. Inside a transaction.
  """
  @spec lock!() :: :ok
  def lock! do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock])
    :ok
  end

  @doc "The snapshot schema version."
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc "The largest snapshot in bytes of JSON."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc """
  Appends the next revision of `symptom` with snapshot `document` (string
  keys, without `seq` and `revision`) at `at`. Returns the updated symptom.
  Must run inside a transaction.
  """
  @spec append!(Symptom.t(), map(), DateTime.t()) :: Symptom.t()
  def append!(%Symptom{} = symptom, document, at) do
    lock!()

    # The caller's struct may be stale: another writer can have appended
    # since it was loaded. The revision is read again under the lock.
    current = Repo.one!(from(s in Symptom, where: s.id == ^symptom.id, lock: "FOR UPDATE", select: s.revision))
    %{rows: [[seq]]} = Repo.query!("SELECT nextval('symptom_revision_seq')")
    revision = current + 1

    document =
      document
      |> Map.merge(%{
        "schema_version" => @schema_version,
        "seq" => seq,
        "symptom_id" => symptom.id,
        "revision" => revision
      })
      |> fit()

    Repo.insert_all(Revision, [
      %{seq: seq, symptom_id: symptom.id, revision: revision, document: document, inserted_at: at}
    ])

    {1, [updated]} =
      Repo.update_all(
        from(s in Symptom, where: s.id == ^symptom.id, select: s),
        set: [revision: revision, document: document, last_revision_at: at, updated_at: at]
      )

    updated
  end

  @doc """
  Trims a snapshot until its JSON is at most #{@max_bytes} bytes: first the
  evidence lists, member ids and touched entities to 20 entries, the title to 200 characters and the entity key to
  its first 200 characters plus `…sha256:<hex digest of the whole key>`, then the evidence and suspected change's touched
  entities entirely, then the member ids and phenomena sources.
  """
  @spec fit(map()) :: map()
  def fit(document) do
    Enum.reduce_while(
      [
        & &1,
        &trim_lists(&1, 20),
        &(&1
          |> Map.put("evidence", %{"series_refs" => [], "example_ids" => [], "masked_excerpts" => []})
          |> put_in_path(["suspected_change", "touched_entities"], [])),
        &(&1
          |> put_in_path(["root", "member_symptom_ids"], [])
          |> Map.update("phenomena", [], fn list -> Enum.map(list, fn p -> Map.put(p, "sources", []) end) end))
      ],
      document,
      fn shrink, doc ->
        doc = shrink.(doc)
        if byte_size(Jason.encode!(doc)) <= @max_bytes, do: {:halt, doc}, else: {:cont, doc}
      end
    )
  end

  defp trim_lists(doc, n) do
    doc
    |> Map.update("title", nil, &(&1 && String.slice(&1, 0, 200)))
    |> update_in_path(["entity", "key"], &trim_key/1)
    |> Map.update("evidence", nil, fn
      %{} = evidence -> Map.new(evidence, fn {k, v} -> {k, if(is_list(v), do: Enum.take(v, n), else: v)} end)
      other -> other
    end)
    |> update_in_path(["root", "member_symptom_ids"], &Enum.take(&1, n))
    |> update_in_path(["suspected_change", "touched_entities"], &Enum.take(&1, n))
  end

  @key_prefix 200

  @doc """
  An entity key as `fit/1` trims it: unchanged up to #{@key_prefix}
  characters, otherwise its first #{@key_prefix} plus `…sha256:<hex digest of
  the whole key>`, so it stays readable and distinct (`symptom_key` hashes
  the full key anyway).
  """
  @spec trim_key(term()) :: term()
  def trim_key(key) when is_binary(key) do
    if String.length(key) <= @key_prefix do
      key
    else
      digest = :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)
      String.slice(key, 0, @key_prefix) <> "…sha256:" <> digest
    end
  end

  def trim_key(key), do: key

  defp put_in_path(doc, path, value), do: update_in_path(doc, path, fn _ -> value end)

  defp update_in_path(doc, [key], fun) when is_map(doc) do
    case doc do
      %{^key => value} when is_list(value) or is_binary(value) -> Map.put(doc, key, fun.(value))
      _ -> doc
    end
  end

  defp update_in_path(doc, [key | rest], fun) when is_map(doc) do
    case doc do
      %{^key => %{} = inner} -> Map.put(doc, key, update_in_path(inner, rest, fun))
      _ -> doc
    end
  end

  @doc """
  Revisions with `seq > after`, at most `limit` (1–#{@max_limit}), in `seq`
  order: `%{revisions: [document], next: seq}` where `next` is the last
  `seq` returned, or `after` when there is none.
  """
  @spec page(non_neg_integer(), pos_integer()) :: %{revisions: [map()], next: non_neg_integer()}
  def page(after_seq, limit) do
    limit = limit |> max(1) |> min(@max_limit)

    revisions =
      Repo.all(from(r in Revision, where: r.seq > ^after_seq, order_by: [asc: r.seq], limit: ^limit, select: r.document))

    %{revisions: revisions, next: if(revisions == [], do: after_seq, else: List.last(revisions)["seq"])}
  end

  @doc "The latest revision of a symptom, or `nil`."
  @spec latest(String.t()) :: map() | nil
  def latest(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.one(from(s in Symptom, where: s.id == ^uuid and s.revision > 0, select: s.document))
      :error -> nil
    end
  end

  @doc """
  Today's board at `now`: the symptoms of the latest push (`Symptoms.Board`,
  at 09:00 Europe/Berlin) that are still open and whose recorded delay
  (`delayed_until`) has passed, in their pushed order. Without a push in the
  last 24 hours, `candidates/1`.
  """
  @spec board(pos_integer(), DateTime.t()) :: [map()]
  def board(limit \\ 5, now \\ DateTime.utc_now()) do
    since = DateTime.shift(now, day: -1)

    pushed =
      Repo.one(
        from(a in AuditEvent,
          where: a.kind == "board_pushed" and a.at >= ^since,
          order_by: [desc: a.at, desc: a.id],
          limit: 1,
          select: a.data
        )
      )

    case pushed do
      %{"symptom_ids" => ids} ->
        open =
          from(s in Symptom,
            where: s.id in ^ids and s.state == "open",
            where: is_nil(s.delayed_until) or s.delayed_until <= ^now
          )
          |> Repo.all()
          |> Map.new(&{&1.id, &1.document})

        ids |> Enum.map(&open[&1]) |> Enum.reject(&is_nil/1) |> Enum.take(limit)

      nil ->
        candidates(limit)
    end
  end

  @doc """
  The open root symptoms at board tier with the highest expected cost
  (intended-shift symptoms from `Symptoms.Deploys` included), at most `limit`.
  """
  @spec candidates(pos_integer()) :: [map()]
  def candidates(limit) do
    Repo.all(
      from(s in Symptom,
        where: s.state == "open" and s.tier == "board" and s.revision > 0,
        where:
          fragment(
            "(?->'root'->>'root_symptom_id') IS NULL OR (?->'root'->>'root_symptom_id') = ?::text",
            s.document,
            s.document,
            s.id
          ),
        order_by: [desc_nulls_last: s.expected_cost, desc: s.opened_at],
        limit: ^limit,
        select: s.document
      )
    )
  end

  @doc "`sha256` (hex) of environment, service, entity kind, entity key and the root's phenomenon class."
  @spec symptom_key({String.t(), String.t(), String.t(), String.t()}, String.t()) :: String.t()
  def symptom_key({environment, service, kind, key}, phenomenon) do
    :sha256
    |> :crypto.hash(Enum.join([environment, service, kind, key, phenomenon], <<0>>))
    |> Base.encode16(case: :lower)
  end

  @doc "A UUIDv7 for `at` (millisecond timestamp, then random bits)."
  @spec uuid7(DateTime.t()) :: String.t()
  def uuid7(at) do
    ms = DateTime.to_unix(at, :millisecond)
    <<rand_a::12, _::6, rand_b::62>> = :crypto.strong_rand_bytes(10)
    Ecto.UUID.cast!(<<ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>)
  end
end
