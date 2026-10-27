defmodule Tuist.Kura.Admission do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  # A two-part advisory lock leaves this namespace isolated from the other
  # transactional locks in the application. The region is the second key, so
  # capacity admission serializes only work competing for the same nodes.
  @advisory_lock_namespace 1_285_447_893
  @volumeless_statuses [:destroying, :destroyed, :archived]

  def lock(%Regions{id: region_id}) do
    if Environment.kura_capacity_admission_required?() do
      lock_region(region_id)
    else
      :ok
    end
  end

  def lock_regions(region_ids) when is_list(region_ids) do
    if Environment.kura_capacity_admission_required?() do
      region_ids
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reduce_while(:ok, fn region_id, :ok ->
        case lock_region(region_id) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    else
      :ok
    end
  end

  def admit?(%Regions{} = region, %Server{} = candidate) do
    if Environment.kura_capacity_admission_required?() do
      admit_with_capacity(region, candidate)
    else
      :ok
    end
  end

  @doc """
  Gibibytes the region can still admit: `:unbounded` when admission is not
  enforced, `nil` when the region cannot be read, which `admit?/2` refuses.
  """
  def headroom_gib(%Regions{} = region) do
    if Environment.kura_capacity_admission_required?() do
      measured_headroom_gib(region)
    else
      :unbounded
    end
  end

  def admit_replacements?(%Regions{} = region, replacements) when is_list(replacements) do
    if Environment.kura_capacity_admission_required?() do
      admit_replacements_with_capacity(region, replacements)
    else
      :ok
    end
  end

  defp lock_region(region_id) do
    case Repo.query("SELECT pg_advisory_xact_lock($1::integer, hashtext($2))", [@advisory_lock_namespace, region_id]) do
      {:ok, _result} -> :ok
      {:error, _reason} -> {:error, :capacity_lock_failed}
    end
  end

  defp admit_with_capacity(%Regions{} = region, candidate) do
    with headroom when is_integer(headroom) <- measured_headroom_gib(region),
         candidate_reservation when is_integer(candidate_reservation) <- Capacity.resident_gib(region, candidate) do
      cond do
        candidate_reservation > headroom -> {:error, :capacity_exhausted}
        unplaceable?(region, [candidate]) -> {:error, :capacity_unplaceable}
        true -> :ok
      end
    else
      _ -> {:error, :capacity_unknown}
    end
  end

  defp measured_headroom_gib(%Regions{id: region_id} = region) do
    with target when is_integer(target) <- Capacity.pressure_line_gib(region_id),
         reserved when is_integer(reserved) <- reserved_gib(region, desired_reservations(region)) do
      target - reserved
    else
      _ -> nil
    end
  end

  defp admit_replacements_with_capacity(%Regions{id: region_id} = region, replacements) do
    with target when is_integer(target) <- Capacity.pressure_line_gib(region_id),
         desired when is_map(desired) <- replace_reservations(region, desired_reservations(region), replacements),
         reserved when is_integer(reserved) <- reserved_gib(region, desired) do
      cond do
        reserved > target -> {:error, :capacity_exhausted}
        unplaceable?(region, Enum.map(replacements, &elem(&1, 1))) -> {:error, :capacity_unplaceable}
        true -> :ok
      end
    else
      _ -> {:error, :capacity_unknown}
    end
  end

  # The region totals above are a sum against a sum, and the scheduler places
  # each replica whole on one node, so passing them is not the same as fitting.
  # Separate from `:capacity_exhausted` because the two need opposite responses:
  # an exhausted region needs another machine, an unplaceable instance needs
  # the room it has to be on the right box.
  #
  # Only a reading that says no refuses. One that is merely missing admits,
  # because a false refusal here stops every claim growth in the region and
  # shows up nowhere the account would notice.
  defp unplaceable?(region, candidates) do
    Enum.any?(candidates, &(Capacity.placeable?(region, &1) == false))
  end

  defp replace_reservations(region, desired, replacements) do
    Enum.reduce_while(replacements, desired, fn
      {%Server{region: current_region} = current, %Server{region: candidate_region} = candidate}, desired
      when current_region == candidate_region and current_region == region.id ->
        {:cont, Map.put(desired, instance_key(current), Capacity.resident_gib(region, candidate))}

      _replacement, _desired ->
        {:halt, nil}
    end)
  end

  # Each instance counts once, at the larger of what its pods request and what
  # its row reserves. The pods are the source of truth for what already runs,
  # but cannot see a row committed before the controller creates its pods; the
  # rows cannot see pods whose row is gone, such as an instance left behind by
  # a deleted account.
  defp reserved_gib(%Regions{id: region_id}, desired) do
    case Capacity.reserved_gib_by_instance(region_id) do
      observed when is_map(observed) ->
        observed
        |> Map.merge(desired, fn _instance, observed_gib, desired_gib -> max(observed_gib, desired_gib) end)
        |> Map.values()
        |> Enum.sum()

      nil ->
        nil
    end
  end

  defp desired_reservations(%Regions{id: region_id} = region) do
    Server
    |> where([server], server.region == ^region_id and server.status not in ^@volumeless_statuses)
    |> preload(account: [:subscriptions])
    |> Repo.all()
    |> Enum.reduce(%{}, fn server, desired ->
      Map.update(
        desired,
        instance_key(server),
        Capacity.resident_gib(region, server),
        &(&1 + Capacity.resident_gib(region, server))
      )
    end)
  end

  # A row's pods carry its `provisioner_node_ref` as their instance. A row
  # without one has no pods to match, so it stands on its own.
  defp instance_key(%Server{provisioner_node_ref: ref}) when is_binary(ref), do: ref
  defp instance_key(%Server{id: id}), do: {:server, id}
end
