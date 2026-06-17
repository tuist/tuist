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
  # Public Kura hostnames for every environment share the single
  # `*.kura.tuist.dev` Cloudflare zone. `{env_suffix}` is filled at runtime
  # (see `managed_region_host_suffix/0`): empty in production and
  # `-staging`/`-canary` elsewhere, so non-production deployments mint
  # distinct hostnames (e.g. `acme-eu-central-1-staging.kura.tuist.dev`).
  @managed_region_public_host_template "{account_handle}-{cluster_id}{env_suffix}.kura.tuist.dev"
  @managed_region_grpc_public_host_template "grpc.{account_handle}-{cluster_id}{env_suffix}.kura.tuist.dev"
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
  # Private runner-cache regions. They all share the same model: a single-
  # replica `KuraInstance` pinned to a specific node pool of the umbrella
  # cluster, exposed only as a `ClusterIP` Service (no public host, no
  # ingress, no certificate, no LoadBalancer). The runner pool reaches
  # the cache pod by Kubernetes Service DNS, so cache traffic never
  # leaves the cluster. The control plane provisions exactly one of
  # these per account that turns runners on (see `Tuist.Kura.RunnerCache`)
  # and the runner dispatch hands the URL back as `cache_endpoint_url`.
  #
  # Each environment reconciles `KuraInstance`s into its own workload
  # cluster (the provisioner uses the in-cluster Kubernetes API), so the
  # Hetzner regions differ only by `cluster_id`, which names the instance
  # (`kura-<handle>-<cluster_id>`) and audits placement. Every environment
  # pins to its `kura` node pool, co-located with the in-cluster Linux
  # runner fleet so cache traffic stays on the cluster network. The
  # Scaleway region is a separate, not-yet-activated target: its
  # `kura-scw-fr-par` pool lives in a different cluster than the Hetzner
  # runners, so it needs the dispatch-time cluster-locality check before
  # any runner can be handed its in-cluster URL.
  @private_region_specs [
    %{
      id: "scw-fr-par-runners",
      display_name: "Scaleway fr-par (runner cache)",
      cluster_id: "scw-fr-par",
      node_pool: "kura-scw-fr-par",
      storage_class: "scw-bssd",
      storage_size: "50Gi"
    },
    %{
      id: "hetzner-production-runners",
      display_name: "Hetzner production (runner cache)",
      cluster_id: "production",
      node_pool: "kura",
      storage_class: @managed_region_storage_class,
      storage_size: "20Gi"
    },
    %{
      id: "hetzner-canary-runners",
      display_name: "Hetzner canary (runner cache)",
      cluster_id: "canary",
      node_pool: "kura",
      storage_class: @managed_region_storage_class,
      storage_size: "20Gi"
    },
    %{
      id: "hetzner-staging-runners",
      display_name: "Hetzner staging (runner cache)",
      cluster_id: "staging",
      node_pool: "kura",
      storage_class: @managed_region_storage_class,
      storage_size: "20Gi"
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

  defp managed_regions do
    Enum.map(@managed_region_specs, &managed_region/1) ++
      Enum.map(@private_region_specs, &private_region/1)
  end

  defp managed_region(spec) do
    host_suffix = managed_region_host_suffix()

    %__MODULE__{
      id: spec.id,
      display_name: spec.display_name,
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: spec.cluster_id,
        hetzner_location: spec.hetzner_location,
        public_host_template: String.replace(@managed_region_public_host_template, "{env_suffix}", host_suffix),
        grpc_public_host_template: String.replace(@managed_region_grpc_public_host_template, "{env_suffix}", host_suffix),
        ingress_class_name: spec.ingress_class_name,
        storage_class: @managed_region_storage_class,
        tuist_base_url: Tuist.Environment.kura_tuist_base_url(),
        node_selector: %{@managed_region_node_pool_label => spec.node_pool},
        dedicated_gateway_account_handles: Tuist.Environment.kura_dedicated_gateway_account_handles()
      }
    }
  end

  # Environment suffix woven into managed-region public hostnames so the
  # ingress hosts, external-dns Cloudflare records, and cert-manager
  # certificates of staging/canary never collide with production. The
  # managed regions (e.g. `eu-central`) are exposed in every environment
  # and share a `cluster_id`, so without a per-environment suffix all three
  # would mint the identical hostname and fight over the same DNS record.
  defp managed_region_host_suffix do
    case Tuist.Environment.env() do
      :stag -> "-staging"
      :can -> "-canary"
      _ -> ""
    end
  end

  defp private_region(spec) do
    %__MODULE__{
      id: spec.id,
      display_name: spec.display_name,
      provisioner: KubernetesController,
      provisioner_config: %{
        cluster_id: spec.cluster_id,
        private: true,
        # In-cluster Service DNS the runner Pods resolve. `{instance}`
        # interpolates to `instance_name(handle, region)`.
        private_url_template: "http://{instance}.kura.svc.cluster.local:4000",
        node_selector: %{@managed_region_node_pool_label => spec.node_pool},
        storage_class: spec.storage_class,
        storage_size: spec.storage_size,
        replicas: 1,
        tuist_base_url: Tuist.Environment.kura_tuist_base_url()
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
