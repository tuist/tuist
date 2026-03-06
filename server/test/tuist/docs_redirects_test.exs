defmodule Tuist.Docs.RedirectsTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.Redirects

  describe "redirect_path/1" do
    test "redirects legacy guides routes to English docs routes" do
      assert Redirects.redirect_path("/guides/quick-start/install-tuist") == "/en/guides/install-tuist"
    end

    test "supports wildcard redirects from old documentation routes" do
      assert Redirects.redirect_path("/documentation/tuist/some-legacy-page") == "/"
    end

    test "supports locale placeholder redirects for English" do
      assert Redirects.redirect_path("/en/guides/develop/build/cache") == "/en/guides/develop/cache"
    end

    test "does not include CLI and manifest reference redirects for now" do
      assert is_nil(Redirects.redirect_path("/cli/build"))
      assert is_nil(Redirects.redirect_path("/references/project-description/structs/project"))
    end
  end
end
