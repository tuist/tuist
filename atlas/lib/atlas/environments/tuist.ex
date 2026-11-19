defmodule Atlas.Environments.Tuist do
  @moduledoc "Tuist sandbox provider, authenticated with Atlas's own OIDC workload identity."
  @behaviour Atlas.Environments.Provider

  alias Atlas.Environments.Identity

  @impl true
  def start(config, identity), do: request(config, identity, :put, "", %{})

  @impl true
  def execute(config, identity, command) do
    payload = Map.take(command, [:id, :tool, :arguments, :execution_timeout_seconds])
    request(config, identity, :post, "/exec", payload)
  end

  @impl true
  def stop(config, identity), do: request(config, identity, :post, "/pause", %{})

  @impl true
  def delete(config, identity), do: request(config, identity, :delete, "", %{})

  defp request(config, identity, method, suffix, body) do
    with {:ok, token} <- Identity.token(identity, config.account_handle, "tuist-environments"),
         {:ok, %Req.Response{status: status, body: response}} when status in 200..299 and is_map(response) <-
           Req.request(
             method: method,
             url:
               config.url <>
                 "/api/environment-providers/atlas/" <>
                 URI.encode(config.account_handle, &URI.char_unreserved?/1) <> "/" <> identity.environment_id <> suffix,
             auth: {:bearer, token},
             json: Map.put(body, :generation, identity.generation),
             retry: false,
             redirect: false,
             receive_timeout: 660_000,
             connect_options: [timeout: 10_000]
           ) do
      if suffix == "/exec" do
        case response do
          %{"success" => success, "output" => output}
          when is_boolean(success) and is_binary(output) and byte_size(output) <= 65_536 ->
            {:ok, %{success: success, output: output}}

          _ ->
            {:error, :environment_provider_unavailable}
        end
      else
        {:ok, response}
      end
    else
      _ -> {:error, :environment_provider_unavailable}
    end
  end
end
