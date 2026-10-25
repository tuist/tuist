defmodule AtlasWeb.NativeLinksTest do
  use ExUnit.Case, async: true
  use Mimic

  alias AtlasWeb.NativeLinks
  alias AtlasWeb.NativeLinks.Config

  @id "0198f0a1-7c2e-7b3d-9f4a-1b2c3d4e5f60"

  setup :verify_on_exit!

  describe "for_page/1" do
    test "maps only the exact equivalent dashboard pages" do
      assert NativeLinks.for_page("/tasks") == {"tasks", nil}
      assert NativeLinks.for_page("/commercial/sales/accounts") == {"accounts", nil}
      assert NativeLinks.for_page("/commercial/sales/accounts/#{@id}") == {"accounts", @id}
      assert NativeLinks.for_page("/commercial/finance") == {"invoices", nil}
      assert NativeLinks.for_page("/people/time-off") == {"time-off", nil}
      assert NativeLinks.for_page("/people") == {"people", nil}
      assert NativeLinks.for_page("/settings") == {"profile", nil}
    end

    test "never maps children, actions, or non-canonical record IDs" do
      for path <- [
            "/",
            "/tasks/",
            "/tasks/#{@id}",
            "/commercial/sales",
            "/commercial/sales/accounts/new",
            "/commercial/sales/accounts/#{String.upcase(@id)}",
            "/commercial/sales/accounts/#{@id}/edit",
            "/commercial/sales/accounts/#{@id}/",
            "/x/commercial/sales/accounts/#{@id}",
            "/commercial/finance/vendors",
            "/people/time-off/settings",
            "/settings/llm-providers",
            "/orbit",
            "/orbit/#{@id}",
            "/open/tasks",
            nil
          ] do
        assert NativeLinks.for_page(path) == nil, "mapped #{inspect(path)}"
      end
    end
  end

  describe "for_open/1" do
    test "accepts the seven screens and records for tasks, accounts, invoices, and Orbit" do
      for screen <- ~w(tasks accounts invoices time-off people profile orbit) do
        assert NativeLinks.for_open([screen]) == {screen, nil}
      end

      for screen <- ~w(tasks accounts invoices orbit) do
        assert NativeLinks.for_open([screen, @id]) == {screen, @id}
      end
    end

    test "rejects other screens, records, and shapes" do
      for segments <- [
            ["browser"],
            ["notes"],
            ["Tasks"],
            ["people", @id],
            ["time-off", @id],
            ["profile", @id],
            ["tasks", String.upcase(@id)],
            ["tasks", "1-1-1-1-1"],
            ["tasks", @id, "edit"],
            ["orbit", String.upcase(@id)],
            ["orbit", "not-a-uuid"],
            ["orbit", @id, "edit"],
            ["tasks/#{@id}"],
            ["tasks", ["x"]],
            [["tasks"]],
            ["tasks", %{"id" => @id}],
            [nil],
            []
          ] do
        assert NativeLinks.for_open(segments) == nil, "accepted #{inspect(segments)}"
      end
    end
  end

  describe "native_url/1" do
    test "binds the link to the configured origin with an encoded server" do
      stub(Config, :origin, fn -> "https://atlas.example.org" end)

      assert NativeLinks.native_url({"accounts", @id}) ==
               "dev.tuist.atlas://navigate/accounts/#{@id}?server=https%3A%2F%2Fatlas.example.org"

      assert NativeLinks.native_url({"time-off", nil}) ==
               "dev.tuist.atlas://navigate/time-off?server=https%3A%2F%2Fatlas.example.org"

      assert NativeLinks.native_url({"orbit", @id}) ==
               "dev.tuist.atlas://navigate/orbit/#{@id}?server=https%3A%2F%2Fatlas.example.org"
    end

    test "keeps nondefault ports in the server origin" do
      stub(Config, :origin, fn -> "https://atlas.example.org:4443" end)

      assert NativeLinks.native_url({"tasks", nil}) ==
               "dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.example.org%3A4443"
    end

    test "returns nil without an HTTPS origin" do
      stub(Config, :origin, fn -> nil end)
      assert NativeLinks.native_url({"tasks", nil}) == nil
    end
  end

  test "browser_path/1 falls back to sign-in protected web pages" do
    assert NativeLinks.browser_path({"tasks", @id}) == "/tasks"
    assert NativeLinks.browser_path({"accounts", @id}) == "/commercial/sales/accounts/#{@id}"
    assert NativeLinks.browser_path({"accounts", nil}) == "/commercial/sales/accounts"
    assert NativeLinks.browser_path({"invoices", @id}) == "/commercial/finance"
    assert NativeLinks.browser_path({"profile", nil}) == "/settings"
    assert NativeLinks.browser_path({"orbit", @id}) == "/"
    assert NativeLinks.browser_path({"orbit", nil}) == "/"
  end

  test "claimed_paths/0 lists exact pages and UUID-shaped records, never finance" do
    uuid = "????????-????-????-????-????????????"

    assert NativeLinks.claimed_paths() == [
             "/tasks",
             "/commercial/sales/accounts",
             "/commercial/sales/accounts/#{uuid}",
             "/people/time-off",
             "/people",
             "/settings",
             "/open/tasks",
             "/open/accounts",
             "/open/invoices",
             "/open/time-off",
             "/open/people",
             "/open/profile",
             "/open/orbit",
             "/open/tasks/#{uuid}",
             "/open/accounts/#{uuid}",
             "/open/invoices/#{uuid}",
             "/open/orbit/#{uuid}"
           ]
  end

  describe "Config.parse!/1" do
    test "returns empty lists when unset or blank" do
      assert Config.parse!(%{}) == [apple_app_ids: [], android_sha256_fingerprints: []]

      assert Config.parse!(%{"ATLAS_APPLE_APP_IDS" => " ", "ATLAS_ANDROID_APP_LINK_SHA256" => ""}) ==
               [apple_app_ids: [], android_sha256_fingerprints: []]
    end

    test "parses and deduplicates verified identities" do
      fingerprint = Enum.map_join(1..32, ":", fn _ -> "AB" end)

      assert Config.parse!(%{
               "ATLAS_APPLE_APP_IDS" => "U6LC622NKF.dev.tuist.atlas, U6LC622NKF.dev.tuist.atlas",
               "ATLAS_ANDROID_APP_LINK_SHA256" => fingerprint
             }) == [apple_app_ids: ["U6LC622NKF.dev.tuist.atlas"], android_sha256_fingerprints: [fingerprint]]
    end

    test "rejects malformed explicit values instead of dropping them" do
      fingerprint = Enum.map_join(1..32, ":", fn _ -> "AB" end)

      for {name, value} <- [
            {"ATLAS_APPLE_APP_IDS", "dev.tuist.atlas"},
            {"ATLAS_APPLE_APP_IDS", "u6lc622nkf.dev.tuist.atlas"},
            {"ATLAS_APPLE_APP_IDS", "U6LC622NKF.dev.tuist.atlas,"},
            {"ATLAS_ANDROID_APP_LINK_SHA256", String.downcase(fingerprint)},
            {"ATLAS_ANDROID_APP_LINK_SHA256", String.replace(fingerprint, ":", "")},
            {"ATLAS_ANDROID_APP_LINK_SHA256", "AB:CD"}
          ] do
        assert_raise RuntimeError, ~r/#{name}/, fn -> Config.parse!(%{name => value}) end
      end
    end
  end

  test "Config.origin/0 ignores endpoints that are not served over HTTPS" do
    # The test endpoint is configured with plain HTTP.
    assert Config.origin() == nil
  end
end
