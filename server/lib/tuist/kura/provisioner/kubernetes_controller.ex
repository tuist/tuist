defmodule Tuist.Kura.Provisioner.KubernetesController do
  @moduledoc """
  Submits desired Kura endpoint state as `KuraInstance` custom resources.

  The Go controller in `infra/kura-controller` owns the actual StatefulSet,
  Kura ingress, and internal peer Service reconciliation; the customer plane is
  fronted by a shared regional ingress (host-network on bare metal, LB-fronted on
  cloud), not a per-account gateway. This provisioner is only the bridge from
  Tuist's account model to the CRDs.
  """

  @behaviour Tuist.Kura.Provisioner

  alias Tuist.Billing.Entitlements
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Mesh
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  @namespace "kura"
  @manifest_revision "2026-07-02-per-account-public-dns-v1"
  @manifest_revision_annotation "tuist.dev/kura-manifest-revision"
  @impl true
  def provision(%{name: handle}, %Regions{} = region, %Server{}) do
    {:ok, instance_name(handle, region)}
  end

  @impl true
  def rollout(
        name,
        %{image_tag: image_tag, account: account, server: %Server{} = server, region: %Regions{} = region} = inputs
      ) do
    with {:ok, hook_script} <- hook_script(inputs) do
      external_peers = self_hosted_peers(account, region)

      case apply_manifests(
             [manifest(name, image_tag, account, region, server, hook_script, external_peers)],
             region
           ) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def destroy(name, %Regions{} = region) do
    case client_delete_kura_instance(@namespace, name, region) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def public_url(handle, %Regions{provisioner_config: config} = region, _ref) do
    cond do
      template = config[:public_host_template] ->
        "https://" <> interpolate_host(template, dns_handle(handle), config)

      url = config[:public_url] ->
        url

      template = config[:private_url_template] ->
        # Private region: build the in-cluster Service DNS URL. The
        # KuraInstance's primary Service is named after instance_name(),
        # which `{instance}` interpolates to.
        interpolate_private_url(template, handle, region)

      true ->
        raise ArgumentError,
              "region #{inspect(config[:cluster_id])} has neither :public_host_template, :public_url, nor :private_url_template"
    end
  end

  defp interpolate_private_url(template, handle, %Regions{provisioner_config: config} = region) do
    template
    |> String.replace("{instance}", instance_name(handle, region))
    |> String.replace("{account_handle}", dns_handle(handle))
    |> String.replace("{cluster_id}", config[:cluster_id] || "")
  end

  @impl true
  def grpc_public_url(handle, %Regions{provisioner_config: config}, _ref) do
    cond do
      template = config[:grpc_public_host_template] ->
        "grpcs://" <> interpolate_host(template, dns_handle(handle), config)

      url = config[:grpc_public_url] ->
        url

      true ->
        nil
    end
  end

  @impl true
  # The instance's Service is named after `provisioner_node_ref`
  # (`rollout/2` sets `metadata.name = ref`), which diverges from
  # `instance_name/2` after a warm-handoff move (`-m` suffix) — so the
  # ref, not the handle, is the source of truth for the in-cluster name.
  def internal_url(_handle, %Regions{provisioner_config: config}, ref) when is_binary(ref) do
    case config[:private_url_template] do
      template when is_binary(template) -> String.replace(template, "{instance}", ref)
      _ -> nil
    end
  end

  @impl true
  def current_image_tag(name, %Regions{} = region) do
    case client_get_kura_instance(@namespace, name, region) do
      {:ok, %{"status" => %{"observedImage" => image}}} -> {:ok, image_tag_from_image(image)}
      {:ok, _} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The node-published URL a runner off the pod network dials:
  `http://<node PN address>:<NodePort>`, from the KuraInstance status
  the kura-controller maintains (node label + allocated Service port).
  `{:error, :node_port_endpoint_not_ready}` until the whole chain —
  Service allocated, primary pod placed, node labeled — is observed;
  callers treat it like an unready public endpoint and retry on the
  next reconcile tick.
  """
  @impl true
  def external_endpoint(name, %Regions{} = region) do
    case client_get_kura_instance(@namespace, name, region) do
      {:ok, %{"status" => %{"nodeAddress" => address} = status}} when is_binary(address) and address != "" ->
        # nodePortHTTP is the pre-rename name of nodePortCache, read as a
        # fallback while controllers that publish it can still be running;
        # drop it once the fleet publishes nodePortCache everywhere (tracked in #11654).
        port = status["nodePortCache"] || status["nodePortHTTP"]

        if is_integer(port) and port > 0 do
          {:ok, "http://#{address}:#{port}"}
        else
          {:error, :node_port_endpoint_not_ready}
        end

      {:ok, _} ->
        {:error, :node_port_endpoint_not_ready}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def caught_up?(name, %Regions{} = region) do
    case client_get_kura_instance(@namespace, name, region) do
      {:ok, %{"status" => %{"phase" => "Ready"}}} -> {:ok, true}
      {:ok, _} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def current_manifest_revision(name, %Regions{} = region) do
    case client_get_kura_instance(@namespace, name, region) do
      {:ok, %{"metadata" => %{"annotations" => %{@manifest_revision_annotation => revision}}}} -> {:ok, revision}
      {:ok, _} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def manifest_revision(account, %Regions{} = region) do
    @manifest_revision <> peers_revision_suffix(self_hosted_peers(account, region))
  end

  @doc "The base manifest revision, independent of dynamic per-account inputs."
  def manifest_revision, do: @manifest_revision

  @impl true
  def resources_for(%Server{}), do: %{}

  def instance_name(handle, %Regions{provisioner_config: %{cluster_id: cluster_id}}) do
    "kura-#{dns_handle(handle)}-#{cluster_id}"
  end

  @doc false
  def image_tag_from_image(image) when is_binary(image) do
    image
    |> String.trim()
    |> String.split("/", trim: true)
    |> List.last()
    |> image_tag_from_last_path_segment()
  end

  defp image_tag_from_last_path_segment(nil), do: nil

  defp image_tag_from_last_path_segment(segment) do
    segment
    |> String.split("@", parts: 2)
    |> List.first()
    |> String.split(":", parts: 2)
    |> case do
      [_image, tag] when tag != "" -> tag
      _ -> nil
    end
  end

  @doc false
  def manifest(name, image_tag, account, %Regions{} = region, %Server{} = server, hook_script, external_peers \\ []) do
    account_handle = dns_handle(account.name)
    revision = @manifest_revision <> peers_revision_suffix(external_peers)
    annotations = %{@manifest_revision_annotation => revision}

    %{
      "apiVersion" => "kura.tuist.dev/v1alpha1",
      "kind" => "KuraInstance",
      "metadata" => %{
        "name" => name,
        "namespace" => @namespace,
        "annotations" => annotations,
        "labels" => %{
          "app.kubernetes.io/name" => "kura",
          "app.kubernetes.io/instance" => name,
          "tuist.dev/account" => account_handle,
          "tuist.dev/region" => region.id
        }
      },
      "spec" =>
        %{
          "accountHandle" => account_handle,
          "tenantID" => account_handle,
          "region" => region.id,
          "image" => "ghcr.io/tuist/kura:#{image_tag}",
          # Only the steady-state (`:none`) server owns the account's customer
          # host. A `:moving_in` target warms with the customer plane withheld
          # (peer plane only, so it bootstraps from the source without two
          # instances claiming the same host), and a `:moving_out` source has
          # already handed the host to the promoted target. The kura-controller
          # leaves the public Ingress/DNS/Certificate unreconciled for an empty
          # publicHost, so host ownership stays with exactly one instance.
          "publicHost" => if(owns_customer_host?(server), do: public_host(account_handle, region)),
          "grpcPublicHost" => if(owns_customer_host?(server), do: grpc_public_host(account_handle, region)),
          "ingressClassName" => ingress_class_name(region),
          "publicHostNetwork" => public_host_network?(region),
          "peerTLSSecretName" => peer_tls_secret_name(region),
          "mesh" => mesh_enabled?(region),
          "meshPublicPeerHost" => mesh_public_peer_host(account_handle, region),
          "meshExternalPeers" => mesh_external_peers(region, external_peers),
          "meshPublicPeerLoadBalancerAnnotations" => mesh_public_peer_lb_annotations(region),
          "meshPeerHostNetwork" => mesh_peer_host_network?(region),
          "meshPeerFailoverIp" => mesh_peer_failover_ip(region),
          "private" => Regions.private?(region),
          "exposeNodePort" => Regions.node_port_data_plane?(region),
          "clientCIDRs" => client_cidrs(region),
          "podAnnotations" => pod_annotations(region),
          "egressGuaranteedMbps" => egress_guaranteed_mbps(account, region),
          "storageClassName" => storage_class(region),
          "storageSize" => storage_size(region),
          "replicas" => replicas(region),
          "nodeSelector" => instance_node_selector(region, server),
          "tolerations" => tolerations(region),
          "extensionScript" => hook_script,
          "extraEnv" => extension_env(region)
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, "", false] end)
        |> Map.new()
    }
  end

  defp public_host(handle, %Regions{provisioner_config: %{public_host_template: template} = config}) do
    interpolate_host(template, dns_handle(handle), config)
  end

  defp public_host(_handle, _region), do: nil

  # The customer gateway is host-network exactly when the regional gateway is:
  # on bare metal there is no cloud LB, so the customer plane is served by the
  # host-network gateway DaemonSet on the box NIC. Tells the controller to
  # publish the account's public host via a per-account DNSEndpoint targeting the
  # box its pods run on, so each account resolves to its own box across a
  # multi-box region. Skipped on private (runner-cache) regions, which have no
  # public host to advertise.
  defp public_host_network?(region) do
    gateway_host_network?(region) and not Regions.private?(region)
  end

  defp grpc_public_host(handle, %Regions{provisioner_config: %{grpc_public_host_template: template} = config}) do
    interpolate_host(template, dns_handle(handle), config)
  end

  defp grpc_public_host(_handle, _region), do: nil

  defp ingress_class_name(%Regions{provisioner_config: %{ingress_class_name: ingress_class_name}})
       when is_binary(ingress_class_name) and ingress_class_name != "", do: ingress_class_name

  defp ingress_class_name(_region), do: nil

  defp peer_tls_secret_name(%Regions{provisioner_config: %{peer_tls_secret_name: secret_name}})
       when is_binary(secret_name) and secret_name != "", do: secret_name

  defp peer_tls_secret_name(_region), do: nil

  defp mesh_enabled?(%Regions{provisioner_config: %{mesh: mesh}}) when is_boolean(mesh), do: mesh
  defp mesh_enabled?(_region), do: false

  defp self_hosted_peers(account, %Regions{} = region) do
    (mesh_enabled?(region) && Mesh.self_hosted_peer_urls(account)) || []
  end

  # Folded into the manifest revision so enrolling or dropping a self-hosted
  # peer changes the desired revision and the reconciler re-applies the manifest.
  defp peers_revision_suffix([]), do: ""

  defp peers_revision_suffix(peer_urls) when is_list(peer_urls) do
    digest =
      peer_urls
      |> Enum.sort()
      |> Enum.join(",")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "+peers-" <> digest
  end

  defp mesh_public_peer_host(handle, region) do
    if mesh_enabled?(region), do: Regions.peer_public_host(handle, region)
  end

  defp mesh_external_peers(region, external_peers) do
    case mesh_enabled?(region) && external_peers do
      [_ | _] = urls -> urls
      _ -> nil
    end
  end

  # Targeting annotations for the public peer LoadBalancer: pin it to the
  # region's hcloud location and restrict its targets to the account's node pool
  # (otherwise the cloud controller targets every node, including ones that
  # can't route to the account's pods). Mirrors the gateway LoadBalancer.
  defp mesh_public_peer_lb_annotations(%Regions{provisioner_config: config} = region) do
    location = Map.get(config, :hetzner_location)

    if mesh_enabled?(region) and is_binary(location) and location != "" do
      annotations = %{"load-balancer.hetzner.cloud/location" => location}

      case node_selector_annotation(region) do
        nil -> annotations
        selector -> Map.put(annotations, "load-balancer.hetzner.cloud/node-selector", selector)
      end
    end
  end

  # The peer plane is host-network exactly when the regional gateway is: on
  # bare metal there is no cloud LB, so the public peer endpoint is served by a
  # host-network SNI-passthrough demux on the box NIC instead of a per-instance
  # LoadBalancer. Tells the controller to make the per-instance peer Service
  # ClusterIP and publish DNS via a DNSEndpoint to the region's failover IP.
  defp mesh_peer_host_network?(region) do
    mesh_enabled?(region) and gateway_host_network?(region)
  end

  # The region's public peer failover IP that the host-network peer DNSEndpoint
  # targets. nil (dropped) on the Hetzner LB regions or when none is configured.
  defp mesh_peer_failover_ip(region) do
    if mesh_peer_host_network?(region), do: Map.get(region.provisioner_config, :failover_ip)
  end

  defp node_selector_annotation(region) do
    case node_selector(region) do
      %{} = selector when map_size(selector) > 0 ->
        Enum.map_join(selector, ",", fn {key, value} -> "#{key}=#{value}" end)

      _ ->
        nil
    end
  end

  # Tuist-platform-wide secrets (JWT verifier, control-plane client
  # secret) are
  # mounted into the Kura pod from the shared kura-shared-secrets
  # Secret in the kura namespace, not embedded in the KuraInstance
  # spec. Anyone with list/watch on kurainstances can read its spec, so
  # putting global credentials there would leak them to every account
  # that ever runs Kura. The controller's envFrom on the StatefulSet
  # picks up that Secret automatically. Non-secret knobs such as the
  # introspection client ID are safe to keep in the spec.
  defp extension_env(%Regions{} = region) do
    [
      env_var("KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE", "true"),
      env_var("KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE", "true"),
      env_var("KURA_EXTENSION_HOOK_TIMEOUT_MS", "5000"),
      env_var("KURA_CONTROL_PLANE_URL", tuist_base_url(region)),
      env_var("KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL", tuist_base_url(region)),
      env_var("KURA_EXTENSION_HTTP_CLIENT_TUIST_CONNECT_TIMEOUT_MS", "3000"),
      env_var("KURA_EXTENSION_HTTP_CLIENT_TUIST_REQUEST_TIMEOUT_MS", "4000")
    ] ++
      maybe_env_var(
        "KURA_CONTROL_PLANE_CLIENT_ID",
        Environment.kura_control_plane_client_id()
      ) ++
      telemetry_env(region)
  end

  defp telemetry_env(%Regions{provisioner_config: %{otlp_traces_endpoint: endpoint}})
       when is_binary(endpoint) and endpoint != "" do
    [env_var("KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", endpoint)]
  end

  defp telemetry_env(_), do: []

  defp env_var(name, value), do: %{"name" => name, "value" => value}
  defp maybe_env_var(_name, nil), do: []
  defp maybe_env_var(_name, ""), do: []
  defp maybe_env_var(name, value), do: [env_var(name, value)]

  defp tuist_base_url(%Regions{id: "local-controller"}) do
    Environment.app_url()
    |> URI.parse()
    |> rewrite_loopback("host.docker.internal")
    |> URI.to_string()
  end

  defp tuist_base_url(%Regions{provisioner_config: %{tuist_base_url: url}}) when is_binary(url) and url != "", do: url

  defp tuist_base_url(_), do: Environment.app_url()

  defp rewrite_loopback(%URI{host: host} = uri, replacement) when host in ["localhost", "127.0.0.1", "0.0.0.0"] do
    %{uri | host: replacement}
  end

  defp rewrite_loopback(uri, _), do: uri

  defp storage_class(%Regions{provisioner_config: %{storage_class: storage_class}}), do: storage_class

  defp storage_class(_), do: nil

  defp storage_size(%Regions{provisioner_config: %{storage_size: storage_size}}), do: storage_size
  defp storage_size(_), do: nil

  defp replicas(%Regions{provisioner_config: %{replicas: replicas}}), do: replicas
  defp replicas(_), do: nil

  defp node_selector(%Regions{provisioner_config: %{node_selector: node_selector}}), do: node_selector

  defp node_selector(_), do: nil

  # Only the steady-state (`:none`) server publishes the account's customer host.
  # See the `publicHost` gating in `manifest/8`.
  defp owns_customer_host?(%Server{move_phase: :moving_in}), do: false
  defp owns_customer_host?(%Server{move_phase: :moving_out}), do: false
  defp owns_customer_host?(%Server{}), do: true

  # A `:moving_in` target is pinned to the destination box (its `target_node`)
  # so the warm handoff lands the account on the intended box, layered on top of
  # the region's pool `node_selector`. Every other row is placed by the
  # scheduler's egress/cpu bin-packing across the region's boxes.
  defp instance_node_selector(region, %Server{move_phase: :moving_in, target_node: node})
       when is_binary(node) and node != "" do
    region
    |> node_selector()
    |> Kernel.||(%{})
    |> Map.put("kubernetes.io/hostname", node)
  end

  defp instance_node_selector(region, %Server{}), do: node_selector(region)

  defp tolerations(%Regions{provisioner_config: %{tolerations: [_ | _] = tolerations}}), do: tolerations

  defp tolerations(_), do: nil

  # nil (not []) when unset so the manifest builder's reject drops the
  # key entirely.
  defp client_cidrs(%Regions{provisioner_config: %{client_cidrs: [_ | _] = cidrs}}), do: cidrs
  defp client_cidrs(_), do: nil

  defp pod_annotations(%Regions{provisioner_config: %{pod_annotations: annotations}})
       when is_map(annotations) and map_size(annotations) > 0, do: annotations

  defp pod_annotations(_), do: nil

  # Guaranteed egress floor: the region's per-tenant Mbps reserved as the
  # tuist.dev/egress-mbps extended resource so the scheduler bin-packs the pod
  # against the node's advertised budget. Enterprise-only — the default pattern
  # is bursty, so non-enterprise tenants run best-effort under the Cilium burst
  # ceiling alone and pack densely. nil (dropped) when the region has no floor or
  # the account isn't entitled.
  defp egress_guaranteed_mbps(account, %Regions{provisioner_config: %{egress_guaranteed_mbps: mbps}})
       when is_integer(mbps) and mbps > 0 do
    if Entitlements.allows?(account, :guaranteed_egress_floor), do: mbps
  end

  defp egress_guaranteed_mbps(_account, _region), do: nil

  # Whether the region's shared gateway runs host-network (directly on the
  # bare-metal box NIC) rather than as an LB-fronted controller. Drives the
  # customer- and peer-plane host-network signals on the KuraInstance.
  defp gateway_host_network?(%Regions{provisioner_config: %{gateway: :host_network}}), do: true
  defp gateway_host_network?(_region), do: false

  defp apply_manifests(manifests, region) do
    manifests
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while(:ok, fn manifest, :ok ->
      case client_apply(manifest, region) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp interpolate_host(template, handle, %{cluster_id: cluster_id}) do
    template
    |> String.replace("{account_handle}", handle)
    |> String.replace("{cluster_id}", cluster_id)
  end

  defp dns_handle(handle), do: String.downcase(handle)

  defp hook_script(inputs) do
    case Map.get(inputs, :hook_script) do
      script when is_binary(script) ->
        {:ok, script}

      nil ->
        hook_script_from_runtime()
    end
  end

  # Hook script is the same for every rollout in a given release, so we
  # read it once and keep it in :persistent_term to avoid disk I/O on
  # every reconciler tick. Cleared automatically when the BEAM is
  # restarted (release upgrade, pod replacement) so a chart change to
  # the bundled hooks.lua picks up on the next deploy.
  @hook_script_cache_key {__MODULE__, :hook_script}

  defp hook_script_from_runtime do
    case Application.get_env(:tuist, :kura_hook_path) do
      nil ->
        {:error, "kura_hook_path is not configured"}

      path when is_binary(path) ->
        case :persistent_term.get({@hook_script_cache_key, path}, :__missing__) do
          :__missing__ -> read_and_cache_hook_script(path)
          script -> {:ok, script}
        end
    end
  end

  defp read_and_cache_hook_script(path) do
    if File.regular?(path) do
      script = File.read!(path)
      :persistent_term.put({@hook_script_cache_key, path}, script)
      {:ok, script}
    else
      {:error, "kura_hook_path #{path} is not a file"}
    end
  end

  defp client_apply(manifest, region), do: Client.apply(manifest, kubernetes_client_opts(region))

  defp client_get_kura_instance(namespace, name, region) do
    Client.get_kura_instance(namespace, name, kubernetes_client_opts(region))
  end

  defp client_delete_kura_instance(namespace, name, region) do
    Client.delete_kura_instance(namespace, name, kubernetes_client_opts(region))
  end

  defp kubernetes_client_opts(%Regions{provisioner_config: %{kubernetes_client: opts}}), do: opts
  defp kubernetes_client_opts(_), do: []
end
