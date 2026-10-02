defmodule Mix.Tasks.Atlas.Docs.Images do
  @shortdoc "Generate documentation social preview images"
  @moduledoc "Generates Atlas documentation social preview images using headless Chrome."
  use Mix.Task

  alias AtlasWeb.Docs.SocialImage
  alias AtlasWeb.DocsHTML

  @output Path.expand("../../../priv/static/images/docs", __DIR__)

  def run(_args) do
    Mix.Task.run("compile")

    chrome =
      System.get_env("ATLAS_DOCS_CHROME_PATH") || System.find_executable("google-chrome") ||
        System.find_executable("chromium") || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    if !File.exists?(chrome), do: Mix.raise("Set ATLAS_DOCS_CHROME_PATH to an installed Chrome executable")
    output = @output
    File.mkdir_p!(output)

    temporary =
      Path.join(output, ".atlas-docs-images-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}")

    File.mkdir_p!(temporary)

    try do
      for page <- DocsHTML.pages() do
        name = if(page.slug == "", do: "overview", else: page.slug)
        html = Path.join(temporary, name <> ".html")
        image = Path.join(temporary, name <> ".png")
        destination = Path.join(output, name <> ".png")
        File.mkdir_p!(Path.dirname(html))
        File.write!(html, SocialImage.render(page))

        capture(
          chrome,
          [
            "--headless",
            "--disable-gpu",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-networking",
            "--disable-extensions",
            "--timeout=10000",
            "--hide-scrollbars",
            "--user-data-dir=#{temporary}/profile",
            "--window-size=1920,1080",
            "--screenshot=#{image}",
            "file://#{URI.encode(html, &(&1 == ?/ or URI.char_unreserved?(&1)))}"
          ],
          image
        )

        File.mkdir_p!(Path.dirname(destination))
        File.rename!(image, destination)
        Mix.shell().info("Generated #{Path.relative_to_cwd(destination)}")
      end
    after
      File.rm_rf!(temporary)
    end
  end

  defp capture(chrome, args, image) do
    port = Port.open({:spawn_executable, chrome}, [:binary, :exit_status, :stderr_to_stdout, args: args])

    try do
      wait_for_image(port, image, System.monotonic_time(:millisecond) + 15_000, "")
    after
      # Some Chrome builds retain the browser after writing a screenshot.
      # Stop only our isolated process and bound the generation step.
      if info = Port.info(port, :os_pid) do
        {:os_pid, pid} = info
        System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
        Port.close(port)
      end
    end
  end

  defp wait_for_image(port, image, deadline, output) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    cond do
      valid_image?(image) ->
        :ok

      remaining == 0 ->
        Mix.raise("Chrome timed out rendering #{image}\n#{output}")

      true ->
        receive do
          {^port, {:data, data}} ->
            output = output <> data
            output = binary_part(output, max(byte_size(output) - 8192, 0), min(byte_size(output), 8192))
            wait_for_image(port, image, deadline, output)

          {^port, {:exit_status, status}} ->
            if !valid_image?(image),
              do:
                Mix.raise(
                  "Chrome exited with status #{status} without a valid documentation image: #{image}\n#{output}"
                )
        after
          min(remaining, 200) -> wait_for_image(port, image, deadline, output)
        end
    end
  end

  defp valid_image?(path) do
    case File.read(path) do
      {:ok, <<137, 80, 78, 71, 13, 10, 26, 10, _length::32, "IHDR", 1920::32, 1080::32, rest::binary>>} ->
        String.ends_with?(rest, <<0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>)

      _ ->
        false
    end
  end
end
