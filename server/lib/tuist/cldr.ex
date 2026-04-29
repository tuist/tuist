all_locales = ["ar", "en", "es", "ja", "ko", "ru", "yue-Hant", "zh-Hans", "zh-Hant"]
dev_all_locales? = System.get_env("TUIST_DEV_ALL_LOCALES") in ~w(1 true TRUE yes YES)
locales = if Mix.env() == :dev and not dev_all_locales?, do: ["en"], else: all_locales

data_dir =
  if Mix.env() == :dev do
    cache_home = System.get_env("XDG_CACHE_HOME") || Path.join(System.user_home!(), ".cache")
    Path.join([cache_home, "tuist", "cldr"])
  else
    Path.expand("../../_build/cldr", __DIR__)
  end

defmodule Tuist.Cldr do
  @moduledoc false

  use Cldr,
    otp_app: :tuist,
    default_locale: "en",
    data_dir: data_dir,
    gettext: TuistWeb.Gettext,
    locales: locales,
    precompile_number_formats: ["#,##0"],
    providers: [Cldr.Number]
end
