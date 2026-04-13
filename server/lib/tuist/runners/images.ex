defmodule Tuist.Runners.Images do
  @moduledoc false
  @images %{
    "xcode-26.4" => "ghcr.io/tuist/tuist-runner-xcode-26.4:latest"
  }

  def resolve_image(labels, label_prefix, default_image) do
    case extract_image_alias(labels, label_prefix) do
      nil -> default_image
      alias_name -> Map.get(@images, alias_name, default_image)
    end
  end

  def list_images do
    @images
  end

  defp extract_image_alias(labels, label_prefix) do
    prefix_with_dash = label_prefix <> "-"

    Enum.find_value(labels, fn label ->
      if String.starts_with?(label, prefix_with_dash) do
        String.replace_prefix(label, prefix_with_dash, "")
      end
    end)
  end
end
