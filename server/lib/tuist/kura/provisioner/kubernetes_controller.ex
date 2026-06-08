defmodule Tuist.Kura.Provisioner.KubernetesController do
  @moduledoc """
  Submits desired Kura endpoint state as `KuraInstance` custom resources.

  The Go controller in `infra/kura-controller` owns the actual
  StatefulSet and direct LoadBalancer Service reconciliation. This provisioner is only
  the bridge from Tuist's account model to the CRD.
  """

  @behaviour Tuist.Kura.Provisioner

  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  @namespace "kura"
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
      manifest = manifest(name, image_tag, account, region, server, hook_script)

      case client_apply(manifest, region) do
        {:ok, _} -> :ok
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
  def public_url(handle, %Regions{provisioner_config: config}, _ref) do
    cond do
      template = config[:public_host_template] ->
        "https://" <> interpolate_host(template, dns_handle(handle), config)

      url = config[:public_url] ->
        url

      true ->
        raise ArgumentError,
              "region #{inspect(config[:cluster_id])} has neither :public_host_template nor :public_url"
    end
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
  def manifest(name, image_tag, account, %Regions{} = region, %Server{}, hook_script) do
    account_handle = dns_handle(account.name)

    %{
      "apiVersion" => "kura.tuist.dev/v1alpha1",
      "kind" => "KuraInstance",
      "metadata" => %{
        "name" => name,
        "namespace" => @namespace,
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
          "storageClassName" => storage_class(region),
          "storageSize" => storage_size(region),
          "replicas" => replicas(region),
          "nodeSelector" => node_selector(region),
          "extensionScript" => hook_script,
          "extraEnv" => extension_env(region)
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
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
        Tuist.Environment.kura_control_plane_client_id()
      ) ++
      maybe_env_var(
        "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID",
        Tuist.Environment.kura_control_plane_client_id()
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
    Tuist.Environment.app_url()
    |> URI.parse()
    |> rewrite_loopback("host.docker.internal")
    |> URI.to_string()
  end

  defp tuist_base_url(%Regions{provisioner_config: %{tuist_base_url: url}}) when is_binary(url) and url != "", do: url

  defp tuist_base_url(_), do: Tuist.Environment.app_url()

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

  defp client_apply(manifest, region) do
    case kubernetes_client_opts(region) do
      [] -> Client.apply(manifest)
      opts -> Client.apply(manifest, opts)
    end
  end

  defp client_get_kura_instance(namespace, name, region) do
    Client.get_kura_instance(namespace, name, kubernetes_client_opts(region))
  end

  defp client_delete_kura_instance(namespace, name, region) do
    case kubernetes_client_opts(region) do
      [] -> Client.delete_kura_instance(namespace, name)
      opts -> Client.delete_kura_instance(namespace, name, opts)
    end
  end

  defp kubernetes_client_opts(%Regions{provisioner_config: %{kubernetes_client: opts}}), do: opts
  defp kubernetes_client_opts(_), do: []
end
