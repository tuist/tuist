defmodule Tuist.Sandboxes.Xcode do
  @moduledoc """
  The Xcodes macOS sandboxes serve, and the template each one boots.

  Each Xcode is a template of its own, `macos-xcode-<xcode-dashes>`, which
  the macOS hosts clone from that Xcode's CI runner image
  (`infra/tart-kubelet/macos-sandboxes.md`). `macos` boots the default
  Xcode, the first of `versions/0`. A sandbox keeps its template for life, so
  a sandbox that names its Xcode keeps it when the default moves.

  Callers pick the Xcode with an exact `xcode_version`, as runner profiles
  do; Tuist does not read a repository's `.xcode-version`. A version the
  hosts do not serve is refused with the served list.
  """
  import Ecto.Changeset

  @default_template "macos"

  @doc "The served Xcodes, the default first. Empty when this server serves only the `macos` template."
  def versions, do: Tuist.Environment.macos_sandbox_xcode_versions()

  @doc "The template a macOS sandbox boots for `version`; `nil` is the default Xcode's `macos`."
  def template(nil), do: @default_template
  def template(version) when is_binary(version), do: "macos-xcode-" <> String.replace(version, ".", "-")

  @doc """
  The served Xcode a template boots: the version whose `template/1` it is, or
  the default for `macos`. `nil` for any other template, or when this server
  serves only the `macos` template and so knows no version.
  """
  def version(template) do
    case {versions(), template} do
      {[default | _], @default_template} -> default
      {served, _} -> Enum.find(served, &(template(&1) == template))
    end
  end

  @doc """
  Validates `:xcode_version`: only a macOS platform takes one, and it must be
  served.
  """
  def validate(changeset) do
    case get_field(changeset, :xcode_version) do
      nil ->
        changeset

      version ->
        cond do
          get_field(changeset, :platform) != :darwin ->
            add_error(changeset, :xcode_version, "is only supported on macOS (platform darwin)")

          version in versions() ->
            changeset

          versions() == [] ->
            add_error(changeset, :xcode_version, "is not available: this server's macOS sandboxes serve one Xcode")

          true ->
            add_error(changeset, :xcode_version, "must be one of: %{versions}", versions: Enum.join(versions(), ", "))
        end
    end
  end

  @doc "`:ok` when a macOS sandbox can boot `version`, otherwise `{:error, {:unserved_xcode_version, version}}`."
  def served(nil), do: :ok
  def served(version), do: if(version in versions(), do: :ok, else: {:error, {:unserved_xcode_version, version}})
end
