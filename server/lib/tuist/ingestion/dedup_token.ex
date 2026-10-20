defmodule Tuist.Ingestion.DedupToken do
  @moduledoc """
  Build an `insert_deduplication_token` for a batch of analytics events.

  ClickHouse dedupes an INSERT block whose token matches a recent block, so
  a Kura retry of the same batch of events dedupes wholesale before any
  materialised view consumes it. The token here is a namespaced SHA-256 of
  the sorted producer `event_id` values in the batch: a legitimately new
  batch with a different id set never collides with an earlier one, and a
  retried batch with the same ids produces the same token.

  A batch whose events carry no producer `event_id` (or a mixed batch, some
  producer and some server-minted) gets no token: a server-minted id
  differs every request, so a token would either be trivially unique per
  request (useless) or would collapse legitimately distinct events.
  Producer-owned identity is the prerequisite for INSERT-level dedup, and
  Kura started emitting `event_id` in the branch that shipped just before
  this module — pre-that Kura simply keeps today's non-dedup behaviour.
  """

  @doc """
  Return the Ecto `insert_all` opts to attach to a batch INSERT, or an
  empty list if the batch does not qualify for INSERT-level dedup.

  `namespace` scopes the token so a token collision across unrelated
  pipelines cannot happen.

  The test environment routes ClickHouse INSERTs through an Ecto SQL
  sandbox transaction. Passing `insert_deduplication_token` there makes
  the row invisible to the same session's subsequent SELECT (the token
  causes ClickHouse to route the block through a keeper-coordinated path
  that does not join the sandbox transaction), so tests would see
  post-INSERT queries return zero rows on every write. Skipping the token
  in tests keeps the sandbox pattern working; the token's dedup
  behaviour is exercised in `dedup_token_test.exs` at the unit level, and
  the production path always attaches it.
  """
  def insert_all_opts(events, namespace) when is_list(events) and is_binary(namespace) do
    if Tuist.Environment.test?() do
      []
    else
      opts_for(events, namespace)
    end
  end

  defp opts_for(events, namespace) do
    case producer_event_ids(events) do
      [] ->
        []

      ids when length(ids) == length(events) ->
        [settings: [insert_deduplication_token: "#{namespace}:#{fingerprint(ids)}"]]

      _partial ->
        []
    end
  end

  defp producer_event_ids(events) do
    Enum.flat_map(events, fn event ->
      case Map.get(event, :event_id) do
        id when is_binary(id) -> [id]
        _ -> []
      end
    end)
  end

  defp fingerprint(ids) do
    ids
    |> Enum.sort()
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
