defmodule SymptomsWeb.BearerAuth do
  @moduledoc """
  Authenticates the Tuist server's projected ServiceAccount token through
  Kubernetes TokenReview. Only the configured namespace and ServiceAccount,
  with the `tuist-symptoms-api` audience, may read the symptom API.
  Tokens are never cached: Kubernetes checks expiry and bound-pod revocation.
  """
  @behaviour Plug

  import Plug.Conn

  @audience "tuist-symptoms-api"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    config = Keyword.merge(Application.get_env(:symptoms, :api_auth, []), opts)

    with {:ok, principal} <- principal(config),
         {:ok, token} <- bearer(conn),
         :ok <- review(token, principal, config) do
      conn
    else
      {:error, :unauthenticated} ->
        conn |> put_resp_header("www-authenticate", "Bearer") |> halt_with(401, "unauthenticated")

      {:error, reason} ->
        halt_with(conn, 503, to_string(reason))
    end
  end

  defp principal(config) do
    namespace = config[:server_namespace]
    name = config[:server_service_account]

    if Enum.all?(
         [namespace, name, config[:base_url], config[:token_path], config[:ca_file]],
         &(is_binary(&1) and &1 != "")
       ) do
      {:ok, "system:serviceaccount:#{namespace}:#{name}"}
    else
      {:error, :not_configured}
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      [<<scheme::binary-size(7), token::binary>>] when token != "" ->
        if String.downcase(scheme) == "bearer ", do: {:ok, token}, else: {:error, :unauthenticated}

      _ ->
        {:error, :unauthenticated}
    end
  end

  defp review(token, principal, config) do
    # Read the reviewer's own API token on every request: kubelet rotates it.
    with {:ok, reviewer} <- File.read(config[:token_path]),
         reviewer = String.trim(reviewer),
         true <- reviewer != "" do
      body = %{
        apiVersion: "authentication.k8s.io/v1",
        kind: "TokenReview",
        spec: %{token: token, audiences: [@audience]}
      }

      case Req.post(String.trim_trailing(config[:base_url], "/") <> "/apis/authentication.k8s.io/v1/tokenreviews",
             auth: {:bearer, reviewer},
             json: body,
             connect_options: [timeout: 5_000, transport_opts: [cacertfile: config[:ca_file]]],
             receive_timeout: 5_000,
             redirect: false,
             retry: false
           ) do
        {:ok, %Req.Response{status: 201, body: %{"status" => status}}} -> authorized_status(status, principal)
        {:ok, %Req.Response{status: 200, body: %{"status" => status}}} -> authorized_status(status, principal)
        _ -> {:error, :unavailable}
      end
    else
      _ -> {:error, :unavailable}
    end
  end

  defp authorized_status(
         %{"authenticated" => true, "user" => %{"username" => principal}, "audiences" => audiences},
         principal
       )
       when is_list(audiences) do
    if @audience in audiences, do: :ok, else: {:error, :unauthenticated}
  end

  defp authorized_status(_status, _principal), do: {:error, :unauthenticated}

  defp halt_with(conn, status, code) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: code}))
    |> halt()
  end
end
