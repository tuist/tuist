defmodule AtlasWeb.NativeThemesControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.NativeThemes

  test "publishes an accessible appearance catalog without authentication", %{conn: conn} do
    response = get(conn, "/api/native/themes")
    catalog = json_response(response, 200)

    assert catalog["schema_version"] == 1
    assert catalog["default_theme_id"] == "pulse"
    assert Enum.map(catalog["themes"], & &1["id"]) == ~w(pulse berlin habibi)
    assert {:ok, ^catalog} = NativeThemes.validate(catalog)
    assert get_resp_header(response, "cache-control") == ["public, max-age=300"]
  end
end
