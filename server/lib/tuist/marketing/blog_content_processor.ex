defmodule Tuist.Marketing.BlogContentProcessor do
  @moduledoc """
  Processes blog post HTML content to replace custom markers with Phoenix components.
  """

  @doc """
  Processes blog HTML content and returns a list of content chunks that can include
  both raw HTML and component data.
  """
  def process_content(html_content) do
    # Split content by prose-banner-button-marker tags
    parse_html_chunks(html_content, [])
  end

  defp parse_html_chunks("", acc), do: Enum.reverse(acc)

  defp parse_html_chunks(html, acc) do
    case find_marker(html) do
      {:found, before, marker_data, after_html} ->
        # Add the HTML before the marker
        new_acc = [{:html, before} | acc]
        # Add the component marker
        new_acc = [{:component, :button, marker_data} | new_acc]
        # Continue parsing the rest
        parse_html_chunks(after_html, new_acc)

      :not_found ->
        # No more markers, add remaining HTML
        Enum.reverse([{:html, html} | acc])
    end
  end

  defp find_marker(html) do
    # Look for <prose-banner-button-marker> tags with attributes
    # The tag might span multiple lines with whitespace and newlines
    # Match everything between opening tag and closing tag (or self-closing)
    regex = ~r/<prose-banner-button-marker\s+([^>]*?)>\s*<\/prose-banner-button-marker>/s

    case Regex.run(regex, html, return: :index) do
      [{start, length} | _] ->
        before = String.slice(html, 0, start)
        marker_html = String.slice(html, start, length)
        after_html = String.slice(html, start + length, String.length(html))

        # Extract attributes from marker
        marker_data = extract_marker_data(marker_html)

        {:found, before, marker_data, after_html}

      nil ->
        :not_found
    end
  end

  defp extract_marker_data(marker_html) do
    title = extract_attribute(marker_html, "data-cta-title")
    href = extract_attribute(marker_html, "data-cta-href")

    %{title: title, href: href}
  end

  defp extract_attribute(html, attr_name) do
    case Regex.run(~r/#{attr_name}="([^"]*)"/, html) do
      [_, value] -> value
      _ -> nil
    end
  end
end
