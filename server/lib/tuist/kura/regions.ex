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
  @managed_region_node_pool_label "node.cluster.x-k8s.io/pool"
  @managed_region_public_host_template "{account_handle}-{cluster_id}.kura.tuist.dev"
  @managed_region_grpc_public_host_template "grpc.{account_handle}-{cluster_id}.kura.tuist.dev"
  @managed_region_storage_class "hcloud-volumes"
  @managed_region_specs [
    %{
      id: "us-east",
      display_name: "US East",
      cluster_id: "us-east-1",
      hetzner_location: "ash",
      ingress_class_name: "kura-us-east",
      node_pool: "kura-us-east"
    },
    %{
      id: "us-west",
      display_name: "US West",
      cluster_id: "us-west-1",
      hetzner_location: "hil",
      ingress_class_name: "kura-us-west",
      node_pool: "kura-us-west"
    },
    %{
      id: "eu-central",
      display_name: "EU Central",
      cluster_id: "eu-central-1",
      hetzner_location: "fsn1",
      ingress_class_name: "kura-eu-central",
      node_pool: "kura"
    }
  ]

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

  defp managed_regions, do: Enum.map(@managed_region_specs, &managed_region/1)

  defp managed_region(spec) do
    %__MODULE__{
      id: spec.id,
      display_name: spec.display_name,
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: spec.cluster_id,
        hetzner_location: spec.hetzner_location,
        public_host_template: @managed_region_public_host_template,
        grpc_public_host_template: @managed_region_grpc_public_host_template,
        ingress_class_name: spec.ingress_class_name,
        storage_class: @managed_region_storage_class,
        tuist_base_url: Tuist.Environment.kura_tuist_base_url(),
        node_selector: %{@managed_region_node_pool_label => spec.node_pool},
        dedicated_gateway_account_handles: Tuist.Environment.kura_dedicated_gateway_account_handles()
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
