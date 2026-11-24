defmodule SymptomsWeb.BearerAuth do
  @moduledoc """
  Bearer-token auth for the symptom API: the token in `config :symptoms,
  :api_token` (env `SYMPTOMS_API_TOKEN`), compared in constant time. Without
  a configured token every request gets 503 `not_configured`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    expected = Application.get_env(:symptoms, :api_token)

    cond do
      not is_binary(expected) or expected == "" -> halt_with(conn, 503, "not_configured")
      authorized?(conn, expected) -> conn
      true -> conn |> put_resp_header("www-authenticate", "Bearer") |> halt_with(401, "unauthenticated")
    end
  end

  defp authorized?(conn, expected) do
    case get_req_header(conn, "authorization") do
      [<<scheme::binary-size(7), token::binary>>] when token != "" ->
        String.downcase(scheme) == "bearer " and Plug.Crypto.secure_compare(token, expected)

      _ ->
        false
    end
  end

  defp halt_with(conn, status, code) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: code}))
    |> halt()
  end
end
