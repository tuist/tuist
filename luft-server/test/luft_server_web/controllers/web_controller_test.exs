defmodule LuftServerWeb.WebControllerTest do
  # Writes the release's static directory, so not async.
  use LuftServerWeb.ConnCase, async: false

  @static Application.app_dir(:luft_server, "priv/static")
  @files %{
    "index.html" => "<!doctype html><title>Luft</title>",
    "assets/main-abc123.js" => "console.log(1)",
    "assets/main-abc123.js.gz" => :zlib.gzip("console.log(1)")
  }

  # A local build may already be in priv/static: restore it afterwards.
  setup do
    backup = Path.join(System.tmp_dir!(), "luft-static-#{System.unique_integer([:positive])}")
    existed? = File.dir?(@static)
    if existed?, do: File.cp_r!(@static, backup)

    for {path, contents} <- @files do
      path = Path.join(@static, path)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
    end

    on_exit(fn ->
      File.rm_rf!(@static)
      if existed?, do: File.cp_r!(backup, @static)
      File.rm_rf!(backup)
    end)
  end

  test "root and client-side routes are JSON 404s even with a built HTML shell", %{conn: conn} do
    for path <- ["/", "/index.html", "/organizations/tuist"] do
      conn = conn |> put_req_header("accept", "text/html") |> get(path)
      assert json_response(conn, 404) == %{"error" => "not_found"}
      refute response(conn, 404) =~ "<title>Luft</title>"
    end
  end

  test "built assets are never served, including compressed copies", %{conn: conn} do
    for path <- ["/assets/main-abc123.js", "/assets/main-abc123.js.gz"],
        encoding <- ["identity", "gzip"] do
      conn = conn |> put_req_header("accept-encoding", encoding) |> get(path)
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert get_resp_header(conn, "content-encoding") == []
      refute get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end
  end

  test "missing assets, auth routes and dotfiles are JSON 404s, never the shell", %{conn: conn} do
    for path <- [
          "/assets/missing.js",
          "/auth/missing",
          "/.env",
          "/@vite/client",
          "/src/main.ts",
          "/node_modules/.vite/deps/example.js"
        ] do
      assert json_response(get(conn, path), 404) == %{"error" => "not_found"}
    end
  end
end
