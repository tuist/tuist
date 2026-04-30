defmodule Tuist.Kura.Regions do
  @moduledoc """
  Catalog of regions where Kura meshes can run. The customer-facing
  unit of provisioning: an account picks one or more regions and the
  control plane spins up exactly one Kura mesh per region.

  A region carries:

    * `id` — stable opaque identifier (`"eu"`, `"us-east"`, `"local"`).
      Stored on `kura_servers.region`. Never renamed once published
      because URLs and `account_cache_endpoints` reference it.
    * `display_name` — what the /ops UI renders.
    * `provider` — the `Tuist.Kura.Provider` implementation that
      actually provisions, rolls, and destroys meshes here. The
      customer never sees this.
    * `provider_config` — opaque to the rest of the codebase; only the
      provider module reads it.

  Adding a region is a code change: edit `@catalog`, supply whatever
  provider config the chosen impl needs, deploy. Regions change rarely
  and provider configs reference assets that ship with the release.
  """

  alias Tuist.Kura.Provider.HelmKubernetes

  defstruct [:id, :display_name, :provider, :provider_config]

  @catalog [
    %{
      id: "eu",
      display_name: "Europe (Hetzner Falkenstein)",
      provider: HelmKubernetes,
      provider_config: %{
        cluster_id: "eu-1",
        helm_overlay: "hetzner",
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev"
      }
    },
    %{
      id: "local",
      display_name: "Local (kind)",
      provider: HelmKubernetes,
      provider_config: %{
        cluster_id: "local",
        helm_overlay: "local",
        kind_cluster_name: "kura-dev",
        public_url: "http://localhost:4000"
      }
    }
  ]

  @doc "All registered regions."
  def all, do: Enum.map(@catalog, &struct(__MODULE__, &1))

  @doc """
  Regions exposed in the current runtime environment. Dev/test sees
  only the local-provider regions so a developer can't accidentally
  provision into managed infrastructure.
  """
  def available do
    if Tuist.Environment.dev?() or Tuist.Environment.test?() do
      Enum.filter(all(), &(&1.id == "local"))
    else
      all()
    end
  end

  @doc "The region with the given ID, or `nil` if unknown."
  def get(id) when is_binary(id), do: Enum.find(all(), &(&1.id == id))
  def get(_), do: nil

  @doc "Same as `get/1` but raises if the region isn't registered."
  def get!(id) do
    case get(id) do
      nil -> raise ArgumentError, "unknown Kura region: #{inspect(id)}"
      region -> region
    end
  end

  @doc "True iff the given ID is in the catalog."
  def exists?(id) when is_binary(id), do: not is_nil(get(id))
  def exists?(_), do: false
end
