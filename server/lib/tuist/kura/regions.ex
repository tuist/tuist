defmodule Tuist.Kura.Regions do
  @moduledoc """
  Catalog of regions where Kura servers can run. The customer-facing
  unit of provisioning: an account picks one or more regions and the
  control plane spins up exactly one Kura server per region.

  A region carries:

    * `id` — stable opaque identifier (`"eu"`, `"us-east"`, `"local"`).
      Stored on `kura_servers.region`. Never renamed once published
      because URLs and `account_cache_endpoints` reference it.
    * `display_name` — what the /ops UI renders.
    * `provisioner` — the `Tuist.Kura.Provisioner` implementation that
      actually provisions, rolls, and destroys Kura servers here. The
      customer never sees this.
    * `provisioner_config` — opaque to the rest of the codebase; only the
      provisioner module reads it.

  The `local` region is worktree-scoped via `TUIST_DEV_INSTANCE`: its
  kind cluster name and forwarded port are suffixed with the instance
  number so multiple worktrees can run side by side without colliding.
  """

  alias Tuist.Kura.Provisioner.HelmKubernetes

  defstruct [:id, :display_name, :provisioner, :provisioner_config]

  # The local region's kind cluster + forwarded port are derived from
  # `TUIST_DEV_INSTANCE` so each worktree is isolated. Worktree
  # instance N runs Kura on `kura-dev-N` and exposes it at
  # `localhost:(4000+N)`.
  @local_kura_base_port 4000

  @doc "All registered regions."
  def all, do: [eu_region(), local_region()]

  @doc """
  Regions exposed in the current runtime environment. Dev/test sees
  only the local region so a developer can't accidentally provision
  into managed infrastructure.
  """
  def available do
    if Tuist.Environment.dev?() or Tuist.Environment.test?() do
      [local_region()]
    else
      [eu_region()]
    end
  end

  @doc "The region with the given ID in the current runtime, or `nil` if unavailable."
  def available_region(id) when is_binary(id), do: Enum.find(available(), &(&1.id == id))
  def available_region(_), do: nil

  @doc "True iff the given ID is available in the current runtime."
  def available?(id) when is_binary(id), do: not is_nil(available_region(id))
  def available?(_), do: false

  @doc "The region with the given ID, or `nil` if unknown."
  def get(id) when is_binary(id), do: Enum.find(all(), &(&1.id == id))
  def get(_), do: nil

  @doc "Tagged-tuple variant of `get/1`."
  def fetch(id) do
    case get(id) do
      nil -> {:error, :not_found}
      region -> {:ok, region}
    end
  end

  @doc "True iff the given ID is in the catalog."
  def exists?(id) when is_binary(id), do: not is_nil(get(id))
  def exists?(_), do: false

  defp eu_region do
    %__MODULE__{
      id: "eu",
      display_name: "Europe (Hetzner Falkenstein)",
      provisioner: HelmKubernetes,
      provisioner_config: %{
        cluster_id: "eu-1",
        helm_overlay: "hetzner",
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        tenant_isolation: true
      }
    }
  end

  defp local_region do
    suffix = Tuist.Environment.dev_instance_suffix()

    %__MODULE__{
      id: "local",
      display_name: "Local (kind)",
      provisioner: HelmKubernetes,
      provisioner_config: %{
        cluster_id: "local",
        helm_overlay: "local",
        kind_cluster_name: "kura-dev-#{suffix}",
        public_url: "http://localhost:#{@local_kura_base_port + suffix}"
      }
    }
  end
end
