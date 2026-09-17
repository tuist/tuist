defmodule Atlas.LLMs.LocalTransport do
  @moduledoc """
  Req-compatible Plug that routes atlas's own inference calls through
  `AtlasWeb.InferenceController` in-process, bypassing the public HTTP
  endpoint at `https://atlas.tuist.dev/inference/v1/*`.

  ReqLLM's OpenAI provider merges caller-supplied `req_http_options` into
  `Req.new/1`, and Req supports the `:plug` option to dispatch a request
  through a Plug instead of the network. `Atlas.LLMs.Runner` uses that
  seam in local mode so agent workflows go straight from the running
  BEAM to `Atlas.Inference.relay_request/3` without a TLS handshake,
  DNS lookup, or ingress hop.

  The plug looks up the profile marked with the requested atlas role
  (`atlas_inference` for chat completions, `atlas_embedding` for
  embeddings), fetches its bound token, and delegates to the same
  controller actions the public API uses. Response shape, streaming
  behavior, and usage accounting stay identical.
  """

  @behaviour Plug

  import Ecto.Query
  import Plug.Conn

  alias Atlas.Inference
  alias Atlas.Inference.ModelBinding
  alias Atlas.Inference.Token
  alias Atlas.Repo
  alias AtlasWeb.InferenceController

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    role = role_for_path(conn.path_info)

    with %ModelBinding{} = binding <- Inference.get_atlas_profile(role),
         %Token{} = token <- fetch_role_token(binding, role) do
      # The profile marked with the atlas role IS the "default profile"
      # for that role. Callers pass an opaque model identifier through
      # ReqLLM (see `Runner.client_opts/1`); we rewrite it to the
      # binding's real name so the downstream `Inference.model_allowed?/3`
      # check succeeds without the caller having to know which profile
      # is currently default.
      params =
        conn
        |> decode_params()
        |> Map.put("model", binding.name)

      conn
      |> assign(:inference_token, token)
      |> assign(:inference_model_binding, binding)
      |> dispatch(role, params)
    else
      _ -> unavailable(conn, role)
    end
  end

  defp role_for_path(path) do
    cond do
      chat_completions?(path) -> :inference
      embeddings?(path) -> :embedding
      true -> :inference
    end
  end

  defp chat_completions?(path) do
    path == ["chat", "completions"] or path == ["v1", "chat", "completions"]
  end

  defp embeddings?(path) do
    path == ["embeddings"] or path == ["v1", "embeddings"]
  end

  defp fetch_role_token(%ModelBinding{id: profile_id}, role) do
    role_str = to_string(role)

    Repo.one(
      from t in Token,
        where:
          t.model_binding_id == ^profile_id and
            t.atlas_role == ^role_str and
            t.enabled == true
    )
  end

  defp decode_params(conn) do
    case conn.body_params do
      params when is_map(params) and map_size(params) > 0 ->
        params

      _ ->
        {:ok, body, _conn} = read_body(conn)

        case body do
          "" -> %{}
          binary when is_binary(binary) -> JSON.decode!(binary)
        end
    end
  end

  defp dispatch(conn, :inference, params) do
    InferenceController.chat_completions(conn, params)
  end

  defp dispatch(conn, :embedding, params) do
    InferenceController.embeddings(conn, params)
  end

  defp unavailable(conn, role) do
    conn
    |> put_resp_content_type("application/json")
    |> put_status(:service_unavailable)
    |> send_resp(
      503,
      JSON.encode!(%{
        error: %{
          message: "No enabled profile assigned to atlas_#{role}, or no bound token available.",
          type: "server_error",
          code: nil
        }
      })
    )
  end
end
