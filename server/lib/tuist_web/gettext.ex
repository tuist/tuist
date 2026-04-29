all_locales = ~w(ar en es ja ko pl pt ru tr yue_Hant zh_Hans zh_Hant)
dev_all_locales? = System.get_env("TUIST_DEV_ALL_LOCALES") in ~w(1 true TRUE yes YES)
allowed_locales = if Mix.env() == :dev and not dev_all_locales?, do: ["en"], else: all_locales

defmodule TuistWeb.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext),
  your module gains a set of macros for translations, for example:

      import TuistWeb.Gettext

      # Simple translation
      gettext("Here is the string to translate")

      # Plural translation
      ngettext("Here is the string to translate",
               "Here are the strings to translate",
               3)

      # Domain-based translation
      dgettext("errors", "Here is the error message to translate")

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """
  use Gettext.Backend, otp_app: :tuist, allowed_locales: allowed_locales
end
