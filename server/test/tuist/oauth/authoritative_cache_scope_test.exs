defmodule Tuist.OAuth.AuthoritativeCacheScopeTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Boruta.Ecto.Scopes
  alias Boruta.Oauth.Scope
  alias Tuist.Repo

  test "upstream scope invalidation ignores legacy lists and lookups remain authoritative" do
    keys = [{Scope, :public}, {Scope, :all}]
    previous = Enum.map(keys, &{&1, Boruta.Cache.get(&1)})

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value), do: Boruta.Cache.delete(key), else: Boruta.Cache.put(key, value)
      end
    end)

    for key <- keys, do: assert(:ok = Boruta.Cache.put(key, [:legacy]))
    scope = Repo.insert!(%Boruta.Ecto.Scope{name: "scope:#{Ecto.UUID.generate()}", public: true})
    assert :ok = Scopes.invalidate(:all)
    for key <- keys, do: assert(Boruta.Cache.get(key) == [:legacy])
    assert Enum.any?(Scopes.public(), &(&1.id == scope.id))
    assert Enum.any?(Scopes.all(), &(&1.id == scope.id))

    Repo.delete!(scope)
    refute Enum.any?(Scopes.public(), &(&1.id == scope.id))
    refute Enum.any?(Scopes.all(), &(&1.id == scope.id))
  end
end
