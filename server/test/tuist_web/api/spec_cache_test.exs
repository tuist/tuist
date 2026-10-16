defmodule TuistWeb.API.SpecCacheTest do
  use ExUnit.Case, async: true

  alias OpenApiSpex.Plug.Cache
  alias TuistWeb.API.SpecCache

  setup do
    on_exit(fn -> SpecCache.erase(__MODULE__) end)
  end

  # Every put of a spec with an operation lookup copies it into the fixed-size
  # literal area, so caching each controller action as it is first resolved
  # exhausted the area and crashed the VM shortly after a deploy.
  test "is the cache the server resolves API specs through" do
    assert Cache.adapter() == SpecCache
  end

  test "keeps the first spec it is given" do
    SpecCache.put(__MODULE__, {:spec, %{"operation" => :operation}})
    SpecCache.put(__MODULE__, {:spec, %{"operation" => :operation, {:controller, :action} => :operation}})

    assert SpecCache.get(__MODULE__) == {:spec, %{"operation" => :operation}}
  end
end
