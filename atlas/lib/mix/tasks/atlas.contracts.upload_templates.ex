defmodule Mix.Tasks.Atlas.Contracts.UploadTemplates do
  @shortdoc "Uploads contract .docx templates to the Atlas object storage bucket"

  @moduledoc """
  Uploads a directory of contract `.docx` templates to the `contracts/templates/`
  prefix of the shared Atlas object storage bucket. This is the one-shot writer
  that pairs with `Atlas.Contracts.Storage` in `:s3` mode (prod default).

  ## Usage

      mix atlas.contracts.upload_templates <local_dir>
      mix atlas.contracts.upload_templates <local_dir> --set 2026-02
      mix atlas.contracts.upload_templates <local_dir> --dry-run

  `<local_dir>` is either the folder that holds the `.docx` files directly
  (`msa.docx`, `annex-2-dpa.docx`, ...) or the parent folder that contains a
  `<set>/` subfolder. `--set` defaults to the current template set
  (`Atlas.Contracts.default_template_set/0`).

  Credentials come from the same env vars runtime.exs reads for
  `Application.get_env(:atlas, :object_storage)`, so a typical invocation
  sources them from 1Password:

      export ATLAS_OBJECT_STORAGE_BUCKET="$(op read op://.../bucket)"
      export ATLAS_OBJECT_STORAGE_ACCESS_KEY_ID="$(op read op://.../username)"
      export ATLAS_OBJECT_STORAGE_SECRET_ACCESS_KEY="$(op read op://.../credential)"
      mix atlas.contracts.upload_templates ./templates/2026-02

  The task never prints credentials.
  """

  use Mix.Task

  alias Atlas.Contracts
  alias Atlas.Contracts.Storage
  alias Atlas.ObjectStorage

  @docx_extension ".docx"

  @impl Mix.Task
  def run(args) do
    {opts, positional, _invalid} =
      OptionParser.parse(args, strict: [set: :string, dry_run: :boolean])

    case positional do
      [local_dir] -> upload(local_dir, opts)
      _other -> Mix.raise("Usage: mix atlas.contracts.upload_templates <local_dir> [--set 2026-02]")
    end
  end

  defp upload(local_dir, opts) do
    template_set = Keyword.get(opts, :set) || Contracts.default_template_set()
    dry_run? = Keyword.get(opts, :dry_run, false)
    source_dir = resolve_source_dir(local_dir, template_set)
    files = list_docx_files(source_dir)

    if files == [] do
      Mix.raise("No .docx files found under #{source_dir}")
    end

    config = if !dry_run?, do: build_config!()

    Enum.each(files, fn filename ->
      path = Path.join(source_dir, filename)
      body = File.read!(path)
      key = Path.join([Storage.s3_prefix(), template_set, filename])

      if dry_run? do
        Mix.shell().info("Would upload #{key} (#{byte_size(body)} bytes)")
      else
        case Storage.put(template_set, filename, body,
               source: :s3,
               content_type: Contracts.docx_content_type(),
               config: config
             ) do
          :ok ->
            Mix.shell().info("Uploaded #{key} (#{byte_size(body)} bytes)")

          {:error, reason} ->
            Mix.raise("Failed to upload #{key}: #{inspect(reason)}")
        end
      end
    end)
  end

  defp resolve_source_dir(local_dir, template_set) do
    expanded = Path.expand(local_dir)

    cond do
      File.dir?(Path.join(expanded, template_set)) -> Path.join(expanded, template_set)
      File.dir?(expanded) -> expanded
      true -> Mix.raise("Local directory not found: #{expanded}")
    end
  end

  defp list_docx_files(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, @docx_extension))
    |> Enum.sort()
  end

  defp build_config! do
    endpoint_url = System.get_env("ATLAS_OBJECT_STORAGE_ENDPOINT_URL", "https://fsn1.your-objectstorage.com")
    region = System.get_env("ATLAS_OBJECT_STORAGE_REGION", "fsn1")
    bucket = fetch_env!("ATLAS_OBJECT_STORAGE_BUCKET")
    access_key_id = fetch_env!("ATLAS_OBJECT_STORAGE_ACCESS_KEY_ID")
    secret_access_key = fetch_env!("ATLAS_OBJECT_STORAGE_SECRET_ACCESS_KEY")

    Application.ensure_all_started(:req)

    %ObjectStorage{
      endpoint_url: endpoint_url,
      region: region,
      bucket: bucket,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      public_base_url: nil
    }
  end

  defp fetch_env!(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" ->
        value

      _missing ->
        Mix.raise("Environment variable #{name} is required")
    end
  end
end
