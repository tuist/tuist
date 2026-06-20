defmodule Tuist.Kura.Provisioner.KubernetesController do
  @moduledoc """
  Submits desired Kura endpoint state as `KuraInstance` and optional
  `KuraGateway` custom resources.

  The Go controller in `infra/kura-controller` owns the actual
  StatefulSet, Kura ingress, dedicated gateway, and internal peer Service
  reconciliation. This provisioner is only the bridge from Tuist's account
  model to the CRDs.
  """

  @behaviour Tuist.Kura.Provisioner

  alias Tuist.Accounts.Account
  alias Tuist.Billing.Entitlements
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  @namespace "kura"
  @manifest_revision "2026-06-18-node-port-and-single-host-grpc-v1"
  @manifest_revision_annotation "tuist.dev/kura-manifest-revision"
  @gateway_annotation "tuist.dev/kura-gateway"
  @gateway_controller_image "registry.k8s.io/ingress-nginx/controller:v1.11.3"
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
      gateway = gateway_assignment(account, region)

      case apply_manifests(
             [
               gateway_manifest(gateway, account, region),
               manifest(name, image_tag, account, region, server, hook_script, gateway)
             ],
             region
           ) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def destroy(name, %Regions{} = region) do
    with {:ok, gateway_name} <- gateway_name_for_instance(name, region),
         :ok <- delete_gateway_if_present(gateway_name, region) do
      case client_delete_kura_instance(@namespace, name, region) do
        :ok -> :ok
        {:error, :not_found} -> :ok
        {:error, reason} -> {:error, reason}
      end
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
      {:ok, %{"status" => %{"nodeAddress" => address, "nodePortHTTP" => port}}}
      when is_binary(address) and address != "" and is_integer(port) and port > 0 ->
        {:ok, "http://#{address}:#{port}"}

      {:ok, _} ->
        {:error, :node_port_endpoint_not_ready}

      {:error, reason} ->
        {:error, reason}
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
  def manifest(name, image_tag, account, %Regions{} = region, %Server{} = server, hook_script) do
    manifest(name, image_tag, account, region, server, hook_script, gateway_assignment(account, region))
  end

  @doc false
  def manifest(name, image_tag, account, %Regions{} = region, %Server{}, hook_script, gateway) do
    account_handle = dns_handle(account.name)
    annotations = maybe_put_gateway_annotation(%{@manifest_revision_annotation => @manifest_revision}, gateway)

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
          "publicHost" => public_host(account_handle, region),
          "grpcPublicHost" => grpc_public_host(account_handle, region),
          "ingressClassName" => ingress_class_name(region, gateway),
          "peerTLSSecretName" => peer_tls_secret_name(region),
          "mesh" => mesh_enabled?(region),
          "private" => Regions.private?(region),
          "exposeNodePort" => Regions.node_port_data_plane?(region),
          "clientCIDRs" => client_cidrs(region),
          "podAnnotations" => pod_annotations(region),
          "storageClassName" => storage_class(region),
          "storageSize" => storage_size(region),
          "replicas" => replicas(region),
          "nodeSelector" => node_selector(region),
          "tolerations" => tolerations(region),
          "extensionScript" => hook_script,
          "extraEnv" => extension_env(region)
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, "", false] end)
        |> Map.new()
    }
  end

  @doc false
  def gateway_manifest(nil, _account, _region), do: nil

  def gateway_manifest(%{name: gateway_name, ingress_class_name: ingress_class_name}, _account, %Regions{} = region) do
    %{
      "apiVersion" => "kura.tuist.dev/v1alpha1",
      "kind" => "KuraGateway",
      "metadata" => %{
        "name" => gateway_name,
        "namespace" => @namespace,
        "labels" => %{
          "app.kubernetes.io/name" => "kura-gateway",
          "app.kubernetes.io/instance" => gateway_name,
          "tuist.dev/region" => region.id
        }
      },
      "spec" =>
        %{
          "region" => region.id,
          "ingressClassName" => ingress_class_name,
          "controllerImage" => gateway_controller_image(region),
          "replicas" => gateway_replicas(region),
          "nodeSelector" => node_selector(region),
          "loadBalancerAnnotations" => gateway_load_balancer_annotations(gateway_name, region)
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, ""] or value == %{} end)
        |> Map.new()
    }
  end

  defp public_host(handle, %Regions{provisioner_config: %{public_host_template: template} = config}) do
    interpolate_host(template, dns_handle(handle), config)
  end

  defp public_host(_handle, _region), do: nil

  defp grpc_public_host(handle, %Regions{provisioner_config: %{grpc_public_host_template: template} = config}) do
    interpolate_host(template, dns_handle(handle), config)
  end

  defp grpc_public_host(_handle, _region), do: nil

  defp ingress_class_name(_region, %{ingress_class_name: ingress_class_name})
       when is_binary(ingress_class_name) and ingress_class_name != "", do: ingress_class_name

  defp ingress_class_name(%Regions{provisioner_config: %{ingress_class_name: ingress_class_name}}, nil)
       when is_binary(ingress_class_name) and ingress_class_name != "", do: ingress_class_name

  defp ingress_class_name(_region, _gateway), do: nil

  defp maybe_put_gateway_annotation(annotations, nil), do: annotations

  defp maybe_put_gateway_annotation(annotations, %{name: gateway_name}),
    do: Map.put(annotations, @gateway_annotation, gateway_name)

  defp peer_tls_secret_name(%Regions{provisioner_config: %{peer_tls_secret_name: secret_name}})
       when is_binary(secret_name) and secret_name != "", do: secret_name

  defp peer_tls_secret_name(_region), do: nil

  defp mesh_enabled?(%Regions{provisioner_config: %{mesh: mesh}}) when is_boolean(mesh), do: mesh
  defp mesh_enabled?(_region), do: false

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

  defp tolerations(%Regions{provisioner_config: %{tolerations: [_ | _] = tolerations}}), do: tolerations

  defp tolerations(_), do: nil

  # nil (not []) when unset so the manifest builder's reject drops the
  # key entirely.
  defp client_cidrs(%Regions{provisioner_config: %{client_cidrs: [_ | _] = cidrs}}), do: cidrs
  defp client_cidrs(_), do: nil

  defp pod_annotations(%Regions{provisioner_config: %{pod_annotations: annotations}})
       when is_map(annotations) and map_size(annotations) > 0, do: annotations

  defp pod_annotations(_), do: nil

  # Private (runner-cache) regions never get a gateway: their whole
  # invariant is "no public endpoint, no LoadBalancer" — a dedicated
  # gateway for a hosted-enterprise account would silently recreate
  # the public surface the region exists to avoid.
  defp gateway_assignment(account, %Regions{} = region) do
    if not Regions.private?(region) and dedicated_gateway?(account, region) do
      gateway_name = gateway_name(account, region)

      %{
        name: gateway_name,
        ingress_class_name: dedicated_gateway_ingress_class_name(gateway_name, region)
      }
    end
  end

  defp dedicated_gateway?(%{name: name} = account, %Regions{provisioner_config: config}) do
    handle = dns_handle(name)

    handle in dedicated_gateway_account_handles(config) or
      hosted_enterprise_account?(account)
  end

  defp dedicated_gateway?(_account, _region), do: false

  defp hosted_enterprise_account?(%Account{} = account) do
    Environment.tuist_hosted?() and Entitlements.allows?(account, :dedicated_kura_gateway)
  end

  defp hosted_enterprise_account?(_account), do: false

  defp gateway_name(account, %Regions{} = region) do
    "kgw-#{gateway_account_hash(account)}-#{region.id}"
  end

  defp gateway_account_hash(%{id: id}) when is_integer(id) do
    opaque_hash("account:#{id}")
  end

  defp gateway_account_hash(%{name: name}) when is_binary(name) do
    opaque_hash("account:#{dns_handle(name)}")
  end

  defp opaque_hash(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp dedicated_gateway_account_handles(%{dedicated_gateway_account_handles: handles}) when is_list(handles) do
    Enum.map(handles, &dns_handle/1)
  end

  defp dedicated_gateway_account_handles(_config), do: []

  defp dedicated_gateway_ingress_class_name(gateway_name, %Regions{} = region) do
    "kura-#{region.id}-#{gateway_name}"
  end

  defp gateway_controller_image(%Regions{provisioner_config: %{gateway_controller_image: image}})
       when is_binary(image) and image != "", do: image

  defp gateway_controller_image(_region), do: @gateway_controller_image

  defp gateway_replicas(%Regions{provisioner_config: %{gateway_replicas: replicas}}), do: replicas
  defp gateway_replicas(_region), do: 2

  defp gateway_load_balancer_annotations(gateway_name, %Regions{provisioner_config: config}) do
    annotations = %{
      "load-balancer.hetzner.cloud/name" => "tuist-#{gateway_name}-ingress",
      "load-balancer.hetzner.cloud/uses-proxyprotocol" => "true"
    }

    annotations =
      case Map.get(config, :hetzner_location) do
        location when is_binary(location) and location != "" ->
          Map.put(annotations, "load-balancer.hetzner.cloud/location", location)

        _ ->
          annotations
      end

    Map.merge(annotations, Map.get(config, :gateway_load_balancer_annotations, %{}))
  end

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

  defp gateway_name_for_instance(name, region) do
    case client_get_kura_instance(@namespace, name, region) do
      {:ok, %{"metadata" => %{"annotations" => %{@gateway_annotation => gateway_name}}}}
      when is_binary(gateway_name) and gateway_name != "" ->
        {:ok, gateway_name}

      {:ok, _} ->
        {:ok, nil}

      {:error, :not_found} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_gateway_if_present(nil, _region), do: :ok

  defp delete_gateway_if_present(gateway_name, region) do
    case client_delete_kura_gateway(@namespace, gateway_name, region) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
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

  defp client_delete_kura_gateway(namespace, name, region) do
    Client.delete_kura_gateway(namespace, name, kubernetes_client_opts(region))
  end

  defp kubernetes_client_opts(%Regions{provisioner_config: %{kubernetes_client: opts}}), do: opts
  defp kubernetes_client_opts(_), do: []
end
