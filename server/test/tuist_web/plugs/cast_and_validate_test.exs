defmodule TuistWeb.Plugs.CastAndValidateTest do
  use ExUnit.Case, async: true

  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Operation
  alias OpenApiSpex.PathItem
  alias OpenApiSpex.Plug.PersistentTermCache
  alias OpenApiSpex.Plug.PutApiSpec
  alias TuistWeb.Plugs.CastAndValidate

  defmodule Controller do
    use OpenApiSpex.ControllerSpecs

    operation(:index,
      operation_id: "entries",
      parameters: [Operation.parameter(:limit, :query, :integer, "Limit", required: true)],
      responses: %{}
    )

    operation(:preview,
      operation_id: "preview",
      parameters: [Operation.parameter(:enabled, :query, :boolean, "Enabled", required: true)],
      responses: %{}
    )

    operation(:skip, false)
  end

  defmodule Spec do
    @moduledoc false
    def spec do
      OpenApiSpex.resolve_schema_modules(%OpenApi{
        info: %Info{title: "Validation", version: "1"},
        paths: %{
          "/entries" => %PathItem{get: Controller.open_api_operation(:index)},
          "/preview" => %PathItem{get: Controller.open_api_operation(:preview)}
        }
      })
    end
  end

  setup do
    on_exit(fn -> PersistentTermCache.erase(Spec) end)
    :ok
  end

  test "casts different actions without rewriting the shared specification cache" do
    conn = conn(:index, "limit=37")
    cached_spec = PutApiSpec.get_spec_and_operation_lookup(conn)
    opts = CastAndValidate.init([])

    result = CastAndValidate.call(conn, opts)
    assert result.params == %{limit: 37}
    refute result.halted

    result = CastAndValidate.call(conn(:preview, "enabled=false"), opts)
    assert result.params == %{enabled: false}
    refute result.halted

    assert PutApiSpec.get_spec_and_operation_lookup(conn) == cached_spec
  end

  test "rejects invalid parameters" do
    result = CastAndValidate.call(conn(:index, "limit=invalid"), CastAndValidate.init(json_render_error_v2: true))

    assert result.halted
    assert result.status == 422
  end

  test "skips actions without an operation" do
    conn = conn(:skip, "limit=invalid")

    assert CastAndValidate.call(conn, CastAndValidate.init([])) == conn
  end

  test "honors an explicit operation ID and replace_params option" do
    opts = CastAndValidate.init(operation_id: "preview", replace_params: false)

    for action <- [:index, :skip] do
      result = CastAndValidate.call(conn(action, "enabled=false"), opts)

      refute result.halted
      assert result.params == %{"enabled" => "false"}
      assert OpenApiSpex.params(result) == %{enabled: false}
    end
  end

  defp conn(action, query) do
    :get
    |> Plug.Test.conn("/?#{query}")
    |> Plug.Conn.fetch_query_params()
    |> Plug.Conn.put_private(:phoenix_controller, Controller)
    |> Plug.Conn.put_private(:phoenix_action, action)
    |> PutApiSpec.call(Spec)
  end
end
