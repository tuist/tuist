defmodule Tuist.NamespaceTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Namespace
  alias Tuist.Namespace.Instance
  alias Tuist.Namespace.JWTToken
  alias Tuist.SSHClient

  describe "create_instance_with_ssh_connection/1" do
    test "successfully creates instance with SSH connection" do
      # Given
      tenant_id = "test-tenant-123"
      bearer_token = "test-bearer-token"
      instance_id = "instance-456"

      expect(JWTToken, :generate_id_token, fn ->
        {:ok, "test-jwt-token"}
      end)

      expect(Req, :post, 4, fn opts ->
        cond do
          String.contains?(opts[:url], "IssueTenantToken") ->
            {:ok, %{status: 200, body: %{"bearerToken" => bearer_token}}}

          String.contains?(opts[:url], "CreateInstance") ->
            {:ok, %{status: 201, body: %{"metadata" => %{"instanceId" => instance_id}}}}

          String.contains?(opts[:url], "DescribeInstance") ->
            {:ok, %{status: 200, body: %{"metadata" => %{"status" => "RUNNING"}}}}

          String.contains?(opts[:url], "GetSSHConfig") ->
            {:ok, %{status: 200, body: %{"endpoint" => "test.com", "username" => "user"}}}
        end
      end)

      stub(Tuist.Environment, :namespace_ssh_public_key, fn ->
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG..."
      end)

      stub(Tuist.Environment, :namespace_ssh_private_key, fn ->
        Base.encode64("test-private-key")
      end)

      expect(SSHClient, :connect, fn _host, _port, _opts ->
        {:ok, :test_ssh_connection_ref}
      end)

      # When
      result = Namespace.create_instance_with_ssh_connection(tenant_id)

      # Then
      assert {:ok,
              %{
                ssh_connection: :test_ssh_connection_ref,
                tenant_token: bearer_token,
                instance: %Instance{id: instance_id}
              }} == result
    end

    test "returns error when tenant token issuance fails" do
      tenant_id = "test-tenant-123"

      expect(JWTToken, :generate_id_token, fn ->
        {:ok, "test-jwt-token"}
      end)

      expect(Req, :post, fn opts ->
        if String.contains?(opts[:url], "IssueTenantToken") do
          {:ok, %{status: 401}}
        end
      end)

      assert {:error, "Unauthorized: Invalid or expired namespace token"} ==
               Namespace.create_instance_with_ssh_connection(tenant_id)
    end
  end

  describe "create_tenant/1" do
    test "successfully creates tenant with all parameters" do
      expected_response = %{"tenant_id" => "tenant-123"}

      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://iam.namespaceapis.com/namespace.cloud.iam.v1beta.TenantService/CreateTenant"

        assert opts[:json] == %{
                 "visible_name" => "Test Tenant",
                 "external_account_id" => "ext-123"
               }

        {:ok, %{status: 201, body: expected_response}}
      end)

      expect(JWTToken, :generate_id_token, fn ->
        {:ok, "test-jwt-token"}
      end)

      assert {:ok, expected_response} == Namespace.create_tenant("Test Tenant", "ext-123")
    end

    test "handles HTTP error responses" do
      expect(Req, :post, fn _opts ->
        {:ok, %{status: 401}}
      end)

      expect(JWTToken, :generate_id_token, fn ->
        {:ok, "test-jwt-token"}
      end)

      assert {:error, "Unauthorized: Invalid or expired namespace token"} =
               Namespace.create_tenant("Test Tenant", "ext-123")
    end
  end

  describe "issue_tenant_token/1" do
    test "successfully issues tenant token" do
      expected_token = "bearer-token-123"

      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://iam.namespaceapis.com/namespace.cloud.iam.v1beta.TenantService/IssueTenantToken"

        assert opts[:json] == %{
                 "tenant_id" => "tenant-123",
                 "actor_id" => "tuist-qa"
               }

        {:ok, %{status: 200, body: %{"bearerToken" => expected_token}}}
      end)

      expect(JWTToken, :generate_id_token, fn ->
        {:ok, "test-jwt-token"}
      end)

      assert {:ok, ^expected_token} = Namespace.issue_tenant_token("tenant-123", "tuist-qa")
    end
  end

  describe "create_instance/1" do
    test "successfully creates instance with default options" do
      instance_id = "instance-789"

      expected_response = %{
        "metadata" => %{
          "instanceId" => instance_id
        }
      }

      expect(Tuist.Environment, :namespace_ssh_public_key, fn ->
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG..."
      end)

      expect(DateTime, :utc_now, fn ->
        ~U[2024-01-01 12:00:00Z]
      end)

      expect(DateTime, :add, fn datetime, minutes, :minute ->
        assert datetime == ~U[2024-01-01 12:00:00Z]
        assert minutes == 20
        ~U[2024-01-01 12:20:00Z]
      end)

      expect(DateTime, :to_iso8601, fn datetime ->
        assert datetime == ~U[2024-01-01 12:20:00Z]
        "2024-01-01T12:20:00Z"
      end)

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "https://eu.compute.namespaceapis.com/namespace.cloud.compute.v1beta.ComputeService/CreateInstance"

        expected_body = %{
          "cluster_id" => "default",
          "shape" => %{
            "os" => "macos",
            "memory_megabytes" => 14_336,
            "virtual_cpu" => 6,
            "machine_arch" => "arm64"
          },
          "deadline" => "2024-01-01T12:20:00Z",
          "experimental" => %{
            "authorized_ssh_keys" => ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG..."]
          }
        }

        assert opts[:json] == expected_body

        {:ok, %{status: 201, body: expected_response}}
      end)

      assert {:ok, %Instance{id: instance_id}} == Namespace.create_instance("test-tenant-token")
    end

    test "successfully creates instance with tenant token" do
      tenant_token = "custom-tenant-token"

      expect(Tuist.Environment, :namespace_ssh_public_key, fn ->
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG..."
      end)

      expect(DateTime, :utc_now, fn ->
        ~U[2024-01-01 12:00:00Z]
      end)

      expect(DateTime, :add, 1, fn datetime, minutes, :minute ->
        assert datetime == ~U[2024-01-01 12:00:00Z]
        assert minutes == 20
        ~U[2024-01-01 12:20:00Z]
      end)

      expect(DateTime, :to_iso8601, fn datetime ->
        assert datetime == ~U[2024-01-01 12:20:00Z]
        "2024-01-01T12:20:00Z"
      end)

      expect(Req, :post, fn opts ->
        headers = opts[:headers]
        auth_header = Enum.find(headers, fn {key, _value} -> key == "Authorization" end)
        assert auth_header == {"Authorization", "Bearer #{tenant_token}"}

        {:ok, %{status: 201, body: %{"metadata" => %{"instanceId" => "instance-with-token"}}}}
      end)

      assert {:ok, %Instance{id: "instance-with-token"}} == Namespace.create_instance(tenant_token)
    end
  end

  describe "wait_for_instance_to_be_running/2" do
    test "returns :ok when instance is running" do
      instance_id = "instance-running"

      expect(Req, :post, fn opts ->
        assert opts[:json] == %{"instance_id" => instance_id, "cluster_id" => "default"}
        {:ok, %{status: 200, body: %{"metadata" => %{"status" => "RUNNING"}}}}
      end)

      assert :ok = Namespace.wait_for_instance_to_be_running(instance_id, "test-tenant-token")
    end
  end

  describe "describe_instance/1" do
    test "successfully describes instance" do
      instance_id = "instance-describe"

      expected_response = %{
        "metadata" => %{
          "instanceId" => instance_id,
          "status" => "RUNNING"
        }
      }

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "https://eu.compute.namespaceapis.com/namespace.cloud.compute.v1beta.ComputeService/DescribeInstance"

        assert opts[:json] == %{
                 "instance_id" => instance_id,
                 "cluster_id" => "default"
               }

        {:ok, %{status: 200, body: expected_response}}
      end)

      assert {:ok, expected_response} == Namespace.describe_instance(instance_id, "test-tenant-token")
    end
  end

  describe "destroy_instance/2" do
    test "successfully deletes instance" do
      instance_id = "instance-delete"

      expect(Req, :post, fn opts ->
        assert opts[:url] ==
                 "https://eu.compute.namespaceapis.com/namespace.cloud.compute.v1beta.ComputeService/DestroyInstance"

        assert opts[:json] == %{
                 "instance_id" => instance_id
               }

        {:ok, %{status: 200, body: %{}}}
      end)

      assert :ok = Namespace.destroy_instance(instance_id, "test-tenant-token")
    end
  end

  describe "ssh_connection/2" do
    test "successfully gets SSH config for connection" do
      instance_id = "instance-ssh"
      endpoint = "instance-ssh.namespace.com"
      username = "test-user"
      tenant_token = "ssh-tenant-token"

      expect(Req, :post, fn opts ->
        assert opts[:json] == %{"instance_id" => instance_id}
        headers = opts[:headers]
        auth_header = Enum.find(headers, fn {key, _value} -> key == "Authorization" end)
        assert auth_header == {"Authorization", "Bearer #{tenant_token}"}

        {:ok, %{status: 200, body: %{"endpoint" => endpoint, "username" => username}}}
      end)

      private_key_b64 = Base.encode64("test-private-key-content")
      public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG..."

      expect(Tuist.Environment, :namespace_ssh_private_key, fn ->
        private_key_b64
      end)

      expect(Tuist.Environment, :namespace_ssh_public_key, fn ->
        public_key
      end)

      expect(SSHClient, :connect, fn host, _port, opts ->
        assert host == String.to_charlist(endpoint)
        assert opts[:user] == String.to_charlist(username)

        {:ok, :test_ssh_connection_ref}
      end)

      # When
      result = Namespace.ssh_connection(instance_id, tenant_token)

      # Then
      assert {:ok, :test_ssh_connection_ref} = result
    end
  end

  describe "get_tenant_usage/3" do
    test "successfully fetches usage with correct date mapping and auth" do
      account = %Account{namespace_tenant_id: "tenant-usage-123"}
      tenant_token = "usage-bearer-token"

      expect(JWTToken, :generate_id_token, fn ->
        {:ok, "test-jwt-token"}
      end)

      expect(Req, :post, 2, fn opts ->
        cond do
          String.contains?(opts[:url], "IssueTenantToken") ->
            {:ok, %{status: 200, body: %{"bearerToken" => tenant_token}}}

          String.contains?(opts[:url], "GetUsage") ->
            assert opts[:json] == %{
                     "period_start" => %{"year" => 2024, "month" => 11, "day" => 20},
                     "period_end" => %{"year" => 2024, "month" => 11, "day" => 21}
                   }

            auth_header = Enum.find(opts[:headers], fn {k, _} -> k == "Authorization" end)
            assert auth_header == {"Authorization", "Bearer #{tenant_token}"}

            {:ok, %{status: 200, body: %{"total" => %{"instanceMinutes" => %{"unit" => 42}}}}}
        end
      end)

      assert {:ok, %{"total" => %{"instanceMinutes" => %{"unit" => 42}}}} =
               Namespace.get_tenant_usage(account, ~D[2024-11-20], ~D[2024-11-21])
    end
  end
end
