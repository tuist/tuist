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

  defp admit_with_capacity(%Regions{id: region_id} = region, candidate) do
    with target when is_integer(target) <- Capacity.pressure_line_gib(region_id),
         observed when is_integer(observed) <- Capacity.reserved_gib(region_id),
         desired when is_integer(desired) <- desired_reservation_gib(region),
         candidate_reservation when is_integer(candidate_reservation) <- Capacity.resident_gib(region, candidate) do
      if max(observed, desired) + candidate_reservation <= target do
        :ok
      else
        {:error, :capacity_exhausted}
      end
    else
      _ -> {:error, :capacity_unknown}
    end
  end

  defp admit_replacements_with_capacity(%Regions{id: region_id} = region, replacements) do
    with target when is_integer(target) <- Capacity.pressure_line_gib(region_id),
         observed when is_integer(observed) <- Capacity.reserved_gib(region_id),
         desired when is_integer(desired) <- desired_reservation_gib(region),
         adjustment when is_integer(adjustment) <- replacement_adjustment_gib(region, replacements) do
      if max(observed, desired + adjustment) <= target do
        :ok
      else
        {:error, :capacity_exhausted}
      end
    else
      _ -> {:error, :capacity_unknown}
    end
  end

  defp replacement_adjustment_gib(region, replacements) do
    Enum.reduce_while(replacements, 0, fn
      {%Server{region: current_region} = current, %Server{region: candidate_region} = candidate}, adjustment
      when current_region == candidate_region and current_region == region.id ->
        {:cont, adjustment + Capacity.resident_gib(region, candidate) - Capacity.resident_gib(region, current)}

      _replacement, _adjustment ->
        {:halt, nil}
    end)
  end

  # The Kubernetes reading is the source of truth for already-created pods,
  # but it cannot see a row that has committed before the controller creates its
  # pods. Keeping pending rows in this total closes that admission race.
  defp desired_reservation_gib(%Regions{id: region_id} = region) do
    Server
    |> where([server], server.region == ^region_id and server.status not in ^@volumeless_statuses)
    |> preload(account: [:subscriptions])
    |> Repo.all()
    |> Enum.reduce(0, fn server, total -> total + Capacity.resident_gib(region, server) end)
  end
end
