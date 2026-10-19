defmodule Tuist.OAuth.AuthoritativeCacheScopeTest do
  use ExUnit.Case, async: false

  alias Boruta.Ecto.Scopes
  alias Boruta.Oauth.Scope

  test "upstream scope invalidation removes both legacy scope lists" do
    keys = [{Scope, :public}, {Scope, :all}]
    previous = Enum.map(keys, &{&1, Boruta.Cache.get(&1)})

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value), do: Boruta.Cache.delete(key), else: Boruta.Cache.put(key, value)
      end
    end)

    for key <- keys, do: assert(:ok = Boruta.Cache.put(key, [:legacy]))
    assert :ok = Scopes.invalidate(:all)
    for key <- keys, do: assert(Boruta.Cache.get(key) == nil)
  end
end
