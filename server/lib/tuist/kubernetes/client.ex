defmodule Tuist.Kubernetes.Client do
  @moduledoc """
  Small Kubernetes API client used by two unrelated subsystems on
  the server:

    * **Kura provisioner / Kura controller**: generic verbs
      (`get/2`, `replace/3`, `patch/3`, `delete/2`, `apply/2`) +
      Kura-instance helpers, with both in-cluster ServiceAccount
      auth and explicit kubeconfig support for local controller/dev use.

    * **Runner dispatch**: domain-specific helpers
      (`create_token_review/1`, `get_service_account/2`,
      `get_runner_pool/2`, `list_runner_pools/1`, `list_pods/2`,
      `patch_pod/3`) that drive the SA-token-authenticated
      dispatch endpoint and stamp owner labels at claim time.

  Both surfaces share the same auth + request infrastructure
  (`request/3` + `config/1`). In-cluster auth uses the projected
  ServiceAccount mount at `/var/run/secrets/kubernetes.io/serviceaccount`;
  local controller/dev paths can pass an explicit kubeconfig via
  `opts[:mode] = :kubeconfig`.
  """

  @service_account_dir "/var/run/secrets/kubernetes.io/serviceaccount"
  @token_path Path.join(@service_account_dir, "token")
  @ca_path Path.join(@service_account_dir, "ca.crt")
  @field_manager "tuist-server"

  # ----- Generic verbs (used by Kura) -----

  def get(path, opts \\ []) when is_binary(path) do
    request(:get, path, opts: opts)
  end

  def replace(path, body, opts \\ []) when is_binary(path) and is_map(body) do
    request(:put, path,
      opts: opts,
      body: JSON.encode!(body),
      headers: [{"content-type", "application/json"}]
    )
  end

  def patch(path, operations, opts \\ []) when is_binary(path) and is_list(operations) do
    request(:patch, path,
      opts: opts,
      body: JSON.encode!(operations),
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
      body = Ymlr.document!(manifest)

      request(:patch, path,
        opts: opts,
        body: body,
        query: %{"fieldManager" => @field_manager, "force" => "true"},
        headers: [{"content-type", "application/apply-patch+yaml"}]
      )
    end
  end

  def get_kura_instance(namespace, name, opts \\ []) do
    get("/apis/kura.tuist.dev/v1alpha1/namespaces/#{namespace}/kurainstances/#{name}", opts)
  end

  def delete_kura_instance(namespace, name, opts \\ []) do
    delete("/apis/kura.tuist.dev/v1alpha1/namespaces/#{namespace}/kurainstances/#{name}", opts)
  end

  # ----- Runner dispatch helpers -----

  # Audience the runner-issued SA token must claim AND the
  # TokenReview must validate against. Tart-kubelet mints the
  # token with `Audiences: [@dispatch_audience]`; the apiserver
  # accepts the token only if it carries this audience (and any
  # configured projected-volume audiences). A leaked guest token
  # is therefore single-purpose: it can talk to this dispatch
  # endpoint and nothing else — in particular, it is NOT a
  # default-audience credential for the K8s API server.
  @dispatch_audience "tuist-runners-dispatch"

  @doc """
  Returns the audience the runner ServiceAccount token must
  carry. Kept as a single source of truth so tart-kubelet (which
  reads this via a CLI flag baked into the controller) and the
  dispatch endpoint always agree.
  """
  def runner_dispatch_audience, do: @dispatch_audience

  @doc """
  POSTs a TokenReview for `token` and returns
  `{:ok, %{namespace: ns, name: sa_name, uid: uid}}` when the
  apiserver authenticates the token AND the principal is a
  ServiceAccount (we reject user / node tokens here so a leaked
  kubeconfig can't impersonate a runner).

  The TokenReview request carries an expected `audiences`
  list so the apiserver rejects tokens that don't claim the
  dispatch audience. Without this, a default-audience SA token
  leaked from the guest VM (it lives on disk at
  `/etc/tuist-sa-token`, readable by the customer-controlled
  job) could be replayed against the K8s API. With it, the
  token only validates here.

  Returns `{:error, :unauthenticated}` when TokenReview rejects
  the token, `{:error, :not_service_account}` when authenticated
  but not an SA, or `{:error, _}` on transport / non-2xx errors.
  """
  def create_token_review(token, opts \\ []) when is_binary(token) do
    create_audience_token_review(token, @dispatch_audience, opts)
  end

  defp create_audience_token_review(token, audience, opts) do
    body =
      JSON.encode!(%{
        "apiVersion" => "authentication.k8s.io/v1",
        "kind" => "TokenReview",
        "spec" => %{
          "token" => token,
          "audiences" => [audience]
        }
      })

    case request(:post, "/apis/authentication.k8s.io/v1/tokenreviews",
           opts: opts,
           body: body,
           headers: [{"content-type", "application/json"}]
         ) do
      {:ok, %{"status" => %{"authenticated" => true, "user" => user, "audiences" => audiences}}}
      when is_list(audiences) ->
        # Defense in depth: the apiserver already rejects tokens
        # that don't claim our audience (returns authenticated:
        # false), but if the request audience filtering is ever
        # accidentally widened, the response carries the
        # subset that did validate — fail-closed if our audience
        # isn't in the list.
        if audience in audiences do
          parse_sa_principal(user)
        else
          {:error, :unauthenticated}
        end

      {:ok, %{"status" => %{"authenticated" => true, "user" => user}}} ->
        parse_sa_principal(user)

      {:ok, %{"status" => %{"authenticated" => false}}} ->
        {:error, :unauthenticated}

      {:ok, %{"status" => %{"error" => _}}} ->
        # Apiserver omits `authenticated` when validation itself
        # fails (expired SA token, rotated signing key, malformed
        # JWT). Fail closed: treat as unauthenticated.
        {:error, :unauthenticated}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  TokenReview variant for the runners-controller calling the
  `desired_replicas` endpoint. Unlike `create_token_review/1`, this
  does NOT require the `tuist-runners-dispatch` audience — the
  controller mounts its SA token at the standard projected path
  (default audience = kube-apiserver), not via a custom
  audience-scoped projected volume the way tart-kubelet does for
  runner Pods.

  The audience filter is intentionally absent. The endpoint
  returns aggregate scaling signals (claimed / queued / p95
  counts) and is read-only, so accepting any valid in-cluster SA
  token is a sane authentication bar — anyone with cluster-side
  workload access could read the same data via the K8s API
  anyway. The strict-audience pattern stays scoped to dispatch,
  where the principal also gates JIT minting against a specific
  customer's GitHub Actions runner.
  """
  def create_controller_token_review(token, opts \\ []) when is_binary(token) do
    body =
      JSON.encode!(%{
        "apiVersion" => "authentication.k8s.io/v1",
        "kind" => "TokenReview",
        "spec" => %{"token" => token}
      })

    case request(:post, "/apis/authentication.k8s.io/v1/tokenreviews",
           opts: opts,
           body: body,
           headers: [{"content-type", "application/json"}]
         ) do
      {:ok, %{"status" => %{"authenticated" => true, "user" => user}}} ->
        parse_sa_principal(user)

      {:ok, %{"status" => %{"authenticated" => false}}} ->
        {:error, :unauthenticated}

      {:ok, %{"status" => %{"error" => _}}} ->
        {:error, :unauthenticated}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  GETs a ServiceAccount by name from `namespace`. The dispatch
  endpoint reads `metadata.labels["tuist.dev/runner-pool"]` to
  resolve which pool the SA-as-caller is authorized for.
  """
  def get_service_account(namespace, name) when is_binary(namespace) and is_binary(name) do
    get("/api/v1/namespaces/#{namespace}/serviceaccounts/#{name}")
  end

  @doc """
  GETs a single RunnerPool CR by name. Returns the decoded JSON map
  on success; the caller pulls `spec.dispatchLabel` (and other
  spec fields) to drive the JIT mint.
  """
  def get_runner_pool(namespace, name) when is_binary(namespace) and is_binary(name) do
    get("/apis/tuist.dev/v1alpha1/namespaces/#{namespace}/runnerpools/#{name}")
  end

  @doc """
  LISTs RunnerPool CRs in `namespace`. The dispatch webhook
  handler iterates the result to find a pool whose
  `spec.dispatchLabel` matches the incoming workflow_job's labels.
  """
  def list_runner_pools(namespace) when is_binary(namespace) do
    case get("/apis/tuist.dev/v1alpha1/namespaces/#{namespace}/runnerpools") do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:error, _} = err -> err
    end
  end

  @doc """
  LISTs Pods in `namespace` matching `label_selector`. Used by
  `Tuist.Runners.dispatch_for_sa` to count in-flight Pods per
  customer (Pods labeled `tuist.dev/runner-pool-owner=<owner>`)
  before claiming a queue entry, to enforce `max_concurrent`.
  """
  def list_pods(namespace, label_selector) when is_binary(namespace) and is_binary(label_selector) do
    case request(:get, "/api/v1/namespaces/#{namespace}/pods", query: %{"labelSelector" => label_selector}) do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:error, _} = err -> err
    end
  end

  @doc """
  GETs a single Pod by name from `namespace`. The dispatch endpoint
  reads `spec.containers[0].image` to compare the polling Pod's
  image against the RunnerPool's spec.image — when the chart bumps
  the digest pin, idle Running Pods on the old image return 410
  Gone to drain themselves.
  """
  def get_pod(namespace, name) when is_binary(namespace) and is_binary(name) do
    get("/api/v1/namespaces/#{namespace}/pods/#{name}")
  end

  @doc """
  Strategic-merge PATCHes a Pod. The dispatch endpoint uses this
  to stamp owner labels on a polling Pod at the moment it claims
  a queue entry, so subsequent `max_concurrent` counts include
  the Pod immediately.
  """
  def patch_pod(namespace, name, patch_body) when is_binary(namespace) and is_binary(name) and is_map(patch_body) do
    request(:patch, "/api/v1/namespaces/#{namespace}/pods/#{name}",
      body: JSON.encode!(patch_body),
      headers: [{"content-type", "application/strategic-merge-patch+json"}]
    )
  end

  @doc """
  Deletes a runner Pod and its same-named per-Pod ServiceAccount.
  The runner-pool reconciler creates the two as RunnerPool siblings
  sharing one name (not parent/child), so deleting the Pod alone
  orphans the SA — mirror the controller's `reapRunner` and delete
  both. Used by `OrphanedStampedPodsWorker` to reclaim a Pod the
  reconciler can't scale down (it only reaps idle, un-stamped Pods,
  so an owner-stamped Pod whose claim has been released is otherwise
  pinned forever, holding its node's memory).

  Idempotent: a 404 on either resource (already gone) counts as
  success. Returns `:ok` when both deletes succeed or 404, otherwise
  `{:error, {pod_result, sa_result}}`.
  """
  def delete_runner(namespace, name, opts \\ []) when is_binary(namespace) and is_binary(name) do
    pod_result = delete("/api/v1/namespaces/#{namespace}/pods/#{name}", opts)
    sa_result = delete("/api/v1/namespaces/#{namespace}/serviceaccounts/#{name}", opts)

    case {ok_or_absent(pod_result), ok_or_absent(sa_result)} do
      {:ok, :ok} -> :ok
      _ -> {:error, {pod_result, sa_result}}
    end
  end

  defp ok_or_absent(:ok), do: :ok
  defp ok_or_absent({:error, :not_found}), do: :ok
  defp ok_or_absent(other), do: other

  # ----- Manifest dispatch -----

  defp manifest_path(%{
         "apiVersion" => "kura.tuist.dev/v1alpha1",
         "kind" => "KuraInstance",
         "metadata" => %{"namespace" => namespace, "name" => name}
       }) do
    {:ok, "/apis/kura.tuist.dev/v1alpha1/namespaces/#{namespace}/kurainstances/#{name}"}
  end

  defp manifest_path(%{
         "apiVersion" => "v1",
         "kind" => "Secret",
         "metadata" => %{"namespace" => namespace, "name" => name}
       }) do
    {:ok, "/api/v1/namespaces/#{namespace}/secrets/#{name}"}
  end

  defp manifest_path(%{"kind" => kind}), do: {:error, "unsupported Kubernetes manifest kind #{kind}"}
  defp manifest_path(_), do: {:error, "unsupported Kubernetes manifest"}

  # ----- Request infrastructure -----

  defp request(method, path, options) do
    opts = Keyword.get(options, :opts, [])
    headers = Keyword.get(options, :headers, [{"content-type", "application/json"}])
    query = Keyword.get(options, :query, %{})
    body = Keyword.get(options, :body)

    with {:ok, config} <- config(opts) do
      req_opts =
        maybe_put_body(
          [
            method: method,
            url: url(config, path),
            headers: request_headers(config, headers),
            params: query,
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

  defp kubeconfig_mode?(opts), do: Keyword.get(opts, :mode) in [:kubeconfig, "kubeconfig"]

  defp write_temp(contents, label, extname) do
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
         {:ok, context} <- kubeconfig_current_context(kubeconfig, opts),
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
      contents = Keyword.get(opts, :kubeconfig) -> {:ok, contents}
      path = Keyword.get(opts, :kubeconfig_path) -> kubeconfig_from_path(path)
      true -> {:error, "Kubernetes kubeconfig client mode requires :kubeconfig or :kubeconfig_path"}
    end
  end

  defp kubeconfig_from_path(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, "cannot read Kubernetes kubeconfig #{path}: #{inspect(reason)}"}
    end
  end

  defp parse_kubeconfig(contents) do
    case YamlElixir.read_from_string(contents) do
      {:ok, kubeconfig} when is_map(kubeconfig) -> {:ok, kubeconfig}
      {:ok, _} -> {:error, "Kubernetes kubeconfig is not a YAML map"}
      {:error, reason} -> {:error, "invalid Kubernetes kubeconfig: #{inspect(reason)}"}
    end
  end

  defp kubeconfig_current_context(kubeconfig, opts) do
    name = Keyword.get(opts, :context) || Map.get(kubeconfig, "current-context")

    kubeconfig_context(kubeconfig, name)
  end

  defp kubeconfig_context(kubeconfig, name) when is_binary(name) and name != "" do
    kubeconfig_named_entry(kubeconfig, "contexts", name)
  end

  defp kubeconfig_context(_kubeconfig, _name), do: {:error, "Kubernetes kubeconfig has no current-context"}

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

  defp parse_sa_principal(%{"username" => "system:serviceaccount:" <> rest, "uid" => uid}) do
    case String.split(rest, ":", parts: 2) do
      [namespace, name] when namespace != "" and name != "" ->
        {:ok, %{namespace: namespace, name: name, uid: uid}}

      _ ->
        {:error, :not_service_account}
    end
  end

  defp parse_sa_principal(_), do: {:error, :not_service_account}
end
