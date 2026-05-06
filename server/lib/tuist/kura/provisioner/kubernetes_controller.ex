defmodule Tuist.Kura.Provisioner.KubernetesController do
  @moduledoc """
  Submits desired Kura endpoint state as `KuraInstance` custom resources.

  The Go controller in `infra/kura-controller` owns the actual
  StatefulSet/Service/Ingress reconciliation. This provisioner is only
  the bridge from Tuist's account model to the CRD.
  """

  @behaviour Tuist.Kura.Provisioner

  alias Tuist.Kura.Provisioner.HelmKubernetes
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  require Logger

  @namespace "kura"
  @tls_secret_name "tuist-tls-cloudflare-origin-kura"

  @impl true
  def provision(%{name: handle}, %Regions{} = region, %Server{}) do
    {:ok, instance_name(handle, region)}
  end

  @impl true
  def rollout(
        name,
        %{
          image_tag: image_tag,
          account: account,
          server: %Server{} = server,
          region: %Regions{} = region,
          on_log_line: on_log_line
        } = inputs
      ) do
    with {:ok, chart} <- chart_path(inputs),
         {:ok, kubeconfig} <- write_kubeconfig(region),
         {:ok, manifest} <- write_manifest(name, image_tag, account, region, server, chart),
         :ok <- shell(["kubectl", "apply", "-f", manifest], kubeconfig, on_log_line) do
      case shell(
             [
               "kubectl",
               "-n",
               @namespace,
               "wait",
               "--for=jsonpath={.status.phase}=Ready",
               "kurainstance/#{name}",
               "--timeout=10m"
             ],
             kubeconfig,
             on_log_line
           ) do
        :ok -> :ok
        {:error, status} -> {:error, "kubectl wait exited with status #{status}"}
      end
    else
      {:error, status} when is_integer(status) -> {:error, "kubectl apply exited with status #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def destroy(name, %Regions{} = region) do
    case write_kubeconfig(region) do
      {:ok, kubeconfig} ->
        case shell(
               ["kubectl", "-n", @namespace, "delete", "kurainstance", name, "--ignore-not-found", "--wait=true"],
               kubeconfig,
               &drop_log/2
             ) do
          :ok -> :ok
          {:error, status} -> {:error, "kubectl delete exited with status #{status}"}
        end

      {:error, reason} ->
        Logger.warning("[Kura.KubernetesController] destroy(#{name}) skipped: #{inspect(reason)}")
        :ok
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
  def current_image_tag(name, %Regions{} = region) do
    with {:ok, kubeconfig} <- write_kubeconfig(region) do
      args = [
        "kubectl",
        "--kubeconfig",
        kubeconfig,
        "-n",
        @namespace,
        "get",
        "kurainstance",
        name,
        "-o",
        "jsonpath={.status.observedImage}"
      ]

      case MuonTrap.cmd("env", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, HelmKubernetes.image_tag_from_image(output)}
        {output, _} -> {:error, String.trim(output)}
      end
    end
  end

  @impl true
  def nodes(name, %Regions{} = region) do
    with {:ok, kubeconfig} <- write_kubeconfig(region) do
      args = [
        "kubectl",
        "--kubeconfig",
        kubeconfig,
        "-n",
        @namespace,
        "get",
        "pods",
        "-l",
        "app.kubernetes.io/instance=#{name}",
        "-o",
        "json"
      ]

      case MuonTrap.cmd("env", args, stderr_to_stdout: true) do
        {output, 0} -> parse_nodes(output)
        {output, _} -> {:error, String.trim(output)}
      end
    end
  end

  @impl true
  def resources_for(%Server{}), do: %{}

  def instance_name(handle, %Regions{provisioner_config: %{cluster_id: cluster_id}}) do
    "kura-#{dns_handle(handle)}-#{cluster_id}"
  end

  @doc false
  def manifest(name, image_tag, account, %Regions{} = region, %Server{}, chart) do
    %{
      "apiVersion" => "kura.tuist.dev/v1alpha1",
      "kind" => "KuraInstance",
      "metadata" => %{
        "name" => name,
        "namespace" => @namespace,
        "labels" => %{
          "app.kubernetes.io/name" => "kura",
          "app.kubernetes.io/instance" => name,
          "tuist.dev/account" => account.name,
          "tuist.dev/region" => region.id
        }
      },
      "spec" =>
        %{
          "accountHandle" => account.name,
          "tenantID" => account.name,
          "region" => region.id,
          "image" => "ghcr.io/tuist/kura:#{image_tag}",
          "publicHost" => public_host(account.name, region),
          "tlsSecretName" => @tls_secret_name,
          "storageClassName" => storage_class(region),
          "extensionScript" => chart |> Path.join("hooks/tuist.lua") |> File.read!(),
          "extraEnv" => extension_env(region)
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
        |> Map.new()
    }
  end

  defp write_manifest(name, image_tag, account, region, server, chart) do
    name
    |> manifest(image_tag, account, region, server, chart)
    |> Ymlr.document!()
    |> write_temp("kurainstance")
  end

  defp public_host(handle, %Regions{provisioner_config: %{public_host_template: template} = config}) do
    interpolate_host(template, dns_handle(handle), config)
  end

  defp public_host(_handle, _region), do: nil

  defp extension_env(%Regions{} = region) do
    [
      env_var("KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE", "true"),
      env_var("KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE", "true"),
      env_var("KURA_EXTENSION_HOOK_TIMEOUT_MS", "5000"),
      env_var("KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL", tuist_base_url(region)),
      env_var("KURA_EXTENSION_HTTP_CLIENT_TUIST_CONNECT_TIMEOUT_MS", "3000"),
      env_var("KURA_EXTENSION_HTTP_CLIENT_TUIST_REQUEST_TIMEOUT_MS", "4000")
    ] ++ jwt_verifier_env() ++ signer_env()
  end

  defp jwt_verifier_env do
    case Tuist.Environment.secret_key_tokens() do
      nil ->
        []

      secret ->
        [
          env_var("KURA_EXTENSION_JWT_VERIFIER_TUIST_ALGORITHM", "HS512"),
          env_var("KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET", secret),
          env_var("KURA_EXTENSION_JWT_VERIFIER_TUIST_ISSUER", "tuist")
        ]
    end
  end

  defp signer_env do
    case license_signing_key() do
      nil ->
        []

      key ->
        [
          env_var("KURA_EXTENSION_SIGNER_TUIST_ALGORITHM", "hmac-sha256"),
          env_var("KURA_EXTENSION_SIGNER_TUIST_SECRET", key)
        ]
    end
  end

  defp env_var(name, value), do: %{"name" => name, "value" => value}

  defp license_signing_key do
    case Tuist.License.get_license() do
      {:ok, %{signing_key: key}} when is_binary(key) and key != "" -> key
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp tuist_base_url(_), do: Tuist.Environment.app_url()

  defp storage_class(%Regions{provisioner_config: %{storage_class: storage_class}}), do: storage_class
  defp storage_class(_), do: nil

  @doc false
  def parse_nodes(json) do
    case Jason.decode(json) do
      {:ok, %{"items" => items}} -> {:ok, Enum.map(items, &node_from_pod/1)}
      {:error, reason} -> {:error, reason}
      _ -> {:error, "unexpected kubectl pod list shape"}
    end
  end

  defp node_from_pod(%{"metadata" => metadata, "status" => status} = pod) do
    %{
      name: metadata["name"],
      pod_ip: status["podIP"],
      host_ip: status["hostIP"],
      node_name: pod |> Map.get("spec", %{}) |> Map.get("nodeName"),
      phase: status["phase"],
      ready: pod_ready?(status),
      started_at: status["startTime"]
    }
  end

  defp pod_ready?(%{"conditions" => conditions}) when is_list(conditions) do
    Enum.any?(conditions, &(&1["type"] == "Ready" and &1["status"] == "True"))
  end

  defp pod_ready?(_), do: false

  defp interpolate_host(template, handle, %{cluster_id: cluster_id}) do
    template
    |> String.replace("{account_handle}", handle)
    |> String.replace("{cluster_id}", cluster_id)
  end

  defp dns_handle(handle), do: String.downcase(handle)

  defp chart_path(inputs) do
    case Map.get(inputs, :chart_path) || Application.get_env(:tuist, :kura_chart_path) do
      nil ->
        {:error, "kura_chart_path is not configured"}

      path when is_binary(path) ->
        if File.dir?(path),
          do: {:ok, path},
          else: {:error, "kura_chart_path #{path} is not a directory"}
    end
  end

  defp write_kubeconfig(%Regions{} = region) do
    with {:ok, contents} <- resolve_kubeconfig(region) do
      write_temp(contents, "kubeconfig")
    end
  end

  defp resolve_kubeconfig(%Regions{provisioner_config: config}) do
    case Tuist.Environment.kura_kubeconfig(config[:cluster_id]) do
      kc when is_binary(kc) and kc != "" -> {:ok, kc}
      _ -> {:error, "no kubeconfig configured for cluster #{config[:cluster_id]}"}
    end
  end

  defp shell(args, kubeconfig_path, on_log_line) do
    env = [
      {~c"KUBECONFIG", String.to_charlist(kubeconfig_path)},
      {~c"PATH", String.to_charlist(System.get_env("PATH") || "/usr/local/bin:/usr/bin:/bin")}
    ]

    port =
      Port.open(
        {:spawn_executable, System.find_executable("env") || "/usr/bin/env"},
        [:binary, :exit_status, :stderr_to_stdout, {:line, 4_096}, {:env, env}, {:args, args}]
      )

    drain(port, on_log_line)
  end

  defp drain(port, on_log_line) do
    receive do
      {^port, {:data, {kind, line}}} when kind in [:eol, :noeol] ->
        on_log_line.(line, :stdout)
        drain(port, on_log_line)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        {:error, status}
    end
  end

  defp write_temp(contents, label) do
    with {:ok, path} <- Briefly.create(prefix: "kura-#{label}-", extname: ".yaml"),
         :ok <- File.write(path, contents),
         :ok <- File.chmod(path, 0o600) do
      {:ok, path}
    else
      {:error, reason} -> {:error, "failed to write #{label}: #{inspect(reason)}"}
    end
  end

  defp drop_log(_line, _stream), do: :ok
end
