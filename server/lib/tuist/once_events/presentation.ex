defmodule Tuist.OnceEvents.Presentation do
  @moduledoc """
  Bounded ecosystem-owned display metadata. Stable identifiers are never inferred
  from labels, and declared output platforms are not execution placement.
  """

  def normalize(value) when is_map(value) do
    package = normalize_package(get(value, :package))
    platforms = normalize_list(get(value, :platforms), &normalize_platform/1)
    context = normalize_list(get(value, :context), &normalize_context/1)

    if package || platforms != [] || context != [] do
      fit(%{"package" => package, "platforms" => platforms, "context" => context})
    end
  end

  def normalize(_), do: nil

  defp fit(metadata) do
    values =
      if(metadata["package"], do: Map.values(metadata["package"]), else: []) ++
        Enum.flat_map(metadata["platforms"] ++ metadata["context"], &Map.values/1)

    if Enum.sum(Enum.map(values, &byte_size/1)) <= 2048 do
      metadata
    else
      cond do
        metadata["context"] != [] -> fit(Map.update!(metadata, "context", &Enum.drop(&1, -1)))
        metadata["platforms"] != [] -> fit(Map.update!(metadata, "platforms", &Enum.drop(&1, -1)))
        true -> nil
      end
    end
  end

  defp normalize_package(value) when is_map(value) do
    ecosystem = get(value, :ecosystem)
    name = get(value, :name)
    version = get(value, :version) || ""
    revision = get(value, :revision) || ""
    digest = get(value, :digest) || ""
    origin = get(value, :origin) || ""

    if token?(ecosystem) && bounded?(name, 128) &&
         Enum.all?([version, revision, digest], &optional_bounded?(&1, 256)) && optional_token?(origin) do
      %{
        "ecosystem" => ecosystem,
        "name" => name,
        "version" => version,
        "revision" => revision,
        "digest" => digest,
        "origin" => origin
      }
    end
  end

  defp normalize_package(_), do: nil

  defp normalize_platform(value) when is_map(value) do
    scheme = get(value, :scheme)
    id = get(value, :id)
    usage = get(value, :usage) || ""

    if token?(scheme) && bounded?(id, 256) && optional_token?(usage) do
      %{"scheme" => scheme, "id" => id, "label" => display(get(value, :label)), "usage" => usage}
    end
  end

  defp normalize_platform(_), do: nil

  defp normalize_context(value) when is_map(value) do
    key = get(value, :key)
    content = get(value, :value)

    if token?(key) && bounded?(content, 256) do
      %{"key" => key, "value" => content, "label" => display(get(value, :label))}
    end
  end

  defp normalize_context(_), do: nil

  defp normalize_list(values, normalize) when is_list(values) do
    values |> Enum.map(normalize) |> Enum.reject(&is_nil/1) |> Enum.take(8)
  end

  defp normalize_list(_, _), do: []

  defp get(value, key), do: Map.get(value, key, Map.get(value, Atom.to_string(key)))

  defp optional_token?(""), do: true
  defp optional_token?(value), do: token?(value)

  defp token?(value) when is_binary(value) do
    byte_size(value) in 1..64 && String.valid?(value) && Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, value)
  end

  defp token?(_), do: false

  defp optional_bounded?("", _), do: true
  defp optional_bounded?(value, limit), do: bounded?(value, limit)

  defp bounded?(value, limit) when is_binary(value) do
    byte_size(value) in 1..limit && String.valid?(value) && !Regex.match?(~r/[\x00-\x1f\x7f-\x{9f}]/u, value)
  end

  defp bounded?(_, _), do: false

  defp display(value) when is_binary(value) and byte_size(value) <= 128 do
    if String.valid?(value), do: String.replace(value, ~r/[\x00-\x1f\x7f-\x{9f}]/u, " "), else: ""
  end

  defp display(_), do: ""
end
