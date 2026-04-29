defmodule Tuist.Kura.Specs do
  @moduledoc """
  Catalog of Kura server specs (sizes). Each spec maps to a fixed
  resource overlay the rollout worker renders into the Helm values for
  the StatefulSet.

  Adding a spec is a code change: append to `@catalog`, deploy. Specs
  rarely change; the value in keeping them in code is that the dropdown
  the operator sees in /ops cannot be filled with arbitrary garbage.
  """

  defstruct [:id, :label, :cpu_request, :memory_request, :memory_limit, :default_volume_gi]

  @catalog [
    %{
      id: :small,
      label: "Small",
      cpu_request: "250m",
      memory_request: "512Mi",
      memory_limit: "1Gi",
      default_volume_gi: 50
    },
    %{
      id: :medium,
      label: "Medium",
      cpu_request: "500m",
      memory_request: "1.5Gi",
      memory_limit: "2Gi",
      default_volume_gi: 200
    },
    %{
      id: :large,
      label: "Large",
      cpu_request: "1000m",
      memory_request: "3Gi",
      memory_limit: "4Gi",
      default_volume_gi: 500
    }
  ]

  @doc "Every registered spec, as structs."
  def all, do: Enum.map(@catalog, &struct(__MODULE__, &1))

  @doc "Returns the spec for the given id (atom), or nil."
  def get(id) when is_atom(id), do: Enum.find(all(), &(&1.id == id))

  @doc "Default volume size for a given spec, used when the operator doesn't override."
  def default_volume_gi(id) when is_atom(id) do
    case get(id) do
      nil -> nil
      %__MODULE__{default_volume_gi: gi} -> gi
    end
  end

  @doc """
  Builds the Helm-values fragment (as a map) for the given spec's
  resource block. Embedded by the rollout worker into the per-instance
  values overlay it generates at deploy time.
  """
  def resource_overlay(id) when is_atom(id) do
    case get(id) do
      nil ->
        %{}

      %__MODULE__{cpu_request: cpu, memory_request: mem_req, memory_limit: mem_limit} ->
        %{
          "resources" => %{
            "requests" => %{"cpu" => cpu, "memory" => mem_req},
            "limits" => %{"memory" => mem_limit}
          }
        }
    end
  end
end
