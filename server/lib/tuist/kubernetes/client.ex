defmodule Tuist.Kubernetes.Client do
  @moduledoc """
  Small Kubernetes API client for server-owned control-plane writes.

  Production uses the pod ServiceAccount projected by Kubernetes for the
  cluster the server runs in. Cross-region Kura operations use kubeconfigs
  loaded from the runtime environment.

  Dev/test can opt into `mode: :kubectl` to exercise the same controller-backed
  path from a local server process against kind.
  """

  @service_account_dir "/var/run/secrets/kubernetes.io/serviceaccount"
  @token_path Path.join(@service_account_dir, "token")
  @ca_path Path.join(@service_account_dir, "ca.crt")
  @field_manager "tuist-server"
  @kura_instance_path ~r{\A/apis/kura\.tuist\.dev/v1alpha1/namespaces/([^/]+)/kurainstances/([^/]+)\z}
  @pods_path ~r{\A/api/v1/namespaces/([^/]+)/pods\z}

  def get(path, opts \\ []) when is_binary(path) do
    request(:get, path, opts: opts)
  end

  def replace(path, body, opts \\ []) when is_binary(path) and is_map(body) do
    request(:put, path,
      opts: opts,
      body: Jason.encode!(body),
      headers: [{"content-type", "application/json"}]
    )
  end

  def patch(path, operations, opts \\ []) when is_binary(path) and is_list(operations) do
    request(:patch, path,
      opts: opts,
      body: Jason.encode!(operations),
      headers: [{"content-type", "application/json-patch+json"}]
    )
  end

  def delete(path, opts \\ []) when is_binary(path) do
    case request(:delete, path, opts: opts) do
      {:ok, _body} -> :ok
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def apply(manifest, opts \\ []) when is_map(manifest) do
    with {:ok, path} <- manifest_path(manifest) do
      if kubectl_mode?(opts) do
        kubectl_apply(manifest, opts)
      else
        body = Ymlr.document!(manifest)

        request(:patch, path,
          opts: opts,
          body: body,
          query: %{"fieldManager" => @field_manager, "force" => "true"},
          headers: [{"content-type", "application/apply-patch+yaml"}]
        )
      end
    end
  end

  def get_kura_instance(namespace, name, opts \\ []) do
    get("/apis/kura.tuist.dev/v1alpha1/namespaces/#{namespace}/kurainstances/#{name}", opts)
  end

  def delete_kura_instance(namespace, name, opts \\ []) do
    delete("/apis/kura.tuist.dev/v1alpha1/namespaces/#{namespace}/kurainstances/#{name}", opts)
  end

  def list_pods(namespace, label_selector, opts \\ []) when is_binary(label_selector) do
    request(:get, "/api/v1/namespaces/#{namespace}/pods", opts: opts, query: %{"labelSelector" => label_selector})
  end

  defp manifest_path(%{
         "apiVersion" => "kura.tuist.dev/v1alpha1",
         "kind" => "KuraInstance",
         "metadata" => %{"namespace" => namespace, "name" => name}
       }) do
    {:ok, "/apis/kura.tuist.dev/v1alpha1/namespaces/#{namespace}/kurainstances/#{name}"}
  end

  defp manifest_path(%{"kind" => kind}), do: {:error, "unsupported Kubernetes manifest kind #{kind}"}
  defp manifest_path(_), do: {:error, "unsupported Kubernetes manifest"}

  defp request(method, path, options) do
    opts = Keyword.get(options, :opts, [])
    headers = Keyword.get(options, :headers, [{"content-type", "application/json"}])
    query = Keyword.get(options, :query, %{})
    body = Keyword.get(options, :body)

    if kubectl_mode?(opts) do
      kubectl_request(method, path, query, opts)
    else
      api_request(method, path, headers, query, body, opts)
    end
  end

  defp api_request(method, path, headers, query, body, opts) do
    with {:ok, config} <- config(opts) do
      req_opts =
        maybe_put_body(
          [
            method: method,
            url: url(config, path),
            headers: request_headers(config, headers),
            params: query,
            finch: Tuist.Finch,
            connect_options: [transport_opts: config.transport_opts]
          ],
          body
        )

      try do
        case Req.request(req_opts) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, body}

          {:ok, %Req.Response{status: 404}} ->
            {:error, :not_found}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, "Kubernetes API #{method} #{path} returned #{status}: #{format_body(body)}"}

          {:error, reason} ->
            {:error, reason}
        end
      after
        cleanup_temp_files(config)
      end
    end
  end

  defp kubectl_apply(manifest, opts) do
    with :ok <- ensure_local_kubectl_mode(),
         {:ok, manifest_path} <- write_temp(Ymlr.document!(manifest), "manifest"),
         {:ok, output} <-
           kubectl(
             [
               "apply",
               "--server-side",
               "--field-manager",
               @field_manager,
               "--force-conflicts",
               "-f",
               manifest_path,
               "-o",
               "json"
             ],
             opts
           ) do
      decode_json(output)
    else
      {:error, %{status: _status} = error} ->
        {:error, format_kubectl_error("apply KuraInstance", error)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp kubectl_request(:get, path, query, opts) do
    case kura_instance_path(path) do
      {:ok, namespace, name} ->
        case kubectl(["-n", namespace, "get", "kurainstance", name, "-o", "json"], opts) do
          {:ok, output} ->
            decode_json(output)

          {:error, %{output: output} = error} when is_binary(output) ->
            if not_found?(output),
              do: {:error, :not_found},
              else: {:error, format_kubectl_error("get KuraInstance", error)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} ->
        kubectl_get_pods(path, query, opts)
    end
  end

  defp kubectl_request(:delete, path, _query, opts) do
    with {:ok, namespace, name} <- kura_instance_path(path) do
      case kubectl(["-n", namespace, "delete", "kurainstance", name], opts) do
        {:ok, _output} ->
          {:ok, %{}}

        {:error, %{output: output} = error} when is_binary(output) ->
          if not_found?(output),
            do: {:error, :not_found},
            else: {:error, format_kubectl_error("delete KuraInstance", error)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp kubectl_request(method, path, _query, _opts) do
    {:error, "unsupported local kubectl Kubernetes request #{method} #{path}"}
  end

  defp kubectl_get_pods(path, query, opts) do
    with {:ok, namespace} <- pods_path(path),
         label_selector when is_binary(label_selector) <- Map.get(query, "labelSelector") do
      case kubectl(["-n", namespace, "get", "pods", "-l", label_selector, "-o", "json"], opts) do
        {:ok, output} ->
          decode_json(output)

        {:error, %{status: _status} = error} ->
          {:error, format_kubectl_error("list pods", error)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "local kubectl pod list request requires a label selector"}
    end
  end

  defp kubectl(args, opts) do
    with :ok <- ensure_local_kubectl_mode(),
         :ok <- ensure_executable("kubectl"),
         {:ok, kubeconfig_args} <- kubeconfig_args(opts) do
      case MuonTrap.cmd("env", ["kubectl"] ++ kubeconfig_args ++ args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, status} -> {:error, %{status: status, output: String.trim(output)}}
      end
    end
  end

  defp kubeconfig_args(opts) do
    cond do
      path = Keyword.get(opts, :kubeconfig_path) ->
        if File.exists?(path),
          do: {:ok, ["--kubeconfig", path]},
          else: {:error, "configured Kubernetes kubeconfig path #{path} does not exist"}

      contents = Keyword.get(opts, :kubeconfig) ->
        with {:ok, path} <- write_temp(contents, "kubeconfig") do
          {:ok, ["--kubeconfig", path]}
        end

      name = Keyword.get(opts, :kind_cluster_name) ->
        with {:ok, contents} <- resolve_kind_kubeconfig(name),
             {:ok, path} <- write_temp(contents, "kubeconfig") do
          {:ok, ["--kubeconfig", path]}
        end

      true ->
        {:ok, []}
    end
  end

  defp resolve_kind_kubeconfig(name) do
    with :ok <- ensure_executable("kind") do
      case kind_kubeconfig(name) do
        kubeconfig when is_binary(kubeconfig) and kubeconfig != "" ->
          {:ok, kubeconfig}

        _ ->
          with :ok <- create_kind_cluster(name),
               kubeconfig when is_binary(kubeconfig) and kubeconfig != "" <- kind_kubeconfig(name) do
            {:ok, kubeconfig}
          else
            {:error, reason} -> {:error, reason}
            _ -> {:error, "failed to bring up kind cluster `#{name}`"}
          end
      end
    end
  end

  defp kind_kubeconfig(name) do
    case MuonTrap.cmd("kind", ["get", "kubeconfig", "--name", name], stderr_to_stdout: true) do
      {kubeconfig, 0} when is_binary(kubeconfig) and kubeconfig != "" -> kubeconfig
      _ -> nil
    end
  end

  defp create_kind_cluster(name) do
    args = ["create", "cluster", "--name", name] ++ kind_config_args()

    case MuonTrap.cmd("kind", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, "kind create cluster failed: #{String.trim(output)}"}
    end
  end

  defp kind_config_args do
    [
      Path.expand("../kura/ops/kind/dev-cluster.yaml", File.cwd!()),
      Path.expand("kura/ops/kind/dev-cluster.yaml", File.cwd!())
    ]
    |> Enum.find(&File.exists?/1)
    |> case do
      nil -> []
      path -> ["--config", path]
    end
  end

  defp ensure_local_kubectl_mode do
    if Tuist.Environment.dev?() or Tuist.Environment.test?() do
      :ok
    else
      {:error, "local kubectl Kubernetes client mode is only available in dev/test"}
    end
  end

  defp ensure_executable(name) do
    if System.find_executable(name),
      do: :ok,
      else: {:error, "#{name} is not on PATH"}
  end

  defp kubectl_mode?(opts), do: Keyword.get(opts, :mode) in [:kubectl, "kubectl"]

  defp kubeconfig_mode?(opts), do: Keyword.get(opts, :mode) in [:kubeconfig, "kubeconfig"]

  defp kura_instance_path(path) do
    case Regex.run(@kura_instance_path, path) do
      [_, namespace, name] -> {:ok, namespace, name}
      _ -> {:error, "unsupported Kubernetes KuraInstance path #{path}"}
    end
  end

  defp pods_path(path) do
    case Regex.run(@pods_path, path) do
      [_, namespace] -> {:ok, namespace}
      _ -> {:error, "unsupported Kubernetes pod list path #{path}"}
    end
  end

  defp decode_json(output) do
    case Jason.decode(output) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, "kubectl returned invalid JSON: #{Exception.message(reason)}"}
    end
  end

  defp not_found?(output) do
    output = String.downcase(output)
    String.contains?(output, "notfound") or String.contains?(output, "not found")
  end

  defp format_kubectl_error(action, %{status: nil, output: output}) do
    "kubectl #{action} failed: #{String.trim(output)}"
  end

  defp format_kubectl_error(action, %{status: status, output: output}) do
    "kubectl #{action} exited with status #{status}: #{String.trim(output)}"
  end

  defp write_temp(contents, label, extname \\ ".yaml") do
    with {:ok, path} <- Briefly.create(prefix: "kubernetes-#{label}-", extname: extname),
         :ok <- File.write(path, contents),
         :ok <- File.chmod(path, 0o600) do
      {:ok, path}
    else
      {:error, reason} -> {:error, "failed to write #{label}: #{inspect(reason)}"}
    end
  end

  defp config(opts) do
    if kubeconfig_mode?(opts), do: kubeconfig_config(opts), else: in_cluster_config(opts)
  end

  defp in_cluster_config(opts) do
    with {:ok, host} <- env("KUBERNETES_SERVICE_HOST", opts),
         {:ok, port} <- env("KUBERNETES_SERVICE_PORT", opts),
         {:ok, token} <- service_account_token(opts),
         {:ok, ca_path} <- service_account_ca_path(opts) do
      {:ok, %{host: host, port: port, token: token, transport_opts: [cacertfile: ca_path], temp_paths: []}}
    end
  end

  defp kubeconfig_config(opts) do
    with {:ok, contents} <- kubeconfig_contents(opts),
         {:ok, kubeconfig} <- parse_kubeconfig(contents),
         {:ok, context} <- kubeconfig_current_context(kubeconfig),
         {:ok, cluster} <- kubeconfig_named_entry(kubeconfig, "clusters", context["cluster"]),
         {:ok, user} <- kubeconfig_named_entry(kubeconfig, "users", context["user"]),
         {:ok, token} <- kubeconfig_token(user),
         {:ok, server} <- kubeconfig_server(cluster),
         {:ok, transport_opts, temp_paths} <- kubeconfig_transport_opts(cluster, user) do
      {:ok, %{server: server, token: token, transport_opts: transport_opts, temp_paths: temp_paths}}
    end
  end

  defp kubeconfig_contents(opts) do
    cond do
      contents = Keyword.get(opts, :kubeconfig) ->
        {:ok, contents}

      path = Keyword.get(opts, :kubeconfig_path) ->
        case File.read(path) do
          {:ok, contents} -> {:ok, contents}
          {:error, reason} -> {:error, "cannot read Kubernetes kubeconfig #{path}: #{inspect(reason)}"}
        end

      cluster_id = Keyword.get(opts, :cluster_id) ->
        case Tuist.Environment.kura_kubeconfig(cluster_id) do
          contents when is_binary(contents) and contents != "" ->
            {:ok, contents}

          _ ->
            suffix = cluster_id |> String.upcase() |> String.replace("-", "_")

            {:error,
             "missing Kubernetes kubeconfig for Kura cluster #{cluster_id}; set TUIST_KURA_KUBECONFIG_#{suffix} or TUIST_KURA_KUBECONFIG_PATH_#{suffix}"}
        end

      true ->
        {:error, "Kubernetes kubeconfig client mode requires :kubeconfig, :kubeconfig_path, or :cluster_id"}
    end
  end

  defp parse_kubeconfig(contents) do
    case YamlElixir.read_from_string(contents) do
      {:ok, kubeconfig} when is_map(kubeconfig) -> {:ok, kubeconfig}
      {:ok, _} -> {:error, "Kubernetes kubeconfig is not a YAML map"}
      {:error, reason} -> {:error, "invalid Kubernetes kubeconfig: #{inspect(reason)}"}
    end
  end

  defp kubeconfig_current_context(%{"current-context" => name} = kubeconfig) when is_binary(name) do
    kubeconfig_named_entry(kubeconfig, "contexts", name)
  end

  defp kubeconfig_current_context(_), do: {:error, "Kubernetes kubeconfig has no current-context"}

  defp kubeconfig_named_entry(kubeconfig, key, name) when is_binary(name) do
    data_key = kubeconfig_entry_data_key(key)

    kubeconfig
    |> Map.get(key, [])
    |> Enum.find(&(Map.get(&1, "name") == name))
    |> case do
      %{"name" => ^name} = entry -> {:ok, Map.get(entry, data_key, %{})}
      nil -> {:error, "Kubernetes kubeconfig references missing #{String.trim_trailing(key, "s")} #{name}"}
    end
  end

  defp kubeconfig_named_entry(_kubeconfig, key, _name) do
    {:error, "Kubernetes kubeconfig context has no #{String.trim_trailing(key, "s")} name"}
  end

  defp kubeconfig_entry_data_key("clusters"), do: "cluster"
  defp kubeconfig_entry_data_key("contexts"), do: "context"
  defp kubeconfig_entry_data_key("users"), do: "user"

  defp kubeconfig_server(%{"server" => server}) when is_binary(server) and server != "" do
    {:ok, String.trim_trailing(server, "/")}
  end

  defp kubeconfig_server(_), do: {:error, "Kubernetes kubeconfig cluster has no server"}

  defp kubeconfig_token(%{"token" => token}) when is_binary(token) and token != "", do: {:ok, token}

  defp kubeconfig_token(%{"client-certificate-data" => cert, "client-key-data" => key})
       when is_binary(cert) and cert != "" and is_binary(key) and key != "", do: {:ok, nil}

  defp kubeconfig_token(%{"client-certificate" => cert, "client-key" => key})
       when is_binary(cert) and cert != "" and is_binary(key) and key != "", do: {:ok, nil}

  defp kubeconfig_token(_user) do
    {:error, "Kubernetes kubeconfig user must contain token or client certificate credentials"}
  end

  defp kubeconfig_transport_opts(cluster, user) do
    with {:ok, cluster_opts, cluster_paths} <- kubeconfig_cluster_transport_opts(cluster),
         {:ok, user_opts, user_paths} <- kubeconfig_user_transport_opts(user) do
      {:ok, cluster_opts ++ user_opts, cluster_paths ++ user_paths}
    end
  end

  defp kubeconfig_cluster_transport_opts(%{"certificate-authority-data" => data}) when is_binary(data) do
    with {:ok, contents} <- decode_kubeconfig_data(data, "certificate-authority-data"),
         {:ok, path} <- write_temp(contents, "ca", ".crt") do
      {:ok, [cacertfile: path], [path]}
    end
  end

  defp kubeconfig_cluster_transport_opts(%{"certificate-authority" => path}) when is_binary(path) and path != "" do
    {:ok, [cacertfile: path], []}
  end

  defp kubeconfig_cluster_transport_opts(%{"insecure-skip-tls-verify" => true}) do
    {:ok, [verify: :verify_none], []}
  end

  defp kubeconfig_cluster_transport_opts(_), do: {:ok, [], []}

  defp kubeconfig_user_transport_opts(%{"client-certificate-data" => cert_data, "client-key-data" => key_data})
       when is_binary(cert_data) and cert_data != "" and is_binary(key_data) and key_data != "" do
    with {:ok, cert} <- decode_kubeconfig_data(cert_data, "client-certificate-data"),
         {:ok, key} <- decode_kubeconfig_data(key_data, "client-key-data"),
         {:ok, cert_path} <- write_temp(cert, "client-cert", ".crt"),
         {:ok, key_path} <- write_temp(key, "client-key", ".key") do
      {:ok, [certfile: cert_path, keyfile: key_path], [cert_path, key_path]}
    end
  end

  defp kubeconfig_user_transport_opts(%{"client-certificate" => cert_path, "client-key" => key_path})
       when is_binary(cert_path) and cert_path != "" and is_binary(key_path) and key_path != "" do
    {:ok, [certfile: cert_path, keyfile: key_path], []}
  end

  defp kubeconfig_user_transport_opts(_), do: {:ok, [], []}

  defp decode_kubeconfig_data(data, field) do
    case Base.decode64(data, ignore: :whitespace) do
      {:ok, contents} -> {:ok, contents}
      :error -> {:error, "Kubernetes kubeconfig #{field} is not valid base64"}
    end
  end

  defp env(name, opts) do
    env = Keyword.get(opts, :env, System)

    case env.get_env(name) do
      nil -> {:error, "Kubernetes in-cluster env var #{name} is not set"}
      value -> {:ok, value}
    end
  end

  defp service_account_token(opts) do
    path = Keyword.get(opts, :token_path, @token_path)

    case File.read(path) do
      {:ok, token} -> {:ok, String.trim(token)}
      {:error, reason} -> {:error, "cannot read Kubernetes ServiceAccount token #{path}: #{inspect(reason)}"}
    end
  end

  defp service_account_ca_path(opts) do
    path = Keyword.get(opts, :ca_path, @ca_path)

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "cannot read Kubernetes ServiceAccount CA #{path}"}
    end
  end

  defp request_headers(config, headers) do
    base_headers = [{"accept", "application/json"} | headers]

    case Map.get(config, :token) do
      token when is_binary(token) and token != "" -> [{"authorization", "Bearer #{token}"} | base_headers]
      _ -> base_headers
    end
  end

  defp cleanup_temp_files(%{temp_paths: paths}) do
    Enum.each(paths, &File.rm/1)
  end

  defp cleanup_temp_files(_), do: :ok

  defp url(%{server: server}, path), do: server <> path
  defp url(config, path), do: "https://#{config.host}:#{config.port}#{path}"

  defp maybe_put_body(req_opts, nil), do: req_opts
  defp maybe_put_body(req_opts, body), do: Keyword.put(req_opts, :body, body)

  defp format_body(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp format_body(body), do: inspect(body, limit: 20)
end
