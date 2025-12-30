defmodule Tuist.Namespace do
  @moduledoc """
  A module to interact with Namespace.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Namespace.Instance
  alias Tuist.Namespace.JWTToken
  alias Tuist.SSHClient

  @base_compute_url "https://eu.compute.namespaceapis.com/namespace.cloud.compute.v1beta.ComputeService"
  @base_usage_url "https://eu.compute.namespaceapis.com/namespace.cloud.compute.v1beta.UsageService"
  @base_tenant_url "https://iam.namespaceapis.com/namespace.cloud.iam.v1beta.TenantService"

  @doc """
  Creates a new instance with an SSH connection and provisions a new tenant token.
  """
  def create_instance_with_ssh_connection(tenant_id) do
    with {:ok, tenant_token} <-
           issue_tenant_token(tenant_id, "tuist-qa"),
         {:ok, %Instance{id: instance_id} = instance} <-
           create_instance(tenant_token),
         :ok <-
           wait_for_instance_to_be_running(instance_id, tenant_token),
         {:ok, ssh_connection} <- ssh_connection(instance_id, tenant_token) do
      {:ok, %{ssh_connection: ssh_connection, tenant_token: tenant_token, instance: instance}}
    end
  end

  @doc """
  Creates a new tenant in Namespace.

  ## Parameters
    - visible_name: The Tenant's visible name, e.g. "Foobar (production)"
    - external_account_id: A string that identifies an external account associated with this tenant
  """
  def create_tenant(visible_name, external_account_id) do
    iam_request(&Req.post/1,
      url: "#{@base_tenant_url}/CreateTenant",
      json: %{
        "visible_name" => visible_name,
        "external_account_id" => "#{external_account_id}"
      }
    )
  end

  @doc """
  Issues a tenant token for a specific tenant.
  """
  def issue_tenant_token(tenant_id, actor_id) do
    case iam_request(&Req.post/1,
           url: "#{@base_tenant_url}/IssueTenantToken",
           json: %{"tenant_id" => tenant_id, "actor_id" => actor_id}
         ) do
      {:ok, %{"bearerToken" => bearer_token}} ->
        {:ok, bearer_token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new compute instance with SSH key authentication.
  """
  def create_instance(tenant_token) do
    ssh_public_key = Environment.namespace_ssh_public_key()

    request_body =
      %{
        "cluster_id" => "default",
        "shape" => %{
          "os" => "macos",
          "memory_megabytes" => 14_336,
          "virtual_cpu" => 6,
          "machine_arch" => "arm64"
        },
        "deadline" => DateTime.utc_now() |> DateTime.add(20, :minute) |> DateTime.to_iso8601(),
        "experimental" => %{
          "authorized_ssh_keys" => [ssh_public_key]
        }
      }

    case compute_request(&Req.post/1,
           url: "#{@base_compute_url}/CreateInstance",
           json: request_body,
           tenant_token: tenant_token
         ) do
      {:ok, %{"metadata" => %{"instanceId" => instance_id}}} ->
        {:ok, %Instance{id: instance_id}}

      response ->
        response
    end
  end

  @doc """
  Waits until an instance reaches the READY state.
  """
  def wait_for_instance_to_be_running(instance_id, tenant_token) do
    start_time = :os.system_time(:second)
    timeout_seconds = 120

    poll_instance_status(instance_id, start_time, timeout_seconds, tenant_token)
  end

  defp poll_instance_status(instance_id, start_time, timeout_seconds, tenant_token) do
    current_time = :os.system_time(:second)

    if current_time - start_time >= timeout_seconds do
      {:error, :instance_timeout}
    else
      case describe_instance(instance_id, tenant_token) do
        {:ok, %{"metadata" => %{"status" => "RUNNING"}}} ->
          :ok

        {:ok, %{"metadata" => %{"status" => _other_status}}} ->
          :timer.sleep(1000)
          poll_instance_status(instance_id, start_time, timeout_seconds, tenant_token)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets the status of an instance.
  """
  def describe_instance(instance_id, tenant_token) do
    compute_request(&Req.post/1,
      url: "#{@base_compute_url}/DescribeInstance",
      json: %{
        "instance_id" => instance_id,
        "cluster_id" => "default"
      },
      tenant_token: tenant_token
    )
  end

  @doc """
  Destroys an instance.
  """
  def destroy_instance(instance_id, tenant_token) do
    compute_request(&Req.post/1,
      url: "#{@base_compute_url}/DestroyInstance",
      json: %{
        "instance_id" => instance_id
      },
      tenant_token: tenant_token
    )
  end

  @doc """
  Gets the compute usage for a tenant between the given dates (inclusive).
  """
  def get_tenant_usage(%Account{namespace_tenant_id: tenant_id}, start_date, end_date) when is_binary(tenant_id) do
    with {:ok, tenant_token} <- issue_tenant_token(tenant_id, "tuist_qa") do
      body =
        %{
          "period_start" => to_date_map(start_date),
          "period_end" => to_date_map(end_date)
        }

      compute_request(&Req.post/1,
        url: "#{@base_usage_url}/GetUsage",
        json: body,
        tenant_token: tenant_token
      )
    end
  end

  defp to_date_map(%Date{} = date), do: %{"year" => date.year, "month" => date.month, "day" => date.day}

  defp ssh_config(instance_id, tenant_token) do
    case compute_request(&Req.post/1,
           url: "#{@base_compute_url}/GetSSHConfig",
           json: %{
             "instance_id" => instance_id
           },
           tenant_token: tenant_token
         ) do
      {:ok, %{"endpoint" => endpoint, "username" => username}} ->
        {:ok, %{endpoint: endpoint, username: username}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Establishes an SSH connection to the specified instance.
  """
  def ssh_connection(instance_id, tenant_token) do
    case ssh_config(instance_id, tenant_token) do
      {:ok, %{endpoint: endpoint, username: username}} ->
        user_dir = Briefly.create!(type: :directory)

        private_key_path = Path.join(user_dir, "id_ed25519")
        public_key_path = Path.join(user_dir, "id_ed25519.pub")

        File.write!(private_key_path, Base.decode64!(Environment.namespace_ssh_private_key()))
        File.write!(public_key_path, Environment.namespace_ssh_public_key())

        SSHClient.connect(String.to_charlist(endpoint), 22,
          user: String.to_charlist(username),
          user_dir: String.to_charlist(user_dir),
          silently_accept_hosts: true,
          auth_methods: ~c"publickey",
          user_interaction: false
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp iam_request(method, attrs) do
    {:ok, id_token} = JWTToken.generate_id_token()
    authorization_header = "Bearer oidc_#{id_token}"

    attrs_with_headers =
      attrs
      |> Keyword.put(:headers, [
        {"Authorization", authorization_header},
        {"Content-Type", "application/json"},
        {"Accept", "application/json"}
      ])
      |> Keyword.put(:finch, Tuist.Finch)

    attrs_with_headers
    |> method.()
    |> handle_namespace_response(method, attrs)
  end

  defp compute_request(method, attrs) do
    tenant_token = Keyword.get(attrs, :tenant_token)

    attrs_with_headers =
      attrs
      |> Keyword.delete(:tenant_token)
      |> Keyword.put(:headers, [
        {"Authorization", "Bearer #{tenant_token}"},
        {"Content-Type", "application/json"},
        {"Accept", "application/json"}
      ])
      |> Keyword.put(:finch, Tuist.Finch)

    attrs_with_headers
    |> method.()
    |> handle_namespace_response(method, attrs)
  end

  defp handle_namespace_response({:ok, %{status: 200, body: body}}, _method, _attrs) do
    if body == %{} do
      :ok
    else
      {:ok, body}
    end
  end

  defp handle_namespace_response({:ok, %{status: 200}}, _method, _attrs) do
    :ok
  end

  defp handle_namespace_response({:ok, %{status: 201, body: body}}, _method, _attrs) do
    {:ok, body}
  end

  defp handle_namespace_response({:ok, %{status: 204}}, _method, _attrs) do
    :ok
  end

  defp handle_namespace_response({:ok, %{status: 401}}, _method, _attrs) do
    {:error, "Unauthorized: Invalid or expired namespace token"}
  end

  defp handle_namespace_response({:ok, %{status: 403}}, _method, _attrs) do
    {:error, "Forbidden: Insufficient permissions"}
  end

  defp handle_namespace_response({:ok, %{status: 404}}, _method, _attrs) do
    {:error, "Not found"}
  end

  defp handle_namespace_response({:ok, %{status: status, body: body}}, _method, _attrs) do
    {:error, "Unexpected status code: #{status}. Body: #{inspect(body)}"}
  end

  defp handle_namespace_response({:error, reason}, _method, _attrs) do
    {:error, "Request failed: #{inspect(reason)}"}
  end
end
