defmodule NooraStorybook.TzdataClient do
  @moduledoc false

  @behaviour Tzdata.HTTPClient

  @impl true
  def get(url, headers, options) do
    with {:ok, status, response_headers, body} <-
           :hackney.request(:get, url, headers, "", options) do
      {:ok, {status, response_headers, body}}
    end
  end

  @impl true
  def head(url, headers, options) do
    with {:ok, status, response_headers} <-
           :hackney.request(:head, url, headers, "", options) do
      {:ok, {status, response_headers}}
    end
  end
end
