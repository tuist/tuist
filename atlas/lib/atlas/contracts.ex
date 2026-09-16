defmodule Atlas.Contracts do
  @moduledoc """
  Reads enterprise-contract `.docx` templates from `priv/contracts/templates/`
  and mints short-lived signed download URLs for them.

  The MCP surface (`list_contract_templates`, `get_contract_template`, and the
  `generate_enterprise_contract` prompt) exposes templates and customer data so
  the local coding agent can produce filled documents on the user's machine.
  Atlas does not generate or store the produced files.
  """

  alias Atlas.Contracts.Template
  alias AtlasWeb.Endpoint

  @download_salt "contract-template-download"
  @download_max_age 86_400
  @current_template_set "2026-02"
  @docx_content_type "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

  def default_template_set, do: @current_template_set

  def docx_content_type, do: @docx_content_type

  def download_max_age, do: @download_max_age

  def list_template_sets do
    case File.ls(templates_root()) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&File.dir?(Path.join(templates_root(), &1)))
        |> Enum.sort()

      {:error, _reason} ->
        []
    end
  end

  def list_templates(template_set \\ @current_template_set) when is_binary(template_set) do
    set_dir = set_dir(template_set)

    case File.ls(set_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".docx"))
        |> Enum.sort()
        |> Enum.map(&build_template(template_set, &1, set_dir))

      {:error, _reason} ->
        []
    end
  end

  def fetch_template(template_set, filename) when is_binary(template_set) and is_binary(filename) do
    if valid_filename?(filename) do
      case Enum.find(list_templates(template_set), &(&1.filename == filename)) do
        nil -> {:error, :not_found}
        %Template{} = template -> {:ok, template}
      end
    else
      {:error, :not_found}
    end
  end

  def template_path(%Template{template_set: set, filename: filename}) do
    Path.join(set_dir(set), filename)
  end

  def sign_download_token(%Template{template_set: set, filename: filename}) do
    Phoenix.Token.sign(Endpoint, @download_salt, %{"template_set" => set, "filename" => filename})
  end

  def verify_download_token(token) when is_binary(token) do
    Phoenix.Token.verify(Endpoint, @download_salt, token, max_age: @download_max_age)
  end

  def verify_download_token(_token), do: {:error, :missing}

  def download_url(%Template{template_set: set, filename: filename} = template) do
    Endpoint.url()
    |> URI.new!()
    |> URI.append_path("/contracts/templates/#{set}/#{filename}")
    |> URI.append_query(URI.encode_query(%{"token" => sign_download_token(template)}))
    |> URI.to_string()
  end

  defp build_template(template_set, filename, set_dir) do
    %Template{
      template_set: template_set,
      filename: filename,
      kind: kind_for(filename),
      title: title_for(filename),
      byte_size: File.stat!(Path.join(set_dir, filename)).size
    }
  end

  defp kind_for("msa.docx"), do: :msa
  defp kind_for("annex-2-dpa.docx"), do: :annex_dpa
  defp kind_for("annex-3-daa.docx"), do: :annex_daa
  defp kind_for("annex-4-sla.docx"), do: :annex_sla
  defp kind_for("order-form-tuist-hosted.docx"), do: :order_form_tuist_hosted
  defp kind_for("order-form-self-hosted.docx"), do: :order_form_self_hosted
  defp kind_for(_filename), do: :other

  defp title_for("msa.docx"), do: "Master Services Agreement"
  defp title_for("annex-2-dpa.docx"), do: "Annex 2: Data Processing Agreement"
  defp title_for("annex-3-daa.docx"), do: "Annex 3: Data Access Agreement"
  defp title_for("annex-4-sla.docx"), do: "Annex 4: Service Level Agreement"
  defp title_for("order-form-tuist-hosted.docx"), do: "Order Form (Tuist-hosted)"
  defp title_for("order-form-self-hosted.docx"), do: "Order Form (Self-hosted)"
  defp title_for(filename), do: filename

  defp templates_root, do: Application.app_dir(:atlas, "priv/contracts/templates")

  defp set_dir(template_set), do: Path.join(templates_root(), template_set)

  # Path-traversal guard: reject anything with a separator or a leading dot.
  defp valid_filename?(filename) do
    filename == Path.basename(filename) and not String.starts_with?(filename, ".")
  end
end
