defmodule TuistWeb.Gettext.PluralTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Gettext.Plural

  defmodule CantoneseBackend do
    @moduledoc false
    use Gettext.Backend,
      otp_app: :tuist,
      priv: "priv/gettext",
      allowed_locales: ["yue_Hant"],
      plural_forms: Plural
  end

  test "Cantonese without a plural header has one form for every count" do
    for locale <- ["yue", "yue_Hant"] do
      context = Plural.init(%{locale: locale})
      assert Plural.nplurals(context) == 1

      for count <- [0, 1, 2, 10, 100, 1_000_000] do
        assert Plural.plural(context, count) == 0
      end
    end
  end

  test "preserves explicit catalog plural rules" do
    context = Plural.init(%{locale: "yue_Hant", plural_forms_header: "nplurals=1; plural=0;"})
    assert Plural.nplurals(context) == 1
    assert Plural.plural(context, 2) == 0
  end

  test "keeps the default rules for other supported locales" do
    for locale <- ~w(ar en es ja ka ko pl pt ru tr zh_Hans zh_Hant) do
      context = Plural.init(%{locale: locale})
      assert Plural.nplurals(context) == Gettext.Plural.nplurals(locale)

      for count <- [0, 1, 2, 3, 5, 11, 21, 100] do
        assert Plural.plural(context, count) == Gettext.Plural.plural(locale, count)
      end
    end
  end

  test "still rejects unsupported locales" do
    assert_raise Gettext.Plural.UnknownLocaleError, fn ->
      %{locale: "unsupported"} |> Plural.init() |> Plural.nplurals()
    end
  end

  test "compiles the existing Cantonese catalogs even in the English-only test environment" do
    assert CantoneseBackend.__gettext__(:known_locales) == ["yue_Hant"]

    Gettext.with_locale(CantoneseBackend, "yue_Hant", fn ->
      assert is_binary(Gettext.dgettext(CantoneseBackend, "errors", "can't be blank"))

      for count <- [0, 1, 2] do
        assert is_binary(Gettext.dngettext(CantoneseBackend, "dashboard_tests", "Device", "Devices", count))
      end
    end)
  end
end
