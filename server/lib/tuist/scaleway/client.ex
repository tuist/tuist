defmodule Tuist.Scaleway.Client do
  @moduledoc """
  HTTP client for the Scaleway Apple Silicon API.

  Docs: https://www.scaleway.com/en/developers/api/apple-silicon/
  """

  alias Tuist.Scaleway

  @base_url "https://api.scaleway.com/apple-silicon/v1alpha1"

  def create_server(%Scaleway{} = config, attrs) do
    body = %{
      "name" => Map.fetch!(attrs, :name),
      "type" => Map.fetch!(attrs, :server_type),
      "os_id" => Map.fetch!(attrs, :os_id),
      "project_id" => config.project_id
    }

    request(&Req.post/1, config,
      url: "#{@base_url}/zones/#{Map.fetch!(attrs, :zone)}/servers",
      json: body
    )
  end

  def get_server(%Scaleway{} = config, zone, server_id) do
    request(&Req.get/1, config, url: "#{@base_url}/zones/#{zone}/servers/#{server_id}")
  end

  def delete_server(%Scaleway{} = config, zone, server_id) do
    case request(&Req.delete/1, config, url: "#{@base_url}/zones/#{zone}/servers/#{server_id}") do
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def list_os(%Scaleway{} = config, zone) do
    request(&Req.get/1, config, url: "#{@base_url}/zones/#{zone}/os")
  end

  def find_os_id(%Scaleway{} = config, zone, os_name) do
    with {:ok, %{"os" => images}} <- list_os(config, zone) do
      case Enum.find(images, fn image -> image["name"] == os_name end) do
        nil -> {:error, {:os_not_found, os_name}}
        image -> {:ok, image["id"]}
      end
    end
  end

  defp request(method, %Scaleway{} = config, attrs) do
    attrs
    |> Keyword.put(:headers, [
      {"X-Auth-Token", config.secret_key},
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ])
    |> Keyword.put(:finch, Tuist.Finch)
    |> Keyword.put(:receive_timeout, 30_000)
    |> Keyword.put(:connect_timeout, 10_000)
    |> method.()
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in [200, 201] do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: 204}}), do: :ok
  defp handle_response({:ok, %{status: 404}}), do: {:error, :not_found}
  defp handle_response({:ok, %{status: 409}}), do: {:error, :conflict}

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, "Scaleway API error: status #{status}, body: #{inspect(body)}"}
  end

  defp handle_response({:error, reason}) do
    {:error, "Scaleway request failed: #{inspect(reason)}"}
  end
end
