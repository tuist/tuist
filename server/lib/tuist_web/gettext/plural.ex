defmodule TuistWeb.Gettext.Plural do
  @moduledoc false
  @behaviour Gettext.Plural

  @impl true
  def init(%{locale: locale} = context) when locale in ["yue", "yue_Hant"] do
    # CLDR gives Cantonese one cardinal plural form, like Chinese. Gettext's
    # default locale table does not include it when a catalog omits the header.
    context |> Map.put(:locale, "zh") |> Gettext.Plural.init()
  end

  def init(context), do: Gettext.Plural.init(context)

  @impl true
  defdelegate nplurals(context), to: Gettext.Plural

  @impl true
  defdelegate plural(context, count), to: Gettext.Plural
end
