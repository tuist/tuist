defmodule Tuist.Kura.Provider.HelmKubernetes do
  @moduledoc """
  Runs Kura as a `StatefulSet` on a managed Kubernetes cluster, deployed
  via the Helm chart at `kura/ops/helm/kura/`.

  `provision/3` is deterministic: it computes the helm release name and
  returns it as the opaque ref. The first install happens in `rollout/2`,
  which renders per-instance values and shells out to the chart's
  `rollout.sh`. The script owns the partitioned-warm-rollout state
  machine; we are a transport. `destroy/2` is `helm uninstall --wait`.

  Region `provider_config` keys read by this module:

    * `:cluster_id` (required) — kubeconfig-secret lookup key + helm
      release suffix.
    * `:helm_overlay` (required) — selects
      `values-managed-provider-<overlay>.yaml` to layer over
      `values-managed.yaml`.
    * `:public_host_template` — template with `{account_handle}` and
      `{cluster_id}` placeholders. Used to generate the public URL and
      Ingress host.
    * `:public_url` — fallback when `:public_host_template` is unset
      (e.g. local kind, where there is no public DNS).
    * `:kind_cluster_name` — when set and no kubeconfig secret is
      configured, autodiscover via `kind get kubeconfig` and (in dev/test)
      auto-create the cluster.
  """

  @behaviour Tuist.Kura.Provider

  alias Tuist.Kura.KuraServer
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Specs

  require Logger

  @namespace "kura"

  ## Provider callbacks

  @impl true
  def provision(%{name: handle}, %Regions{} = region, %KuraServer{}) do
    {:ok, release_name(handle, region), %{}}
  end

  @impl true
  def rollout(release, %{
        image_tag: image_tag,
        account: account,
        server: %KuraServer{} = server,
        region: %Regions{} = region,
        on_log_line: on_log_line
      }) do
    with {:ok, chart} <- chart_path(),
         {:ok, kubeconfig} <- write_kubeconfig(region),
         {:ok, values} <- write_instance_values(image_tag, account, region, server, chart) do
      args = [
        Path.join(chart, "rollout.sh"),
        release,
        @namespace,
        "-f",
        Path.join(chart, "values-managed.yaml"),
        "-f",
        Path.join(chart, "values-managed-provider-#{helm_overlay(region)}.yaml"),
        "-f",
        values
      ]

      case shell(args, kubeconfig, on_log_line) do
        :ok -> :ok
        {:error, status} -> {:error, "rollout exited with status #{status}"}
      end
    end
  end

  @impl true
  def destroy(release, %Regions{} = region) do
    case write_kubeconfig(region) do
      {:ok, kubeconfig} ->
        args = ["helm", "uninstall", release, "--namespace", @namespace, "--ignore-not-found", "--wait"]
        _ = shell(args, kubeconfig, &drop_log/2)
        :ok

      {:error, reason} ->
        # An orphaned helm release is preferable to a stuck `:destroying`
        # row that blocks re-provisioning. Operators can clean up by hand.
        Logger.warning("[Kura.HelmKubernetes] destroy(#{release}) skipped: #{inspect(reason)}")
        :ok
    end
  end

  @impl true
  def public_url(handle, %Regions{provider_config: config}, _ref) do
    cond do
      template = config[:public_host_template] ->
        "https://" <> interpolate_host(template, handle, config)

      url = config[:public_url] ->
        url

      true ->
        raise ArgumentError,
              "region #{inspect(config[:cluster_id])} has neither :public_host_template nor :public_url"
    end
  end

  @impl true
  def current_image_tag(release, %Regions{} = region) do
    with {:ok, kubeconfig} <- write_kubeconfig(region) do
      args = [
        "kubectl",
        "--kubeconfig",
        kubeconfig,
        "-n",
        @namespace,
        "get",
        "statefulset",
        release,
        "-o",
        "jsonpath={.spec.template.spec.containers[?(@.name=='kura')].image}"
      ]

      case MuonTrap.cmd("env", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, parse_image_tag(output)}
        {output, _} -> {:error, String.trim(output)}
      end
    end
  end

  @doc """
  The helm release name for `(account, region)`. Public so tests and
  ops scripts can compute it without going through `provision/3`.
  """
  def release_name(handle, %Regions{provider_config: %{cluster_id: cluster_id}}) do
    "kura-#{handle}-#{cluster_id}"
  end

  ## Values rendering

  defp write_instance_values(image_tag, account, region, server, chart) do
    yaml = render_values(image_tag, account, region, server, chart)
    write_temp(yaml, "instance.yaml")
  end

  defp render_values(image_tag, account, %Regions{} = region, %KuraServer{} = server, chart) do
    release = release_name(account.name, region)
    hook_script = chart |> Path.join("hooks/tuist.lua") |> File.read!() |> with_lua_prelude()

    """
    fullnameOverride: #{release}
    image:
      tag: "#{image_tag}"
    config:
      tenantId: "#{account.name}"
      region: "#{region.id}"
    extension:
      enabled: true
      script: |
    #{indent(hook_script, 8)}
    extraEnv:
    #{render_extension_env(region)}
    #{render_resources(server)}
    #{render_persistence(server)}
    #{render_ingress(region, account.name)}
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: kura
            app.kubernetes.io/instance: #{release}
    """
  end

  defp render_resources(%KuraServer{spec: spec}) do
    case Specs.resource_overlay(spec) do
      %{"resources" => %{"requests" => req, "limits" => lim}} ->
        """
        resources:
          requests:
            cpu: "#{req["cpu"]}"
            memory: "#{req["memory"]}"
          limits:
            memory: "#{lim["memory"]}"\
        """

      _ ->
        ""
    end
  end

  defp render_resources(_), do: ""

  defp render_persistence(%KuraServer{volume_size_gi: gi}) when is_integer(gi) and gi > 0 do
    "persistence:\n  size: #{gi}Gi"
  end

  defp render_persistence(_), do: ""

  defp render_ingress(%Regions{provider_config: config}, handle) do
    case config[:public_host_template] do
      nil ->
        # Local kind has no public DNS; the chart's local overlay
        # disables Ingress entirely.
        ""

      template ->
        host = interpolate_host(template, handle, config)

        """
        ingress:
          hosts:
            - host: #{host}
              paths:
                - path: /
                  pathType: Prefix
          tls:
            - secretName: tuist-tls-cloudflare-origin-kura
              hosts:
                - #{host}\
        """
    end
  end

  defp render_extension_env(%Regions{} = region) do
    [
      yaml_env("KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE", "true"),
      yaml_env("KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE", "true"),
      # Kura's hook timeout defaults to 25ms — below a cold HTTPS round
      # trip. Cache hits stay sub-ms regardless.
      yaml_env("KURA_EXTENSION_HOOK_TIMEOUT_MS", "5000"),
      yaml_env("KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL", tuist_base_url(region)),
      yaml_env("KURA_EXTENSION_HTTP_CLIENT_TUIST_CONNECT_TIMEOUT_MS", "3000"),
      yaml_env("KURA_EXTENSION_HTTP_CLIENT_TUIST_REQUEST_TIMEOUT_MS", "4000")
      | signer_env()
    ]
    |> Enum.join("\n")
  end

  defp signer_env do
    case license_signing_key() do
      nil ->
        []

      key ->
        [
          yaml_env("KURA_EXTENSION_SIGNER_TUIST_ALGORITHM", "hmac-sha256"),
          yaml_env("KURA_EXTENSION_SIGNER_TUIST_SECRET", key)
        ]
    end
  end

  defp yaml_env(name, value) do
    "  - name: #{name}\n    value: '#{escape_yaml(value)}'"
  end

  defp escape_yaml(value), do: String.replace(value || "", "'", "''")

  defp license_signing_key do
    case Tuist.License.get_license() do
      {:ok, %{signing_key: key}} when is_binary(key) and key != "" -> key
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # Kura's per-client HTTP config doesn't accept static headers. We
  # inject the verify endpoint's shared secret as a Lua global the hook
  # picks up at call time.
  defp with_lua_prelude(script) do
    auth =
      case Tuist.Environment.kura_verify_token() do
        token when is_binary(token) and token != "" -> "Bearer #{token}"
        _ -> ""
      end

    "tuist_verify_authorization = #{lua_string(auth)}\n" <> script
  end

  defp lua_string(value) do
    escaped = value |> String.replace("\\", "\\\\") |> String.replace(~s("), ~s(\\"))
    ~s("#{escaped}")
  end

  # Kura pods reach the Tuist server via this base URL. For local kind
  # we rewrite `localhost` to `host.docker.internal` because the pod's
  # loopback is the pod itself.
  defp tuist_base_url(%Regions{provider_config: %{helm_overlay: "local"}}) do
    Tuist.Environment.app_url()
    |> URI.parse()
    |> rewrite_loopback("host.docker.internal")
    |> URI.to_string()
  end

  defp tuist_base_url(_), do: Tuist.Environment.app_url()

  defp rewrite_loopback(%URI{host: host} = uri, replacement)
       when host in ["localhost", "127.0.0.1", "0.0.0.0"] do
    %{uri | host: replacement}
  end

  defp rewrite_loopback(uri, _), do: uri

  defp interpolate_host(template, handle, %{cluster_id: cluster_id}) do
    template
    |> String.replace("{account_handle}", handle)
    |> String.replace("{cluster_id}", cluster_id)
  end

  defp indent(text, n) do
    pad = String.duplicate(" ", n)
    text |> String.split("\n") |> Enum.map_join("\n", &(pad <> &1))
  end

  defp parse_image_tag(output) do
    case output |> String.trim() |> String.split(":", parts: 2) do
      [_image, tag] when tag != "" -> tag
      _ -> nil
    end
  end

  defp helm_overlay(%Regions{provider_config: %{helm_overlay: overlay}}), do: overlay

  ## Kubeconfig discovery

  defp chart_path do
    case Application.get_env(:tuist, :kura_chart_path) do
      nil ->
        {:error, "kura_chart_path is not configured"}

      path when is_binary(path) ->
        if File.dir?(path),
          do: {:ok, path},
          else: {:error, "kura_chart_path #{path} is not a directory"}
    end
  end

  defp write_kubeconfig(%Regions{} = region) do
    with {:ok, contents} <- resolve_kubeconfig(region),
         {:ok, path} <- write_temp(contents, "kubeconfig") do
      {:ok, path}
    end
  end

  defp resolve_kubeconfig(%Regions{provider_config: config} = region) do
    case Tuist.Environment.kura_kubeconfig(config[:cluster_id]) do
      kc when is_binary(kc) and kc != "" -> {:ok, kc}
      _ -> autodiscover_kubeconfig(region)
    end
  end

  defp autodiscover_kubeconfig(%Regions{provider_config: %{kind_cluster_name: name}}) do
    cond do
      System.find_executable("kind") == nil ->
        {:error, "no kubeconfig configured and kind is not on PATH"}

      kc = kind_kubeconfig(name) ->
        {:ok, kc}

      Tuist.Environment.dev?() or Tuist.Environment.test?() ->
        with :ok <- create_kind_cluster(name),
             kc when is_binary(kc) <- kind_kubeconfig(name) do
          {:ok, kc}
        else
          _ -> {:error, "failed to bring up kind cluster `#{name}`"}
        end

      true ->
        {:error, "kind cluster `#{name}` not found and auto-create is dev-only"}
    end
  end

  defp autodiscover_kubeconfig(%Regions{provider_config: %{cluster_id: id}}) do
    {:error, "no kubeconfig configured for cluster #{id}"}
  end

  defp kind_kubeconfig(name) do
    case MuonTrap.cmd("kind", ["get", "kubeconfig", "--name", name], stderr_to_stdout: true) do
      {kc, 0} when is_binary(kc) and kc != "" -> kc
      _ -> nil
    end
  end

  defp create_kind_cluster(name) do
    Logger.info("[Kura.HelmKubernetes] creating kind cluster `#{name}` (~90s)")
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

  ## Shell

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
         :ok <- File.write(path, contents) do
      {:ok, path}
    else
      {:error, reason} -> {:error, "failed to write #{label}: #{inspect(reason)}"}
    end
  end

  defp drop_log(_line, _stream), do: :ok
end
