defmodule TuistWeb.DocsRedirectControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  test "resolves legacy docs paths without a locale in one hop", %{conn: conn} do
    for {legacy_path, current_path} <- [
          {"/docs/documentation/tuist/installation", "/en/docs/guides/install-tuist"},
          {"/docs/guides/develop/build/cache?tab=setup", "/en/docs/guides/features/cache?tab=setup"}
        ] do
      assert conn |> get(legacy_path) |> redirected_to(301) == current_path
    end
  end

  test "redirects current docs paths without a locale to English", %{conn: conn} do
    assert conn |> get("/docs/guides/install-tuist") |> redirected_to(301) == "/en/docs/guides/install-tuist"
  end

  test "keeps retired docs languages so their audited English mappings apply", %{conn: conn} do
    conn = get(conn, "/docs/pt/guides/features/projects/dependencies")
    assert redirected_to(conn, 301) == "/pt/docs/guides/features/projects/dependencies"

    conn = conn |> recycle() |> get("/pt/docs/guides/features/projects/dependencies")
    assert redirected_to(conn, 301) == "/en/docs/guides/features/projects/dependencies"
  end

  test "redirects legacy ProjectDescription references to their external site", %{conn: conn} do
    assert conn |> get("/docs/reference/project-description/structs/project") |> redirected_to(301) ==
             "https://projectdescription.tuist.dev/documentation/projectdescription"
  end
end
