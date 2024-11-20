defmodule TuistWeb.Plugs.API.TransformQueryArrayParamsPlug do
  @moduledoc """
  Some API clients send query parameters without the `[]` suffix: ?platforms=ios&platforms=macos.
  However, Phoenix expects query parameters to be in the form of ?platforms[]=ios&platforms[]=macos.
  This plug transforms query parameters from the former to the latter.
  """

  def init(query_array_keys), do: query_array_keys

  def call(conn, query_array_keys) do
    %{
      conn
      | query_params:
          Plug.Conn.Query.decode(
            query_array_keys
            |> Enum.map(&Atom.to_string/1)
            |> Enum.reduce(conn.query_string, fn key, acc ->
              String.replace(acc, "#{key}=", "#{key}[]=")
            end)
          )
    }
  end
end
