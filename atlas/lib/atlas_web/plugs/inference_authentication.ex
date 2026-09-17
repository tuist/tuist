defmodule AtlasWeb.Plugs.InferenceAuthentication do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Atlas.Audit
  alias Atlas.Inference

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token_value} <- bearer_token(conn),
         {:ok, token} <- Inference.authenticate_token(token_value) do
      Audit.put_context(%{interface: "inference"})

      conn
      |> assign(:inference_token, token)
      |> assign(:inference_model_binding, token.model_binding)
    else
      _other -> unauthorized(conn)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _other -> :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="atlas-inference"))
    |> put_status(:unauthorized)
    |> json(%{
      error: %{
        message: "Missing or invalid inference token.",
        type: "invalid_request_error",
        code: "invalid_api_key"
      }
    })
    |> halt()
  end
end
