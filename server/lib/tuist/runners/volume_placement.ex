defmodule Tuist.Runners.VolumePlacement do
  @moduledoc """
  Which Nodes of a host class (or a Linux fleet) hold a repository's cache
  volumes. Every volume of one repository goes to the same Nodes, so a job finds
  all of the volumes it attaches on any one of them, and dispatch steers the
  repository's jobs to those Nodes (`VolumeAffinities`).

  Nodes are picked by weighted rendezvous hashing: each Node scores the key, and
  the highest scores hold it. A Node's weight is its cache capacity, so larger
  disks hold proportionally more repositories. Adding or removing a Node only
  moves the repositories that Node takes or held.
  """

  @min_replicas 2

  @doc """
  The `count` Nodes of `weights` (a map of Node name to positive weight) that
  hold `key`'s volumes, highest score first.
  """
  def holders(key, weights, count) when is_binary(key) and is_map(weights) and is_integer(count) do
    weights
    |> Enum.sort_by(fn {node, weight} -> score(key, node, weight) end, :desc)
    |> Enum.take(count)
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  How many of `peer_count` Nodes hold a repository whose jobs ran at most
  `peak_concurrency` at a time: one more than that, so the repository's next job
  finds an idle holder while the others run, and never fewer than two, so one
  busy or replaced Node does not leave it cold.
  """
  def replicas(peak_concurrency, peer_count) when is_integer(peak_concurrency) and is_integer(peer_count) do
    (peak_concurrency + 1) |> max(@min_replicas) |> min(peer_count) |> max(0)
  end

  # Weighted rendezvous: weight / -ln(u), u uniform in (0, 1) per key and Node.
  defp score(key, node, weight) do
    <<hash::unsigned-64, _::binary>> = :crypto.hash(:sha256, [key, 0, node])
    u = (hash + 1) / 18_446_744_073_709_551_617
    weight / -:math.log(u)
  end
end
