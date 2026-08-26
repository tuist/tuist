defmodule Tuist.LocaleTest do
  use ExUnit.Case, async: true

  alias Tuist.Locale

  describe "collapse_locale_path_prefix/1" do
    # Collapsing relies on Tuist.Locale.languages/0, which is trimmed to "en"
    # unless TUIST_DEV_ALL_LOCALES=1.
    @describetag :locale

    test "collapses the locale segment of a localized route" do
      assert Locale.collapse_locale_path_prefix("/ja/pricing") == "/:locale/pricing"

      assert Locale.collapse_locale_path_prefix("/zh_Hant/customers/:slug") ==
               "/:locale/customers/:slug"

      assert Locale.collapse_locale_path_prefix("/yue_Hant/docs/*path") == "/:locale/docs/*path"
    end

    test "collapses a locale home route" do
      assert Locale.collapse_locale_path_prefix("/ka") == "/:locale"
    end

    test "leaves English routes alone so they stay separable from the other locales" do
      assert Locale.collapse_locale_path_prefix("/en/docs") == "/en/docs"
    end
  end

  describe "collapse_locale_path_prefix/1 for paths without a locale" do
    test "leaves unlocalized routes alone" do
      assert Locale.collapse_locale_path_prefix("/") == "/"
      assert Locale.collapse_locale_path_prefix("/pricing") == "/pricing"

      assert Locale.collapse_locale_path_prefix("/api/projects/:account_handle") ==
               "/api/projects/:account_handle"
    end

    test "leaves an unresolved route label alone" do
      assert Locale.collapse_locale_path_prefix("Unknown") == "Unknown"
    end

    test "does not collapse a route whose first segment is a path parameter" do
      assert Locale.collapse_locale_path_prefix("/:account_handle/:project_handle") ==
               "/:account_handle/:project_handle"
    end
  end
end
