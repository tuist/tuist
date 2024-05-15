defmodule TuistCloudWeb.WarningsHeaderPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test
  alias TuistCloudWeb.WarningsHeaderPlug

  test "put_warning assigns the warning" do
    # Given
    conn = conn(:get, "/")

    # When
    conn =
      WarningsHeaderPlug.put_warning(conn, "warning 1")
      |> WarningsHeaderPlug.put_warning("warning 2")

    # Then
    assert conn.assigns[:warnings] == ["warning 2", "warning 1"]
  end
end
