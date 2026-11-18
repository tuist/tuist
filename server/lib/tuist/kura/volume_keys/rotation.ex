defmodule Tuist.Kura.VolumeKeys.Rotation do
  @moduledoc """
  Bounded, resumable root rewrap. Results contain identifiers/counts only.
  Run on a release with the old decrypt keys and the new wrapping target.
  Never retire a key on the strength of the live inventory alone: retained
  backups still need their original wrapping keys.
  """
  import Ecto.Query

  alias Tuist.Kura.VolumeKeys
  alias Tuist.Kura.VolumeKeys.TenantKey
  alias Tuist.Repo

  def inventory do
    {:ok, %{rows: rows}} =
      Repo.query("""
      SELECT share->>'provider', share->>'key_id', k.state, count(*)
      FROM kura_tenant_keys k CROSS JOIN LATERAL unnest(k.shares) AS share
      GROUP BY 1, 2, 3 ORDER BY 1, 2, 3
      """)

    Enum.map(rows, fn [provider, key_id, state, count] ->
      %{provider: provider, key_id: key_id, state: state, shares: count}
    end)
  end

  def batch({provider, key_id} = target, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    after_id = Keyword.get(opts, :after_id)

    with true <- is_integer(limit) and limit in 1..100,
         {:ok, ^provider, ^key_id} <- VolumeKeys.wrapping_target() do
      query = from(k in TenantKey, order_by: k.id, limit: ^limit, select: k.id)
      query = if after_id, do: from(k in query, where: k.id > ^after_id), else: query
      ids = Repo.all(query)
      initial = %{processed: 0, after_id: after_id, done: length(ids) < limit}

      Enum.reduce_while(ids, {:ok, initial}, fn id, {:ok, progress} ->
        case VolumeKeys.rewrap_key(id, target) do
          :ok -> {:cont, {:ok, %{progress | processed: progress.processed + 1, after_id: id}}}
          {:error, reason} -> {:halt, {:error, %{reason: reason, key_id: id, progress: %{progress | done: false}}}}
        end
      end)
    else
      false -> {:error, :invalid_limit}
      {:error, _} = error -> error
      _ -> {:error, :wrapping_target_changed}
    end
  end
end
