defmodule Tuist.Namespace do
  @moduledoc """
  A module to interact with Namespace.
  """

  alias Tuist.Environment
  alias Tuist.Namespace.Instance

  @base_compute_url "https://eu.compute.namespaceapis.com/namespace.cloud.compute.v1beta.ComputeService"
  @base_tenant_url "https://iam.namespaceapis.com/namespace.cloud.iam.v1beta.TenantService"

  @doc """
  Creates a new tenant in Namespace.

  ## Parameters
    - visible_name: The Tenant's visible name, e.g. "Foobar (production)"
    - external_account_id: A string that identifies an external account associated with this tenant
    - policies: A list of policies that apply to this Tenant (optional)
    - labels: A list of labels that should be attached to the Tenant (optional)
  """
  def create_tenant(params) do
    visible_name = Keyword.get(params, :visible_name)
    external_account_id = Keyword.fetch!(params, :external_account_id)
    policies = Keyword.get(params, :policies, [])
    labels = Keyword.get(params, :labels, [])

    request_body = %{
      "visible_name" => visible_name,
      "external_account_id" => "#{external_account_id}",
      "policies" => policies,
      "labels" => labels
    }

    case iam_request(&Req.post/1,
           url: "#{@base_tenant_url}/CreateTenant",
           json: request_body
         )
         |> dbg do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Issues a tenant token for a specific tenant.

  ## Parameters
    - tenant_id: The ID of the tenant to issue credentials for
    - actor_id: An integration-specified identifier representing the user requesting credentials
    - duration_secs: How long the credentials should be valid for (optional, defaults to 15 minutes)
    - policies: A list of policies that apply to this tenant token (optional)
  """
  def issue_tenant_token(params) do
    tenant_id = Keyword.fetch!(params, :tenant_id)
    actor_id = Keyword.fetch!(params, :actor_id)
    # Default 15 minutes
    duration_secs = Keyword.get(params, :duration_secs, 900)
    policies = Keyword.get(params, :policies, [])

    request_body = %{
      "tenant_id" => tenant_id,
      "actor_id" => actor_id,
      "duration_secs" => duration_secs,
      "policies" => policies
    }

    case iam_request(&Req.post/1,
           url: "#{@base_tenant_url}/IssueTenantToken",
           json: request_body
         ) do
      {:ok, %{"bearerToken" => bearer_token}} ->
        {:ok, bearer_token}

      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new compute instance with SSH key authentication.

  ## Options
    - tenant_token: Optional tenant token to use for authentication instead of the default token
  """
  def create_instance(opts \\ []) do
    ssh_public_key = Tuist.Environment.namespace_ssh_public_key()

    # deadline = DateTime.utc_now() |> DateTime.add(10, :hour) |> DateTime.to_iso8601()
    deadline = DateTime.utc_now() |> DateTime.add(10, :minute) |> DateTime.to_iso8601()

    request_body =
      %{
        "cluster_id" => "default",
        "shape" => %{
          "os" => "macos",
          "memory_megabytes" => 14336,
          "virtual_cpu" => 6,
          "machine_arch" => "arm64"
        },
        "deadline" => deadline,
        "experimental" => %{
          "authorized_ssh_keys" => [ssh_public_key]
        }
      }

    case compute_request(&Req.post/1,
           url: "#{@base_compute_url}/CreateInstance",
           json: request_body,
           tenant_token: opts[:tenant_token]
         ) do
      {:ok, create_instance_response} ->
        %{"metadata" => %{"instanceId" => instance_id}} = create_instance_response
        {:ok, %Instance{id: instance_id}}

      response ->
        response
    end
  end

  @doc """
  Waits until an instance reaches the READY state.

  ## Options
    - tenant_token: Optional tenant token to use for authentication
  """
  def wait_for_instance_to_be_running(instance_id, opts \\ []) do
    start_time = :os.system_time(:second)
    timeout_seconds = 20

    poll_instance_status(instance_id, start_time, timeout_seconds, opts[:tenant_token])
  end

  defp poll_instance_status(instance_id, start_time, timeout_seconds, tenant_token) do
    current_time = :os.system_time(:second)

    if current_time - start_time >= timeout_seconds do
      {:error, :instance_timeout}
    else
      request_body = %{
        "instance_id" => instance_id
      }

      case compute_request(&Req.post/1,
             url: "#{@base_compute_url}/DescribeInstance",
             json: request_body,
             tenant_token: tenant_token
           )
           |> dbg do
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
  def describe_instance(instance_id) do
    request_body = %{
      "instance_id" => instance_id,
      "cluster_id" => "default"
    }

    compute_request(&Req.post/1,
      url: "#{@base_compute_url}/DescribeInstance",
      json: request_body
    )
  end

  @doc """
  Deletes an instance.
  """
  def delete_instance(instance_id) do
    compute_request(&Req.delete/1,
      url: "#{@base_compute_url}/v1beta/compute/instances/#{instance_id}"
    )
  end

  @doc """
  Lists all instances.
  """
  def list_instances(opts \\ []) do
    page_size = Keyword.get(opts, :page_size, 100)

    compute_request(&Req.get/1,
      url: "#{@base_compute_url}/v1beta/compute/instances",
      params: %{page_size: page_size}
    )
  end

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

  ## Options
    - tenant_token: Optional tenant token to use for authentication
  """
  def ssh_connection(instance_id, opts \\ []) do
    case ssh_config(instance_id, opts[:tenant_token]) do
      {:ok, %{endpoint: endpoint, username: username}} ->
        user_dir = Briefly.create!(type: :directory)

        File.write!(
          user_dir <> "/id_ed25519",
          Tuist.Environment.namespace_ssh_private_key() |> Base.decode64!()
        )

        File.write!(user_dir <> "/id_ed25519.pub", Tuist.Environment.namespace_ssh_public_key())

        :ssh.connect(String.to_charlist(endpoint), 22,
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
    # For IAM/tenant endpoints, use OIDC token
    {:ok, id_token} = Tuist.Namespace.JWTToken.generate_id_token()
    authorization_header = "Bearer oidc_#{id_token}"

    attrs_with_headers =
      attrs
      |> Keyword.put(:headers, [
        {"Authorization", authorization_header},
        {"Content-Type", "application/json"},
        {"Accept", "application/json"}
      ])
      |> dbg
      |> Keyword.put(:finch, Tuist.Finch)

    attrs_with_headers
    |> method.()
    |> handle_namespace_response(method, attrs)
  end

  defp compute_request(method, attrs) do
    # For compute endpoints, use tenant token if provided, otherwise use environment token
    authorization_header =
      case Keyword.get(attrs, :tenant_token) do
        nil ->
          # Use environment token for compute endpoints
          "Bearer #{Environment.namespace_token()}"

        tenant_token ->
          # Use the provided tenant token
          "Bearer #{tenant_token}"
      end

    # Remove tenant_token from attrs since it's not needed for the HTTP request
    cleaned_attrs = Keyword.delete(attrs, :tenant_token)

    attrs_with_headers =
      cleaned_attrs
      |> Keyword.put(:headers, [
        {"Authorization", authorization_header},
        {"Content-Type", "application/json"},
        {"Accept", "application/json"}
      ])
      |> dbg
      |> Keyword.put(:finch, Tuist.Finch)

    attrs_with_headers
    |> method.()
    |> handle_namespace_response(method, attrs)
  end

  defp handle_namespace_response({:ok, %{status: 200, body: body}}, _method, _attrs) do
    {:ok, body}
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
