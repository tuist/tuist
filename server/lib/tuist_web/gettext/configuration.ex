defmodule TuistWeb.Gettext.Configuration do
  @moduledoc false

  defmacro __using__(_opts) do
    allowed_locales =
      if Tuist.Environment.single_locale?() do
        ["en"]
      else
        ~w(ar en es ja ka ko pl pt ru tr yue_Hant zh_Hans zh_Hant)
      end

    quote bind_quoted: [allowed_locales: allowed_locales] do
      use Gettext.Backend, otp_app: :tuist, allowed_locales: allowed_locales
    end
  end
end
