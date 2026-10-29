defmodule AtlasWeb.Utilities.Avatar do
  @moduledoc false

  def gravatar_url(email) when is_binary(email) do
    normalized_email = email |> String.trim() |> String.downcase()

    if normalized_email != "" do
      hash =
        normalized_email
        |> then(&:crypto.hash(:md5, &1))
        |> Base.encode16(case: :lower)

      "https://gravatar.com/avatar/#{hash}?d=404"
    end
  end

  def gravatar_url(_email), do: nil
end
