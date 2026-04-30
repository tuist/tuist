defmodule Tuist.Marketing.NimblePublisher.Cache do
  @moduledoc false

  alias Tuist.ContentCache
  alias Tuist.Marketing.NimblePublisher.Builder

  def start_link(_opts) do
    ContentCache.start_link(name: __MODULE__)
  end

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  def entries(key, opts) do
    ContentCache.get(__MODULE__, key, fn -> Builder.build!(opts) end)
  end

  def reload do
    ContentCache.reload(__MODULE__)
  end
end
