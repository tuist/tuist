defmodule Tuist.Kura.Specs do
  @moduledoc """
  Customer-facing Kura server size catalog.

  A spec is a label and a rough capacity description. It is **not** a
  Kubernetes resources block, an instance type, or a volume size. The
  provisioner for a region translates `(spec, volume_size_gi)` into
  whatever its platform actually needs:

    * On Kubernetes (`HelmKubernetes`), the spec maps to Pod CPU and
      memory requests/limits and the volume to a PVC size.
    * On a future bare-metal provisioner (Hetzner Dedicated, Vultr, …),
      the same spec would map to an instance type and the volume to
      a separately-attached block volume.

  Adding a spec is a code change: append to `@catalog`, deploy. The
  list is the dropdown the operator sees in /ops, so the labels are
  the customer-facing source of truth.
  """

  defstruct [:id, :label, :description, :default_volume_gi, :bandwidth]

  # Per-spec ingress/egress bandwidth limits applied as Cilium-honored
  # pod annotations on the StatefulSet. Starting points sized for a
  # 1 Gbps Hetzner AX NIC with light oversubscription; revisit once we
  # have load data.
  @catalog [
    %{
      id: :small,
      label: "Small",
      description: "Single small team, ~4 GB hot working set",
      default_volume_gi: 50,
      bandwidth: %{ingress: "100M", egress: "100M"}
    },
    %{
      id: :medium,
      label: "Medium",
      description: "Mid-size team, ~16 GB hot working set, ~50 K artifacts",
      default_volume_gi: 200,
      bandwidth: %{ingress: "250M", egress: "250M"}
    },
    %{
      id: :large,
      label: "Large",
      description: "Busy CI fleet, ~64 GB hot working set",
      default_volume_gi: 500,
      bandwidth: %{ingress: "500M", egress: "500M"}
    }
  ]

  @doc "Every registered spec, as structs."
  def all, do: Enum.map(@catalog, &struct(__MODULE__, &1))

  @doc "Returns the spec for the given id (atom), or nil."
  def get(id) when is_atom(id), do: Enum.find(all(), &(&1.id == id))

  @doc """
  Recommended default volume size for a spec. Just a hint the /ops
  form pre-fills; operators can override.
  """
  def default_volume_gi(id) when is_atom(id) do
    case get(id) do
      nil -> nil
      %__MODULE__{default_volume_gi: gi} -> gi
    end
  end

  @doc """
  Bandwidth caps for a spec, as `{ingress, egress}` strings consumable
  by Cilium's `kubernetes.io/{ingress,egress}-bandwidth` pod
  annotations. Returns `nil` for unknown specs.
  """
  def bandwidth(id) when is_atom(id) do
    case get(id) do
      nil -> nil
      %__MODULE__{bandwidth: bw} -> bw
    end
  end
end
