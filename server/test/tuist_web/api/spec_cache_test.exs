defmodule TuistWeb.API.SpecCacheTest do
  use ExUnit.Case, async: true

  alias OpenApiSpex.Plug.Cache
  alias OpenApiSpex.Plug.PutApiSpec
  alias TuistWeb.API.ProjectsController
  alias TuistWeb.API.SpecCache

  setup do
    on_exit(fn -> SpecCache.erase(__MODULE__) end)
    %{conn: %Plug.Conn{private: %{open_api_spex: %{spec_module: __MODULE__}}}}
  end

  # Every put of a spec with an operation lookup copies it into the fixed-size
  # literal area, so caching each controller action as it is first resolved
  # exhausted the area and crashed the VM shortly after a deploy.
  test "is the cache the server resolves API specs through" do
    assert Cache.adapter() == SpecCache
  end

  test "resolves routed controller actions from the first put", %{conn: conn} do
    {_spec, lookup} =
      PutApiSpec.get_spec_and_operation_lookup(%{conn | private: %{open_api_spex: %{spec_module: TuistWeb.API.Spec}}})

    SpecCache.put(__MODULE__, {:spec, Map.filter(lookup, fn {key, _} -> is_binary(key) end)})

    {:spec, stored_lookup} = SpecCache.get(__MODULE__)
    assert stored_lookup[{ProjectsController, :index}] == lookup["listProjects"]

    PutApiSpec.get_and_cache_controller_action(conn, "listProjects", {ProjectsController, :index})
    SpecCache.put(__MODULE__, {:other_spec, %{}})

    assert SpecCache.get(__MODULE__) == {:spec, stored_lookup}
  end
end
