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

  test "client-side routes get the HTML shell, revalidated on every load", %{conn: conn} do
    conn = get(conn, "/organizations/tuist")

    assert html_response(conn, 200) =~ "<title>Luft</title>"
    assert get_resp_header(conn, "cache-control") == ["no-cache"]
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "script-src 'self' 'wasm-unsafe-eval'"
    assert csp =~ "frame-ancestors 'none'"
  end

  test "hashed assets are immutable and served gzipped when accepted", %{conn: conn} do
    plain = get(conn, "/assets/main-abc123.js")
    assert response(plain, 200) == "console.log(1)"
    assert get_resp_header(plain, "cache-control") == ["public, max-age=31536000, immutable"]

    gzipped = conn |> put_req_header("accept-encoding", "gzip") |> get("/assets/main-abc123.js")
    assert get_resp_header(gzipped, "content-encoding") == ["gzip"]
    assert :zlib.gunzip(response(gzipped, 200)) == "console.log(1)"
  end

  test "missing assets, API routes and dotfiles are JSON 404s, never the shell", %{conn: conn} do
    for path <- ["/assets/missing.js", "/api/missing", "/auth/missing", "/.env"] do
      assert json_response(get(conn, path), 404) == %{"error" => "not_found"}
    end
  end
end
