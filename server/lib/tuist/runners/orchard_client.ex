defmodule Tuist.Runners.OrchardClient do
  @moduledoc false
  alias Tuist.Runners.OrchardConfig

  def create_vm(%OrchardConfig{} = config, attrs) do
    body =
      maybe_put(
        %{
          "image" => Map.fetch!(attrs, :image),
          "cpu" => Map.get(attrs, :cpu, 4),
          "memory" => Map.get(attrs, :memory, 8192)
        },
        "startup_script",
        Map.get(attrs, :startup_script)
      )

    case orchard_request(&Req.post/1, config,
           url: "#{config.controller_url}/v1/vms",
           json: Map.put(body, "name", Map.fetch!(attrs, :name))
         ) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_vm(%OrchardConfig{} = config, vm_name) do
    orchard_request(&Req.get/1, config, url: "#{config.controller_url}/v1/vms/#{URI.encode(vm_name)}")
  end

  def delete_vm(%OrchardConfig{} = config, vm_name) do
    case orchard_request(&Req.delete/1, config, url: "#{config.controller_url}/v1/vms/#{URI.encode(vm_name)}") do
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def list_vms(%OrchardConfig{} = config, opts \\ []) do
    query_params = if filter = Keyword.get(opts, :filter), do: [filter: filter], else: []

    orchard_request(&Req.get/1, config,
      url: "#{config.controller_url}/v1/vms",
      params: query_params
    )
  end

  defp orchard_request(method, %OrchardConfig{} = config, attrs) do
    attrs_with_auth =
      attrs
      |> Keyword.put(:headers, [
        {"Accept", "application/json"},
        {"Content-Type", "application/json"}
      ])
      |> Keyword.put(:auth, {:basic, "#{config.service_account_name}:#{config.service_account_token}"})
      |> Keyword.put(:finch, Tuist.Finch)
      |> Keyword.put(:receive_timeout, 30_000)
      |> Keyword.put(:connect_timeout, 10_000)

    attrs_with_auth
    |> method.()
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in [200, 201] do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: 204}}) do
    :ok
  end

  defp handle_response({:ok, %{status: 404}}) do
    {:error, :not_found}
  end

  defp handle_response({:ok, %{status: 409}}) do
    {:error, :conflict}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, "Orchard API error: status #{status}, body: #{inspect(body)}"}
  end

  defp handle_response({:error, reason}) do
    {:error, "Orchard request failed: #{inspect(reason)}"}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
