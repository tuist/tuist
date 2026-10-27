defmodule TuistWeb.Gettext.Configuration do
  @moduledoc false

  defmacro __using__(_opts) do
    allowed_locales =
      if apply(Tuist.Environment, :single_locale?, []) do
        ["en"]
      else
        ~w(ar en es ja ka ko pl pt ru tr yue_Hant zh_Hans zh_Hant)
      end

    quote bind_quoted: [allowed_locales: allowed_locales] do
      # Gettext compiles each locale/domain module in a ParallelCompiler async task that
      # waits on the plural module. If it is not compiled yet, the compiler only resumes
      # those tasks on its 10s threshold tick, stalling cold compiles for ~30 minutes.
      require TuistWeb.Gettext.Plural

      use Gettext.Backend,
        otp_app: :tuist,
        allowed_locales: allowed_locales,
        plural_forms: TuistWeb.Gettext.Plural,
        split_module_by: [:locale, :domain]
    end
  end
end
