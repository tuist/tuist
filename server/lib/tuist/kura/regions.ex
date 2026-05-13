defmodule Tuist.Kura.Regions do
  @moduledoc """
  Catalog of regions where Kura servers can run. The customer-facing
  unit of provisioning: an account picks one or more regions and the
  control plane spins up exactly one Kura server per region.

  A region carries:

    * `id` — stable opaque identifier (`"eu-central"`, `"us-east"`,
      `"us-west"`, `"local-controller"`).
      Stored on `kura_servers.region`. Never renamed once published
      because URLs and `account_cache_endpoints` reference it.
    * `display_name` — the customer-facing region label.
    * `provisioner` — the `Tuist.Kura.Provisioner` implementation that
      actually provisions, rolls, and destroys Kura servers here. The
      customer never sees this.
    * `provisioner_config` — opaque to the rest of the codebase; only the
      provisioner module reads it.

  The local controller region is worktree-scoped via `TUIST_DEV_INSTANCE`:
  its kind cluster name and forwarded port are suffixed with the instance
  number so multiple worktrees can run side by side without colliding.
  """

  alias Tuist.Kura.Provisioner.KubernetesController

  defstruct [:id, :display_name, :provisioner, :provisioner_config]

  # The local controller region's kind cluster + forwarded port are derived from
  # `TUIST_DEV_INSTANCE` so each worktree is isolated. Worktree
  # instance N runs Kura on `kura-dev-N`.
  @local_controller_kura_base_port 4100

  @doc "All registered regions."
  def all, do: managed_regions() ++ [local_controller_region()]

  @doc """
  Regions exposed in the current runtime environment. Dev/test sees
  only the controller-backed local region so a developer can't
  accidentally provision into managed infrastructure. Managed runtimes
  expose only the region IDs enabled through
  `TUIST_KURA_AVAILABLE_REGIONS`.
  """
  def available do
    if Tuist.Environment.dev?() or Tuist.Environment.test?() do
      [local_controller_region()]
    else
      available_region_ids = MapSet.new(Tuist.Environment.kura_available_region_ids())

      Enum.filter(managed_regions(), &MapSet.member?(available_region_ids, &1.id))
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

  defp managed_regions, do: [us_east_region(), us_west_region(), eu_central_region()]

  defp us_east_region do
    %__MODULE__{
      id: "us-east",
      display_name: "US East",
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: "us-east-1",
        hetzner_location: "ash",
        kubernetes_client: [mode: :kubeconfig, cluster_id: "us-east-1"],
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        grpc_public_host_template: "grpc.{account_handle}-{cluster_id}.kura.tuist.dev",
        storage_class: "hcloud-volumes"
      }
    }
  end

  defp us_west_region do
    %__MODULE__{
      id: "us-west",
      display_name: "US West",
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: "us-west-1",
        hetzner_location: "hil",
        kubernetes_client: [mode: :kubeconfig, cluster_id: "us-west-1"],
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        grpc_public_host_template: "grpc.{account_handle}-{cluster_id}.kura.tuist.dev",
        storage_class: "hcloud-volumes"
      }
    }
  end

  defp eu_central_region do
    %__MODULE__{
      id: "eu-central",
      display_name: "EU Central",
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: "eu-central-1",
        hetzner_location: "fsn1",
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        grpc_public_host_template: "grpc.{account_handle}-{cluster_id}.kura.tuist.dev",
        storage_class: "hcloud-volumes"
      }
    }
  end

  defp local_controller_region do
    suffix = Tuist.Environment.dev_instance_suffix()

    %__MODULE__{
      id: "local-controller",
      display_name: "Local Controller (kind)",
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: "local-controller",
        kubeconfig_context: "kind-kura-dev-#{suffix}",
        kubernetes_client: [
          mode: :kubeconfig,
          kubeconfig_path: Path.expand("~/.kube/config"),
          context: "kind-kura-dev-#{suffix}"
        ],
        node_selector: %{"kubernetes.io/os" => "linux"},
        otlp_traces_endpoint: "http://127.0.0.1:4318/v1/traces",
        public_url: "http://localhost:#{@local_controller_kura_base_port + suffix}",
        replicas: 1,
        storage_size: "10Gi"
      }
    }
  end
end
