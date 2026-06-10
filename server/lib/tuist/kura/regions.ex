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

  @doc """
  Regions a customer may explicitly select in the UI. This is
  `available/0` minus regions the control plane manages on the
  customer's behalf (the private runner-cache regions, which are
  provisioned automatically when an account turns on runners and are
  reachable only over the cluster's internal DNS — there is no public
  endpoint for a developer to point the CLI at). `create_server/1`
  still accepts these regions through `available/0`; they're only
  hidden from the picker.
  """
  def selectable, do: Enum.reject(available(), &private?/1)

  @doc """
  True iff the region has no public endpoint and is reachable only over
  the cluster's internal DNS (today: the runner-cache regions, which
  serve the in-cluster runner fleet). Private regions are managed by
  the control plane rather than picked by customers, skip the public
  DNS/HTTPS readiness probe at activation, and never mirror their URL
  into `account_cache_endpoints` (CLI-facing; developer machines can't
  reach the in-cluster endpoint).
  """
  def private?(%__MODULE__{provisioner_config: config}), do: config[:private] == true
  def private?(_), do: false

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

  defp managed_regions,
    do: [
      us_east_region(),
      us_west_region(),
      eu_central_region(),
      scaleway_runners_region(),
      hetzner_staging_runners_region()
    ]

  # Private runner-cache regions. Both share the same model: a single-
  # replica `KuraInstance` pinned to a specific node pool of the umbrella
  # cluster, exposed only as a `ClusterIP` Service (no public host, no
  # ingress, no certificate, no LoadBalancer). The runner pool reaches
  # the cache pod by Kubernetes Service DNS, so cache traffic never
  # leaves the cluster. The control plane provisions exactly one of
  # these per account that turns runners on (see `Tuist.Kura.RunnerCache`)
  # and the runner dispatch hands the URL back as `cache_endpoint_url`.

  defp scaleway_runners_region do
    %__MODULE__{
      id: "scw-fr-par-runners",
      display_name: "Scaleway fr-par (runner cache)",
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: "scw-fr-par",
        private: true,
        # In-cluster Service DNS the runner Pods resolve. `{instance}`
        # interpolates to `instance_name(handle, region)`.
        private_url_template: "http://{instance}.kura.svc.cluster.local:4000",
        node_selector: %{"node.cluster.x-k8s.io/pool" => "kura-scw-fr-par"},
        storage_class: "scw-bssd",
        storage_size: "50Gi",
        replicas: 1,
        tuist_base_url: Tuist.Environment.kura_tuist_base_url()
      }
    }
  end

  defp hetzner_staging_runners_region do
    %__MODULE__{
      id: "hetzner-staging-runners",
      display_name: "Hetzner staging (runner cache)",
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: "staging",
        private: true,
        private_url_template: "http://{instance}.kura.svc.cluster.local:4000",
        node_selector: %{"node.cluster.x-k8s.io/pool" => "kura"},
        storage_class: "hcloud-volumes",
        storage_size: "20Gi",
        replicas: 1,
        tuist_base_url: Tuist.Environment.kura_tuist_base_url()
      }
    }
  end

  defp us_east_region do
    %__MODULE__{
      id: "us-east",
      display_name: "US East",
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: "us-east-1",
        hetzner_location: "ash",
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        grpc_public_host_template: "grpc.{account_handle}-{cluster_id}.kura.tuist.dev",
        ingress_class_name: "kura-us-east",
        storage_class: "hcloud-volumes",
        tuist_base_url: Tuist.Environment.kura_tuist_base_url(),
        node_selector: %{"node.cluster.x-k8s.io/pool" => "kura-us-east"},
        dedicated_gateway_account_handles: Tuist.Environment.kura_dedicated_gateway_account_handles()
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
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        grpc_public_host_template: "grpc.{account_handle}-{cluster_id}.kura.tuist.dev",
        ingress_class_name: "kura-us-west",
        storage_class: "hcloud-volumes",
        tuist_base_url: Tuist.Environment.kura_tuist_base_url(),
        node_selector: %{"node.cluster.x-k8s.io/pool" => "kura-us-west"},
        dedicated_gateway_account_handles: Tuist.Environment.kura_dedicated_gateway_account_handles()
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
        ingress_class_name: "kura-eu-central",
        storage_class: "hcloud-volumes",
        tuist_base_url: Tuist.Environment.kura_tuist_base_url(),
        node_selector: %{"node.cluster.x-k8s.io/pool" => "kura"},
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
