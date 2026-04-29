defmodule Tuist.Cldr.Configuration do
  @moduledoc false

  defmacro __using__(_opts) do
    locales =
      if Tuist.Environment.dev_single_locale?() do
        ["en"]
      else
        ["ar", "en", "es", "ja", "ko", "ru", "yue-Hant", "zh-Hans", "zh-Hant"]
      end

    data_dir =
      if Tuist.Environment.dev?() do
        cache_home = System.get_env("XDG_CACHE_HOME") || Path.join(System.user_home!(), ".cache")
        Path.join([cache_home, "tuist", "cldr"])
      else
        Path.expand("../../../_build/cldr", __DIR__)
      end

    quote bind_quoted: [data_dir: data_dir, locales: locales] do
      use Cldr,
        otp_app: :tuist,
        default_locale: "en",
        data_dir: data_dir,
        gettext: TuistWeb.Gettext,
        locales: locales,
        precompile_number_formats: ["#,##0"],
        providers: [Cldr.Number]
    end
  end
end
