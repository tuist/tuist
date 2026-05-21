defmodule Tuist.XcodeMirror.AppleReleasesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.XcodeMirror.AppleReleases

  setup :verify_on_exit!

  describe "list_released/1" do
    test "extracts version numbers from xcodereleases.com payload, GA only by default" do
      payload = [
        %{
          "version" => %{
            "number" => "26.4.1",
            "build" => "17E202",
            "release" => %{"release" => true}
          }
        },
        %{
          "version" => %{
            "number" => "26.5",
            "build" => "17F1234",
            "release" => %{"rc" => 1}
          }
        },
        %{
          "version" => %{
            "number" => "26.4",
            "build" => "17E180",
            "release" => %{"release" => true}
          }
        }
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: payload}}
      end)

      assert {:ok, ["26.4.1", "26.4"]} = AppleReleases.list_released()
    end

    test "include_prereleases: true keeps RC/beta entries" do
      payload = [
        %{"version" => %{"number" => "26.5", "release" => %{"rc" => 1}}},
        %{"version" => %{"number" => "26.4.1", "release" => %{"release" => true}}}
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: payload}}
      end)

      assert {:ok, ["26.5", "26.4.1"]} =
               AppleReleases.list_released(include_prereleases: true)
    end

    test "non-200 maps to :bad_status" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 503, body: ""}}
      end)

      assert {:error, {:bad_status, 503}} = AppleReleases.list_released()
    end

    test "transport error maps to :network_error" do
      expect(Req, :get, fn _url, _opts ->
        {:error, %{__exception__: true, reason: :timeout}}
      end)

      assert {:error, {:network_error, _}} = AppleReleases.list_released()
    end

    test "skips entries with empty version numbers" do
      payload = [
        %{"version" => %{"number" => "", "release" => %{"release" => true}}},
        %{"version" => %{"number" => "26.4.1", "release" => %{"release" => true}}}
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: payload}}
      end)

      assert {:ok, ["26.4.1"]} = AppleReleases.list_released()
    end
  end

  describe "download_url/2" do
    test "returns the Apple-CDN URL for a known version" do
      url = "https://download.developer.apple.com/.../Xcode_26.4.1.xip"

      payload = [
        %{
          "version" => %{"number" => "26.4.1", "release" => %{"release" => true}},
          "links" => %{"download" => %{"url" => url}}
        }
      ]

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: payload}}
      end)

      assert AppleReleases.download_url("26.4.1") == url
    end

    test "nil for an unknown version" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      assert is_nil(AppleReleases.download_url("99.0.0"))
    end
  end
end
