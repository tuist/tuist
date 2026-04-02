defmodule Tuist.Cldr do
  @moduledoc false
  use Cldr,
    otp_app: :tuist,
    default_locale: "en",
    data_dir: Path.expand("../../_build/cldr", __DIR__),
    gettext: TuistWeb.Gettext,
    locales: ["ar", "en", "es", "ja", "ko", "pl", "pt", "ru", "tr", "yue-Hant", "zh-Hans", "zh-Hant"],
    precompile_number_formats: ["#,##0"],
    providers: [Cldr.Number]
end
