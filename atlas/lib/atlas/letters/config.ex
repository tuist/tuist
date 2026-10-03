defmodule Atlas.Letters.Config do
  @moduledoc false

  @production_api_base_url "https://api.pingen.com"
  @production_identity_base_url "https://identity.pingen.com"
  @staging_api_base_url "https://api-staging.v2.pingen.com"
  @staging_identity_base_url "https://identity-staging.pingen.com"

  def configured? do
    config()
    |> Keyword.take([:client_id, :client_secret, :organisation_id])
    |> Enum.all?(fn {_key, value} -> present?(value) end)
  end

  def client_id, do: config()[:client_id]
  def client_secret, do: config()[:client_secret]
  def organisation_id, do: config()[:organisation_id]
  def webhook_signing_key, do: config()[:webhook_signing_key]
  def delivery_product, do: config()[:delivery_product] || "fast"
  def print_mode, do: config()[:print_mode] || "simplex"
  def print_spectrum, do: config()[:print_spectrum] || "color"
  def receive_timeout, do: config()[:receive_timeout] || 15_000
  def staging?, do: config()[:staging] == true

  def api_base_url do
    config()[:api_base_url] || if(staging?(), do: @staging_api_base_url, else: @production_api_base_url)
  end

  def identity_base_url do
    config()[:identity_base_url] ||
      if(staging?(), do: @staging_identity_base_url, else: @production_identity_base_url)
  end

  defp config, do: Application.get_env(:atlas, :pingen, [])
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
