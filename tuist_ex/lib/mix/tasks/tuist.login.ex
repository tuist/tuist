defmodule Mix.Tasks.Tuist.Login do
  @shortdoc "Log in to Tuist"

  @moduledoc """
  Log in to Tuist using a browser, an email and password, or a continuous integration provider.

      mix tuist.login [--email EMAIL] [--password PASSWORD] [--url URL]

  When either credential is provided, the task prompts for the missing one.
  """

  use Mix.Task

  def run(args) do
    {options, rest, invalid} =
      OptionParser.parse(args, strict: [email: :string, password: :string, url: :string])

    if rest != [] or invalid != [] do
      Mix.raise("Usage: mix tuist.login [--email EMAIL] [--password PASSWORD] [--url URL]")
    end

    :ok = TuistEx.Auth.login(options)
    Mix.shell().info("Successfully logged in.")
  end
end
