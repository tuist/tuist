defmodule Pulse.ResourceBudget do
  @moduledoc """
  Derives a node's admission envelope from one memory budget, so an operator
  sets the pod's memory limit and Pulse sizes ingest and query concurrency to
  stay inside it. Overload then becomes a retryable 429 or overloaded error
  instead of an OOM kill, and autoscaling can add instances on saturation.

  A fixed reserve covers the runtime, code, caches and manifests. Half of the
  rest backs ingest slots (about 32 MiB worst case each: compressed and
  decompressed bodies plus decoded records). The other half backs query
  workers: interactive slots plus one alerting and one reliability worker,
  each with a process heap ceiling. Explicit per-setting variables still win.

  This is a per-instance bound, not a cluster limit. Manifests of unretained
  tenants grow with history and are not covered; enable retention for those.
  """

  import Bitwise, only: [<<<: 2]

  @reserve_mb 256
  @ingest_slot_mb 32
  @background_query_workers 2

  @type envelope :: %{
          budget_mb: pos_integer(),
          ingest_slots: pos_integer(),
          query_slots: pos_integer(),
          query_heap_mb: pos_integer()
        }

  @doc """
  The envelope for `budget_mb` mebibytes.

      iex> Pulse.ResourceBudget.derive(1024)
      %{budget_mb: 1024, ingest_slots: 12, query_slots: 3, query_heap_mb: 76}
  """
  @spec derive(pos_integer()) :: envelope()
  def derive(budget_mb) when is_integer(budget_mb) and budget_mb > 0 do
    usable = max(budget_mb - @reserve_mb, 128)
    half = div(usable, 2)
    workers = @background_query_workers + 3
    heap = half |> div(workers) |> max(32) |> min(128)

    %{
      budget_mb: budget_mb,
      ingest_slots: half |> div(@ingest_slot_mb) |> max(2) |> min(256),
      query_slots: (div(half, heap) - @background_query_workers) |> max(1) |> min(64),
      query_heap_mb: heap
    }
  end

  @doc """
  The memory limit of this process's cgroup in mebibytes, or nil when it is
  unlimited or unknown. Reads cgroup v2, then v1, under `root`.
  """
  @spec cgroup_limit_mb(Path.t()) :: pos_integer() | nil
  def cgroup_limit_mb(root \\ "/sys/fs/cgroup") do
    Enum.find_value([Path.join(root, "memory.max"), Path.join(root, "memory/memory.limit_in_bytes")], fn path ->
      with {:ok, raw} <- File.read(path),
           {bytes, _} when bytes > 0 and bytes < 1 <<< 60 <- Integer.parse(String.trim(raw)) do
        max(div(bytes, 1_048_576), 1)
      else
        _ -> nil
      end
    end)
  end
end
