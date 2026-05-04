defmodule Tuist.Kura.Provisioner.HetznerCloud do
  @moduledoc """
  Provisions Kura directly on Hetzner Cloud servers owned by the Tuist
  server.

  Production Kura should not depend on spare capacity in the Syself
  Kubernetes cluster. This provisioner makes the server the control
  plane for the machine lifecycle: create or reuse the VM through
  Hetzner Cloud, reconcile the public DNS record, then roll out Kura by
  SSHing into the VM and updating a Docker Compose stack.

  Region `provisioner_config` keys read by this module:

    * `:target_id` - audit identifier stored on deployment rows.
    * `:location` - Hetzner location, for example `"fsn1"`.
    * `:image` - Hetzner image name. Defaults to `"ubuntu-24.04"`.
    * `:public_host_template` - template with `{account_handle}`,
      `{region}`, and `{target_id}` placeholders.
    * `:firewall_ids` - optional list of pre-created Hetzner firewall IDs.
  """

  @behaviour Tuist.Kura.Provisioner

  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.SSHClient

  require Logger

  @hcloud_base_url "https://api.hetzner.cloud/v1"
  @cloudflare_base_url "https://api.cloudflare.com/client/v4"
  @install_root "/opt/tuist/kura"
  @cache_dir "/var/cache/kura"
  @hook_remote_path "#{@install_root}/hooks/tuist.lua"
  @compose_remote_path "#{@install_root}/docker-compose.yml"
  @env_remote_path "#{@install_root}/kura.env"
  @caddy_remote_path "#{@install_root}/Caddyfile"

  @server_types %{
    small: "cx22",
    medium: "cx32",
    large: "cx42"
  }

  @impl true
  def provision(account, %Regions{} = region, %Server{} = server) do
    with {:ok, token} <- hcloud_token(),
         {:ok, _public_key} <- ssh_public_key(),
         {:ok, servers} <- list_servers(token, account, region),
         {:ok, hcloud_server} <- provision_server(servers, token, account, region, server),
         {:ok, ip} <- public_ipv4(hcloud_server),
         host = public_host(account.name, region),
         :ok <- ensure_dns_record(host, ip) do
      {:ok, encode_ref(hcloud_server["id"], host)}
    end
  end

  @impl true
  def rollout(
        ref,
        %{
          image_tag: image_tag,
          account: account,
          server: %Server{} = server,
          region: %Regions{} = region,
          on_log_line: on_log_line
        } = inputs
      ) do
    with {:ok, decoded_ref} <- decode_ref(ref),
         {:ok, token} <- hcloud_token(),
         {:ok, hcloud_server} <- get_server(token, decoded_ref.server_id),
         {:ok, ip} <- public_ipv4(hcloud_server),
         {:ok, chart} <- chart_path(inputs),
         {:ok, hook_script} <- read_hook_script(chart),
         {:ok, connection} <- connect(ip) do
      close_after(connection, fn ->
        rollout_over_ssh(connection, decoded_ref.host, image_tag, account, region, server, hook_script, on_log_line)
      end)
    end
  end

  @impl true
  def destroy(ref, %Regions{}) do
    with {:ok, decoded_ref} <- decode_ref(ref),
         {:ok, token} <- hcloud_token(),
         :ok <- delete_dns_record(decoded_ref.host) do
      delete_server(token, decoded_ref.server_id)
    end
  end

  @impl true
  def public_url(account_handle, %Regions{} = region, ref) do
    host =
      case decode_ref(ref) do
        {:ok, %{host: host}} -> host
        {:error, _} -> public_host(account_handle, region)
      end

    "https://#{host}"
  end

  @impl true
  def current_image_tag(ref, %Regions{}) do
    with {:ok, decoded_ref} <- decode_ref(ref),
         {:ok, token} <- hcloud_token(),
         {:ok, hcloud_server} <- get_server(token, decoded_ref.server_id),
         {:ok, ip} <- public_ipv4(hcloud_server),
         {:ok, connection} <- connect(ip) do
      close_after(connection, fn ->
        with {:ok, image} <- SSHClient.run_command(connection, "docker inspect --format '{{.Config.Image}}' tuist-kura") do
          {:ok, image_tag_from_image(image)}
        end
      end)
    end
  end

  @impl true
  def resources_for(%Server{spec: spec}) do
    case Map.get(@server_types, spec) do
      nil -> %{}
      server_type -> %{server_type: server_type}
    end
  end

  defp provision_server([], token, account, region, server) do
    create_server(token, account, region, server)
  end

  defp provision_server([hcloud_server], _token, _account, _region, _server), do: {:ok, hcloud_server}

  defp provision_server(servers, _token, account, region, _server) do
    ids = Enum.map_join(servers, ", ", & &1["id"])
    {:error, "multiple Hetzner Kura servers found for account #{account.id} in #{region.id}: #{ids}"}
  end

  defp list_servers(token, account, region) do
    selector = account |> labels(region) |> Enum.map_join(",", fn {key, value} -> "#{key}=#{value}" end)

    case Req.get("#{@hcloud_base_url}/servers",
           headers: hcloud_headers(token),
           params: [label_selector: selector],
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: 200, body: %{"servers" => servers}}} -> {:ok, servers}
      response -> {:error, hcloud_error(response)}
    end
  end

  defp create_server(token, account, %Regions{} = region, %Server{} = server) do
    body =
      maybe_put(
        %{
          name: server_name(account.name, region),
          server_type: Map.fetch!(resources_for(server), :server_type),
          image: region.provisioner_config[:image] || "ubuntu-24.04",
          location: region.provisioner_config[:location],
          start_after_create: true,
          public_net: %{enable_ipv4: true, enable_ipv6: false},
          labels: labels(account, region),
          user_data: cloud_init()
        },
        :firewalls,
        firewall_refs(region)
      )

    case Req.post("#{@hcloud_base_url}/servers",
           headers: hcloud_headers(token),
           json: body,
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: status, body: %{"server" => hcloud_server}}} when status in [200, 201, 202] ->
        {:ok, hcloud_server}

      response ->
        {:error, hcloud_error(response)}
    end
  end

  defp get_server(token, server_id) do
    case Req.get("#{@hcloud_base_url}/servers/#{server_id}",
           headers: hcloud_headers(token),
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: 200, body: %{"server" => hcloud_server}}} -> {:ok, hcloud_server}
      response -> {:error, hcloud_error(response)}
    end
  end

  defp delete_server(token, server_id) do
    case Req.delete("#{@hcloud_base_url}/servers/#{server_id}",
           headers: hcloud_headers(token),
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: status}} when status in [200, 202, 204, 404] -> :ok
      response -> {:error, hcloud_error(response)}
    end
  end

  defp ensure_dns_record(host, ip) do
    with {:ok, token} <- cloudflare_token(),
         {:ok, zone_id} <- cloudflare_zone_id(),
         {:ok, records} <- list_dns_records(token, zone_id, host) do
      body = dns_record_body(host, ip)

      case records do
        [] -> create_dns_record(token, zone_id, body)
        [%{"id" => id} | _] -> update_dns_record(token, zone_id, id, body)
      end
    end
  end

  defp delete_dns_record(host) do
    with {:ok, token} <- cloudflare_token(),
         {:ok, zone_id} <- cloudflare_zone_id(),
         {:ok, records} <- list_dns_records(token, zone_id, host) do
      Enum.reduce_while(records, :ok, fn
        %{"id" => id}, :ok ->
          case Req.delete("#{@cloudflare_base_url}/zones/#{zone_id}/dns_records/#{id}",
                 headers: cloudflare_headers(token),
                 finch: Tuist.Finch
               ) do
            {:ok, %Req.Response{status: status}} when status in [200, 202, 204, 404] -> {:cont, :ok}
            response -> {:halt, {:error, cloudflare_error(response)}}
          end
      end)
    end
  end

  defp list_dns_records(token, zone_id, host) do
    case Req.get("#{@cloudflare_base_url}/zones/#{zone_id}/dns_records",
           headers: cloudflare_headers(token),
           params: [type: "A", name: host],
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true, "result" => records}}} -> {:ok, records}
      response -> {:error, cloudflare_error(response)}
    end
  end

  defp create_dns_record(token, zone_id, body) do
    case Req.post("#{@cloudflare_base_url}/zones/#{zone_id}/dns_records",
           headers: cloudflare_headers(token),
           json: body,
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: status, body: %{"success" => true}}} when status in [200, 201] -> :ok
      response -> {:error, cloudflare_error(response)}
    end
  end

  defp update_dns_record(token, zone_id, record_id, body) do
    case Req.put("#{@cloudflare_base_url}/zones/#{zone_id}/dns_records/#{record_id}",
           headers: cloudflare_headers(token),
           json: body,
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true}}} -> :ok
      response -> {:error, cloudflare_error(response)}
    end
  end

  defp dns_record_body(host, ip) do
    %{
      type: "A",
      name: host,
      content: ip,
      ttl: 1,
      proxied: false
    }
  end

  defp rollout_over_ssh(connection, host, image_tag, account, region, server, hook_script, on_log_line) do
    env_file = env_file(image_tag, account, region, server)
    compose_file = compose_file()
    caddy_file = caddy_file(host)

    with :ok <- run_remote(connection, "mkdir -p #{@install_root}/hooks #{@cache_dir}", on_log_line),
         :ok <- upload(connection, env_file, @env_remote_path, 0o100600),
         :ok <- upload(connection, compose_file, @compose_remote_path, 0o100644),
         :ok <- upload(connection, caddy_file, @caddy_remote_path, 0o100644),
         :ok <- upload(connection, hook_script, @hook_remote_path, 0o100600),
         :ok <-
           run_remote(
             connection,
             "docker compose -f #{@compose_remote_path} --env-file #{@env_remote_path} pull",
             on_log_line
           ),
         :ok <-
           run_remote(
             connection,
             "docker compose -f #{@compose_remote_path} --env-file #{@env_remote_path} up -d --remove-orphans",
             on_log_line
           ) do
      run_remote(connection, "docker image prune -f", on_log_line)
    end
  end

  defp upload(connection, contents, remote_path, permissions) do
    with {:ok, path} <- write_temp(contents, Path.basename(remote_path)) do
      SSHClient.transfer_file(connection, path, remote_path, permissions: permissions)
    end
  end

  defp run_remote(connection, command, on_log_line) do
    on_log_line.(command, :stdout)

    case SSHClient.run_command(connection, command) do
      {:ok, output} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.each(&on_log_line.(&1, :stdout))

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connect(ip) do
    with {:ok, private_key} <- ssh_private_key(),
         {:ok, user_dir} <- write_ssh_key(private_key) do
      connect_with_retry(ip, user_dir, 30)
    end
  end

  defp connect_with_retry(_ip, _user_dir, 0), do: {:error, "timed out waiting for SSH"}

  defp connect_with_retry(ip, user_dir, attempts) do
    case SSHClient.connect(String.to_charlist(ip), 22,
           user: ~c"root",
           user_dir: String.to_charlist(user_dir),
           silently_accept_hosts: true,
           auth_methods: ~c"publickey",
           user_interaction: false
         ) do
      {:ok, connection} ->
        {:ok, connection}

      {:error, reason} ->
        Logger.debug("[Kura.HetznerCloud] SSH not ready for #{ip}: #{inspect(reason)}")
        Process.sleep(5_000)
        connect_with_retry(ip, user_dir, attempts - 1)
    end
  end

  defp close_after(connection, fun) do
    fun.()
  after
    SSHClient.close(connection)
  end

  defp write_ssh_key(private_key) do
    user_dir = Briefly.create!(type: :directory)
    private_key_path = Path.join(user_dir, "id_ed25519")

    with :ok <- File.write(private_key_path, private_key),
         :ok <- File.chmod(private_key_path, 0o600) do
      {:ok, user_dir}
    else
      {:error, reason} -> {:error, "failed to write SSH key: #{inspect(reason)}"}
    end
  end

  defp env_file(image_tag, account, %Regions{} = region, %Server{} = server) do
    [
      {"KURA_IMAGE_TAG", image_tag},
      {"KURA_PORT", "4000"},
      {"KURA_GRPC_PORT", "50051"},
      {"KURA_INTERNAL_PORT", "7443"},
      {"KURA_TENANT_ID", account.name},
      {"KURA_REGION", region.id},
      {"KURA_TMP_DIR", "/tmp/kura"},
      {"KURA_DATA_DIR", @cache_dir},
      {"KURA_NODE_URL", "http://kura:7443"},
      {"KURA_PEERS", "http://kura:7443"},
      {"KURA_EXTENSION_ENABLED", "true"},
      {"KURA_EXTENSION_SCRIPT_PATH", "/etc/kura/extensions/tuist.lua"},
      {"KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE", "true"},
      {"KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE", "true"},
      {"KURA_EXTENSION_HOOK_TIMEOUT_MS", "5000"},
      {"KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL", Tuist.Environment.app_url()},
      {"KURA_EXTENSION_HTTP_CLIENT_TUIST_CONNECT_TIMEOUT_MS", "3000"},
      {"KURA_EXTENSION_HTTP_CLIENT_TUIST_REQUEST_TIMEOUT_MS", "4000"}
      | runtime_secret_env()
    ]
    |> Kernel.++(resource_env(server))
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{escape_env(value)}" end)
    |> Kernel.<>("\n")
  end

  defp runtime_secret_env do
    jwt_env() ++ signer_env()
  end

  defp jwt_env do
    case Tuist.Environment.secret_key_tokens() do
      nil ->
        []

      secret ->
        [
          {"KURA_EXTENSION_JWT_VERIFIER_TUIST_ALGORITHM", "HS512"},
          {"KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET", secret},
          {"KURA_EXTENSION_JWT_VERIFIER_TUIST_ISSUER", "tuist"}
        ]
    end
  end

  defp signer_env do
    case license_signing_key() do
      nil ->
        []

      key ->
        [
          {"KURA_EXTENSION_SIGNER_TUIST_ALGORITHM", "hmac-sha256"},
          {"KURA_EXTENSION_SIGNER_TUIST_SECRET", key}
        ]
    end
  end

  defp resource_env(%Server{spec: :small}) do
    [
      {"KURA_MEMORY_SOFT_LIMIT_BYTES", "751619276"},
      {"KURA_MEMORY_HARD_LIMIT_BYTES", "912680550"}
    ]
  end

  defp resource_env(%Server{spec: :medium}) do
    [
      {"KURA_MEMORY_SOFT_LIMIT_BYTES", "1503238553"},
      {"KURA_MEMORY_HARD_LIMIT_BYTES", "1825361100"}
    ]
  end

  defp resource_env(%Server{spec: :large}) do
    [
      {"KURA_MEMORY_SOFT_LIMIT_BYTES", "3006477107"},
      {"KURA_MEMORY_HARD_LIMIT_BYTES", "3650722201"}
    ]
  end

  defp resource_env(_), do: []

  defp compose_file do
    """
    services:
      kura:
        image: ghcr.io/tuist/kura:${KURA_IMAGE_TAG}
        container_name: tuist-kura
        restart: unless-stopped
        env_file:
          - kura.env
        volumes:
          - #{@cache_dir}:#{@cache_dir}
          - ./hooks:/etc/kura/extensions:ro
        expose:
          - "4000"
          - "50051"
          - "7443"

      caddy:
        image: caddy:2-alpine
        container_name: tuist-kura-caddy
        restart: unless-stopped
        ports:
          - "80:80"
          - "443:443"
        volumes:
          - ./Caddyfile:/etc/caddy/Caddyfile:ro
          - caddy_data:/data
          - caddy_config:/config
        depends_on:
          - kura

    volumes:
      caddy_data:
      caddy_config:
    """
  end

  defp caddy_file(host) do
    """
    #{host} {
      encode zstd gzip
      reverse_proxy kura:4000
    }
    """
  end

  defp cloud_init do
    ssh_key = Tuist.Environment.kura_ssh_public_key()

    """
    #cloud-config
    package_update: true
    packages:
      - ca-certificates
      - curl
      - ufw
    users:
      - default
      - name: root
        ssh_authorized_keys:
          - #{ssh_key}
    runcmd:
      - mkdir -p #{@install_root}/hooks #{@cache_dir}
      - curl -fsSL https://get.docker.com | sh
      - ufw allow 22/tcp
      - ufw allow 80/tcp
      - ufw allow 443/tcp
      - ufw --force enable
    """
  end

  defp labels(account, region) do
    %{
      tuist_service: "kura",
      tuist_account_id: "#{account.id}",
      tuist_account_handle: dns_handle(account.name),
      tuist_region: region.id
    }
  end

  defp public_host(account_handle, %Regions{} = region) do
    template = region.provisioner_config[:public_host_template] || "{account_handle}-{region}.kura.tuist.dev"

    template
    |> String.replace("{account_handle}", dns_handle(account_handle))
    |> String.replace("{region}", region.id)
    |> String.replace("{target_id}", region.provisioner_config[:target_id] || region.id)
    |> String.replace(
      "{cluster_id}",
      region.provisioner_config[:cluster_id] || region.provisioner_config[:target_id] || region.id
    )
  end

  defp server_name(account_handle, %Regions{} = region), do: "kura-#{dns_handle(account_handle)}-#{region.id}"

  defp dns_handle(handle) do
    handle
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.trim("-")
  end

  defp public_ipv4(%{"public_net" => %{"ipv4" => %{"ip" => ip}}}) when is_binary(ip), do: {:ok, ip}
  defp public_ipv4(_), do: {:error, "Hetzner server has no public IPv4 address"}

  defp chart_path(inputs) do
    case Map.get(inputs, :chart_path) || Application.get_env(:tuist, :kura_chart_path) do
      nil ->
        {:error, "kura_chart_path is not configured"}

      path when is_binary(path) ->
        if File.dir?(path), do: {:ok, path}, else: {:error, "kura_chart_path #{path} is not a directory"}
    end
  end

  defp read_hook_script(chart) do
    case File.read(Path.join([chart, "hooks", "tuist.lua"])) do
      {:ok, script} -> {:ok, script}
      {:error, reason} -> {:error, "failed to read Kura hook script: #{inspect(reason)}"}
    end
  end

  defp write_temp(contents, label) do
    with {:ok, path} <- Briefly.create(prefix: "kura-#{label}-"),
         :ok <- File.write(path, contents),
         :ok <- File.chmod(path, 0o600) do
      {:ok, path}
    else
      {:error, reason} -> {:error, "failed to write #{label}: #{inspect(reason)}"}
    end
  end

  defp firewall_refs(%Regions{provisioner_config: %{firewall_ids: ids}}) when is_list(ids) do
    Enum.map(ids, &%{firewall: &1})
  end

  defp firewall_refs(_), do: []

  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp hcloud_token do
    case Tuist.Environment.kura_hetzner_api_token() do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, "kura Hetzner API token is not configured"}
    end
  end

  defp cloudflare_token do
    case Tuist.Environment.kura_cloudflare_api_token() do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, "kura Cloudflare API token is not configured"}
    end
  end

  defp cloudflare_zone_id do
    case Tuist.Environment.kura_cloudflare_zone_id() do
      zone_id when is_binary(zone_id) and zone_id != "" -> {:ok, zone_id}
      _ -> {:error, "kura Cloudflare zone ID is not configured"}
    end
  end

  defp ssh_private_key do
    case Tuist.Environment.kura_ssh_private_key() do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, "kura SSH private key is not configured"}
    end
  end

  defp ssh_public_key do
    case Tuist.Environment.kura_ssh_public_key() do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, "kura SSH public key is not configured"}
    end
  end

  defp hcloud_headers(token), do: [{"Authorization", "Bearer #{token}"}]
  defp cloudflare_headers(token), do: [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

  defp encode_ref(id, host), do: "hcloud:#{id}:#{host}"

  defp decode_ref("hcloud:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [server_id, host] when server_id != "" and host != "" -> {:ok, %{server_id: server_id, host: host}}
      _ -> {:error, "invalid Hetzner provisioner ref"}
    end
  end

  defp decode_ref(_), do: {:error, "invalid Hetzner provisioner ref"}

  defp license_signing_key do
    case Tuist.License.get_license() do
      {:ok, %{signing_key: key}} when is_binary(key) and key != "" -> key
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp image_tag_from_image(image) when is_binary(image) do
    image
    |> String.trim()
    |> String.split("/", trim: true)
    |> List.last()
    |> case do
      nil ->
        nil

      segment ->
        segment
        |> String.split("@", parts: 2)
        |> List.first()
        |> String.split(":", parts: 2)
        |> case do
          [_image, tag] when tag != "" -> tag
          _ -> nil
        end
    end
  end

  defp escape_env(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
  end

  defp hcloud_error({:ok, %Req.Response{status: status, body: body}}),
    do: "Hetzner API responded with #{status}: #{inspect(body)}"

  defp hcloud_error({:error, reason}), do: "Hetzner API request failed: #{inspect(reason)}"
  defp hcloud_error(other), do: "Hetzner API request failed: #{inspect(other)}"

  defp cloudflare_error({:ok, %Req.Response{status: status, body: body}}),
    do: "Cloudflare API responded with #{status}: #{inspect(body)}"

  defp cloudflare_error({:error, reason}), do: "Cloudflare API request failed: #{inspect(reason)}"
  defp cloudflare_error(other), do: "Cloudflare API request failed: #{inspect(other)}"
end
