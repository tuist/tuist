defmodule Tuist.Kura.Provisioner.HetznerCloudTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kura.Provisioner.HetznerCloud
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  setup :set_mimic_from_context

  describe "provision/3" do
    test "creates a Hetzner server and DNS record when none exists" do
      stub_required_environment()

      expect(Req, :get, 2, fn url, opts ->
        case url do
          "https://api.hetzner.cloud/v1/servers" ->
            assert opts[:params] == [
                     label_selector:
                       "tuist_service=kura,tuist_account_id=account-123,tuist_account_handle=tuist,tuist_region=eu"
                   ]

            {:ok, response(200, %{"servers" => []})}

          "https://api.cloudflare.com/client/v4/zones/zone-id/dns_records" ->
            assert opts[:params] == [type: "A", name: "tuist-eu.kura.tuist.dev"]
            {:ok, response(200, %{"success" => true, "result" => []})}
        end
      end)

      expect(Req, :post, 2, fn url, opts ->
        case url do
          "https://api.hetzner.cloud/v1/servers" ->
            json = opts[:json]

            assert json.name == "kura-tuist-eu"
            assert json.server_type == "cx22"
            assert json.image == "ubuntu-24.04"
            assert json.location == "fsn1"
            assert json.labels.tuist_service == "kura"
            assert json.labels.tuist_account_id == "account-123"
            assert json.labels.tuist_account_handle == "tuist"
            assert json.labels.tuist_region == "eu"
            assert json.user_data =~ "ssh-ed25519 test-key"

            {:ok,
             response(201, %{
               "server" => %{
                 "id" => 123,
                 "public_net" => %{"ipv4" => %{"ip" => "203.0.113.10"}}
               }
             })}

          "https://api.cloudflare.com/client/v4/zones/zone-id/dns_records" ->
            assert opts[:json] == %{
                     type: "A",
                     name: "tuist-eu.kura.tuist.dev",
                     content: "203.0.113.10",
                     ttl: 1,
                     proxied: false
                   }

            {:ok, response(200, %{"success" => true, "result" => %{"id" => "record-id"}})}
        end
      end)

      assert HetznerCloud.provision(account(), eu_region(), %Server{spec: :small, volume_size_gi: 50}) ==
               {:ok, "hcloud:123:tuist-eu.kura.tuist.dev"}
    end

    test "reuses an existing server and updates DNS" do
      stub_required_environment()

      expect(Req, :get, 2, fn url, _opts ->
        case url do
          "https://api.hetzner.cloud/v1/servers" ->
            {:ok,
             response(200, %{
               "servers" => [
                 %{
                   "id" => 456,
                   "name" => "kura-tuist-eu",
                   "public_net" => %{"ipv4" => %{"ip" => "203.0.113.11"}}
                 }
               ]
             })}

          "https://api.cloudflare.com/client/v4/zones/zone-id/dns_records" ->
            {:ok, response(200, %{"success" => true, "result" => [%{"id" => "record-id"}]})}
        end
      end)

      expect(Req, :put, fn "https://api.cloudflare.com/client/v4/zones/zone-id/dns_records/record-id", opts ->
        assert opts[:json].content == "203.0.113.11"
        {:ok, response(200, %{"success" => true, "result" => %{"id" => "record-id"}})}
      end)

      assert HetznerCloud.provision(account(), eu_region(), %Server{spec: :medium, volume_size_gi: 200}) ==
               {:ok, "hcloud:456:tuist-eu.kura.tuist.dev"}
    end

    test "returns an error when the Hetzner API token is missing" do
      stub(Tuist.Environment, :kura_hetzner_api_token, fn -> nil end)

      assert HetznerCloud.provision(account(), eu_region(), %Server{}) ==
               {:error, "kura Hetzner API token is not configured"}
    end

    test "returns an error when the SSH public key is missing" do
      stub(Tuist.Environment, :kura_hetzner_api_token, fn -> "hcloud-token" end)
      stub(Tuist.Environment, :kura_ssh_public_key, fn -> nil end)

      assert HetznerCloud.provision(account(), eu_region(), %Server{}) ==
               {:error, "kura SSH public key is not configured"}
    end
  end

  describe "rollout/2" do
    @tag :tmp_dir
    test "uploads runtime files and restarts Kura over SSH", %{tmp_dir: tmp_dir} do
      chart = chart_fixture(tmp_dir, "print('tuist hook')")

      stub_required_environment()
      stub(Tuist.Environment, :kura_ssh_private_key, fn -> "PRIVATE KEY" end)
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :secret_key_tokens, fn -> "jwt-secret" end)
      stub(Tuist.License, :get_license, fn -> {:ok, %{signing_key: "license-secret"}} end)

      expect(Req, :get, fn "https://api.hetzner.cloud/v1/servers/123", _opts ->
        {:ok,
         response(200, %{
           "server" => %{
             "id" => 123,
             "public_net" => %{"ipv4" => %{"ip" => "203.0.113.10"}}
           }
         })}
      end)

      expect(Tuist.SSHClient, :connect, fn ~c"203.0.113.10", 22, opts ->
        assert opts[:user] == ~c"root"
        assert opts[:silently_accept_hosts]
        {:ok, :ssh_connection}
      end)

      expect(Tuist.SSHClient, :run_command, 4, fn :ssh_connection, command ->
        send(self(), {:ssh_command, command})
        {:ok, "ok\n"}
      end)

      expect(Tuist.SSHClient, :transfer_file, 4, fn :ssh_connection, local_path, remote_path, opts ->
        send(self(), {:ssh_transfer, File.read!(local_path), remote_path, opts})
        :ok
      end)

      expect(Tuist.SSHClient, :close, fn :ssh_connection -> :ok end)

      assert :ok =
               HetznerCloud.rollout("hcloud:123:tuist-eu.kura.tuist.dev", %{
                 image_tag: "0.5.2",
                 account: %{name: "TUIST"},
                 server: %Server{spec: :small, volume_size_gi: 50},
                 region: eu_region(),
                 chart_path: chart,
                 on_log_line: fn _, _ -> :ok end
               })

      assert_receive {:ssh_command, "mkdir -p /opt/tuist/kura/hooks /var/cache/kura"}

      assert_receive {:ssh_command,
                      "docker compose -f /opt/tuist/kura/docker-compose.yml --env-file /opt/tuist/kura/kura.env pull"}

      assert_receive {:ssh_command,
                      "docker compose -f /opt/tuist/kura/docker-compose.yml --env-file /opt/tuist/kura/kura.env up -d --remove-orphans"}

      assert_receive {:ssh_transfer, env_file, "/opt/tuist/kura/kura.env", [permissions: 0o100600]}
      assert env_file =~ "KURA_IMAGE_TAG=0.5.2"
      assert env_file =~ "KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET=jwt-secret"
      assert env_file =~ "KURA_EXTENSION_SIGNER_TUIST_SECRET=license-secret"

      assert_receive {:ssh_transfer, compose_file, "/opt/tuist/kura/docker-compose.yml", [permissions: 0o100644]}
      assert compose_file =~ "ghcr.io/tuist/kura:${KURA_IMAGE_TAG}"
      assert compose_file =~ "caddy:2-alpine"

      assert_receive {:ssh_transfer, "print('tuist hook')", "/opt/tuist/kura/hooks/tuist.lua", [permissions: 0o100600]}
    end

    @tag :tmp_dir
    test "closes SSH when rollout fails after connecting", %{tmp_dir: tmp_dir} do
      chart = chart_fixture(tmp_dir, "print('tuist hook')")

      stub_required_environment()
      stub(Tuist.Environment, :kura_ssh_private_key, fn -> "PRIVATE KEY" end)
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :secret_key_tokens, fn -> nil end)
      stub(Tuist.License, :get_license, fn -> {:error, :missing} end)

      expect(Req, :get, fn "https://api.hetzner.cloud/v1/servers/123", _opts ->
        {:ok,
         response(200, %{
           "server" => %{
             "id" => 123,
             "public_net" => %{"ipv4" => %{"ip" => "203.0.113.10"}}
           }
         })}
      end)

      expect(Tuist.SSHClient, :connect, fn ~c"203.0.113.10", 22, _opts -> {:ok, :ssh_connection} end)

      expect(Tuist.SSHClient, :run_command, fn :ssh_connection, "mkdir -p /opt/tuist/kura/hooks /var/cache/kura" ->
        {:error, "mkdir failed"}
      end)

      expect(Tuist.SSHClient, :close, fn :ssh_connection -> send(self(), :ssh_closed) end)

      assert HetznerCloud.rollout("hcloud:123:tuist-eu.kura.tuist.dev", %{
               image_tag: "0.5.2",
               account: %{name: "TUIST"},
               server: %Server{spec: :small, volume_size_gi: 50},
               region: eu_region(),
               chart_path: chart,
               on_log_line: fn _, _ -> :ok end
             }) == {:error, "mkdir failed"}

      assert_received :ssh_closed
    end
  end

  describe "destroy/2" do
    test "deletes DNS and the Hetzner server" do
      stub_required_environment()

      expect(Req, :get, fn "https://api.cloudflare.com/client/v4/zones/zone-id/dns_records", opts ->
        assert opts[:params] == [type: "A", name: "tuist-eu.kura.tuist.dev"]
        {:ok, response(200, %{"success" => true, "result" => [%{"id" => "record-id"}]})}
      end)

      expect(Req, :delete, 2, fn url, _opts ->
        case url do
          "https://api.cloudflare.com/client/v4/zones/zone-id/dns_records/record-id" ->
            {:ok, response(200, %{"success" => true})}

          "https://api.hetzner.cloud/v1/servers/123" ->
            {:ok, response(204, %{})}
        end
      end)

      assert HetznerCloud.destroy("hcloud:123:tuist-eu.kura.tuist.dev", eu_region()) == :ok
    end

    test "treats a missing Hetzner server as already destroyed" do
      stub_required_environment()

      expect(Req, :get, fn "https://api.cloudflare.com/client/v4/zones/zone-id/dns_records", _opts ->
        {:ok, response(200, %{"success" => true, "result" => []})}
      end)

      expect(Req, :delete, fn "https://api.hetzner.cloud/v1/servers/123", _opts ->
        {:ok, response(404, %{"error" => %{"code" => "not_found"}})}
      end)

      assert HetznerCloud.destroy("hcloud:123:tuist-eu.kura.tuist.dev", eu_region()) == :ok
    end
  end

  describe "public_url/3" do
    test "uses the DNS host encoded in the provisioner ref" do
      assert HetznerCloud.public_url("other", eu_region(), "hcloud:123:tuist-eu.kura.tuist.dev") ==
               "https://tuist-eu.kura.tuist.dev"
    end
  end

  describe "resources_for/1" do
    test "maps customer-facing specs to Hetzner server types" do
      assert HetznerCloud.resources_for(%Server{spec: :small}) == %{server_type: "cx22"}
      assert HetznerCloud.resources_for(%Server{spec: :medium}) == %{server_type: "cx32"}
      assert HetznerCloud.resources_for(%Server{spec: :large}) == %{server_type: "cx42"}
    end
  end

  describe "current_image_tag/2" do
    test "reads the running Kura container image over SSH" do
      stub_required_environment()
      stub(Tuist.Environment, :kura_ssh_private_key, fn -> "PRIVATE KEY" end)

      expect(Req, :get, fn "https://api.hetzner.cloud/v1/servers/123", _opts ->
        {:ok,
         response(200, %{
           "server" => %{
             "id" => 123,
             "public_net" => %{"ipv4" => %{"ip" => "203.0.113.10"}}
           }
         })}
      end)

      expect(Tuist.SSHClient, :connect, fn ~c"203.0.113.10", 22, _opts -> {:ok, :ssh_connection} end)

      expect(Tuist.SSHClient, :run_command, fn :ssh_connection,
                                               "docker inspect --format '{{.Config.Image}}' tuist-kura" ->
        {:ok, "ghcr.io/tuist/kura:0.5.2\n"}
      end)

      expect(Tuist.SSHClient, :close, fn :ssh_connection -> :ok end)

      assert HetznerCloud.current_image_tag("hcloud:123:tuist-eu.kura.tuist.dev", eu_region()) == {:ok, "0.5.2"}
    end
  end

  defp stub_required_environment do
    stub(Tuist.Environment, :kura_hetzner_api_token, fn -> "hcloud-token" end)
    stub(Tuist.Environment, :kura_cloudflare_api_token, fn -> "cf-token" end)
    stub(Tuist.Environment, :kura_cloudflare_zone_id, fn -> "zone-id" end)
    stub(Tuist.Environment, :kura_ssh_public_key, fn -> "ssh-ed25519 test-key" end)
  end

  defp account, do: %{id: "account-123", name: "TUIST"}

  defp eu_region do
    %Regions{
      id: "eu",
      provisioner_config: %{
        target_id: "fsn1",
        location: "fsn1",
        image: "ubuntu-24.04",
        public_host_template: "{account_handle}-{region}.kura.tuist.dev"
      }
    }
  end

  defp response(status, body), do: %Req.Response{status: status, body: body}

  defp chart_fixture(tmp_dir, hook_script) do
    root = Path.join(tmp_dir, "chart")
    hooks = Path.join(root, "hooks")
    File.mkdir_p!(hooks)
    File.write!(Path.join(hooks, "tuist.lua"), hook_script)
    root
  end
end
