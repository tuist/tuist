defmodule Tuist.Kura.Clusters do
  @moduledoc """
  Catalog of backing Kubernetes clusters that can host Kura meshes.

  A cluster has a stable opaque ID like `eu-1`, `us-east-1`. The region
  prefix is the only field exposed to accounts; provider and location
  are internal and may change without breaking any URL.

  Adding a cluster is a code change: edit `@catalog`, deploy. We chose
  this over a DB table because the cluster set changes rarely and CI
  workflows that touch infra (Helm overlays, kubeconfig secrets) are
  versioned alongside the code anyway.

  Each entry also names the Helm provider overlay we layer in for that
  cluster. The actual kubeconfig is fetched at deploy time from
  `Tuist.Kura.kubeconfig_for_cluster/1`, which reads from the encrypted
  secrets bundle baked into the release.
  """

  defstruct [:id, :region, :provider, :location]

  # Raw catalog — turned into structs lazily in `all/0` so the module
  # attribute does not need to reference its own struct at compile time.
  # `local-1` is always present so the /ops UI exposes a "deploy to my
  # local kind cluster" path in development. It is inert in production
  # because no kubeconfig is configured for it; the rollout worker
  # surfaces a clear error message in that case.
  @catalog [
    %{id: "eu-1", region: "eu", provider: "hetzner", location: "fsn1"},
    %{id: "local-1", region: "local", provider: "local", location: "kind"}
  ]

  @doc "Returns every registered cluster."
  def all do
    Enum.map(@catalog, &struct(__MODULE__, &1))
  end

  @doc "Returns the cluster with the given ID, or `nil`."
  def get(id) when is_binary(id) do
    Enum.find(all(), &(&1.id == id))
  end

  @doc "Returns true when the given cluster ID is in the catalog."
  def exists?(id) when is_binary(id) do
    not is_nil(get(id))
  end

  @doc """
  Builds the public URL for a (account, cluster) pair.

  This is the value stored in `account_cache_endpoints.url` and returned
  to the CLI via the `:kura` resolution path.
  """
  def public_url(account_handle, %__MODULE__{id: cluster_id})
      when is_binary(account_handle) do
    "https://#{account_handle}-#{cluster_id}.kura.tuist.dev"
  end

  @doc "Helm release name for a (account, cluster) pair."
  def release_name(account_handle, %__MODULE__{id: cluster_id})
      when is_binary(account_handle) do
    "kura-#{account_handle}-#{cluster_id}"
  end

  @doc "Path to the Helm provider overlay for this cluster."
  def provider_overlay_path(%__MODULE__{provider: provider}) do
    "kura/ops/helm/kura/values-managed-provider-#{provider}.yaml"
  end
end
