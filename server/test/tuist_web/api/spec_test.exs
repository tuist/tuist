defmodule TuistWeb.API.SpecTest do
  use ExUnit.Case, async: true

  alias OpenApiSpex.Operation
  alias OpenApiSpex.Parameter
  alias TuistWeb.API.Spec

  # The command line tool's client is generated from this spec, and Swift
  # takes the generated path initializers' labelled arguments in the order
  # the spec lists the parameters. An operation that declares them in a map
  # gets whatever order the runtime gives the map's keys, which can change
  # with the Erlang release and break every call site.
  test "lists every operation's path parameters in the order its path names them" do
    mismatches =
      for {path, item} <- Spec.spec().paths,
          %Operation{} = operation <- [item.get, item.put, item.post, item.delete, item.patch, item.head, item.options],
          listed = for(%Parameter{in: :path, name: name} <- operation.parameters || [], do: to_string(name)),
          named = for([_, name] <- Regex.scan(~r/\{([^}]+)\}/, path), name in listed, do: name),
          listed != named,
          do: {operation.operationId, listed}

    assert mismatches == []
  end
end
