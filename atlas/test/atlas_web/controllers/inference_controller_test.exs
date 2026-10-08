defmodule AtlasWeb.InferenceControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Inference
  alias Atlas.Inference.ModelBinding
  alias Atlas.Inference.Token
  alias Atlas.Inference.Usage
  alias Atlas.Repo
  alias AtlasWeb.InferenceController

  test "relays and records a billing rejection after a provider requires streaming", %{conn: conn} do
    unique = System.unique_integer([:positive])

    binding =
      Repo.insert!(%ModelBinding{name: "Balanced-#{unique}", upstream_provider: "test", upstream_model: "model"})

    token = Repo.insert!(%Token{name: "test", token_hash: "test-#{unique}", model_binding_id: binding.id})
    body = %{"error" => %{"type" => "credit_limit", "message" => "A positive credit balance is required."}}

    request = fn options ->
      if options[:json]["stream"] do
        response = %Req.Response{status: 402, headers: %{"content-type" => ["application/json"]}, body: ""}
        {first, last} = String.split_at(JSON.encode!(body), 30)
        into = Keyword.fetch!(options, :into)
        {:cont, acc} = into.({:data, first}, {%Req.Request{}, response})
        {:cont, {_request, response}} = into.({:data, last}, acc)
        {:ok, response}
      else
        {:ok, %Req.Response{status: 400, body: %{"error" => %{"code" => "streaming_required"}}}}
      end
    end

    Inference.put_process_config(
      providers: %{"test" => %{base_url: "https://provider.example", api_key: "test"}},
      request: request
    )

    on_exit(&Inference.delete_process_config/0)

    conn =
      conn
      |> assign(:inference_model_binding, binding)
      |> assign(:inference_token, token)
      |> InferenceController.chat_completions(%{"model" => binding.name, "messages" => []})

    assert json_response(conn, 402) == body
    usage = Repo.get_by!(Usage, token_id: token.id)
    assert usage.status == 402
  end
end
