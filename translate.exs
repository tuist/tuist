Mix.install([
  {:req_llm, "~> 1.9"},
  {:yaml_elixir, "~> 2.11"},
  {:expo, "~> 1.1"}
])

defmodule L10n.Context do
  @l10n_filename "L10N.md"

  def resolve_chain(start_dir, repo_root) do
    start_dir
    |> directories_up_to(repo_root)
    |> Enum.map(&Path.join(&1, @l10n_filename))
    |> Enum.filter(&File.exists?/1)
    |> Enum.reverse()
    |> Enum.map(&parse_file/1)
    |> merge_chain()
  end

  def load_locale_override(start_dir, repo_root, locale) do
    start_dir
    |> directories_up_to(repo_root)
    |> Enum.map(&Path.join([&1, "L10N", "#{locale}.md"]))
    |> Enum.filter(&File.exists?/1)
    |> Enum.reverse()
    |> Enum.map(fn path -> path |> File.read!() |> parse_content() |> elem(1) end)
    |> Enum.join("\n\n")
  end

  def parse_file(path) do
    path |> File.read!() |> parse_content()
  end

  def parse_content(content) do
    case String.split(content, ~r/^---\s*$/m, parts: 3) do
      ["", frontmatter, body] ->
        {:ok, parsed} = YamlElixir.read_from_string(frontmatter)
        {parsed, String.trim(body)}

      _ ->
        {%{}, String.trim(content)}
    end
  end

  defp merge_chain(parsed_files) do
    {frontmatters, bodies} = Enum.unzip(parsed_files)

    merged_frontmatter =
      Enum.reduce(frontmatters, %{}, fn fm, acc ->
        Map.merge(acc, fm, fn
          _key, _old, new when new != nil -> new
          _key, old, _new -> old
        end)
      end)

    merged_body = Enum.join(bodies, "\n\n")
    {merged_frontmatter, merged_body}
  end

  defp directories_up_to(start, root) do
    start = Path.expand(start)
    root = Path.expand(root)
    do_directories_up_to(start, root, [])
  end

  defp do_directories_up_to(current, root, acc) when current == root do
    [current | acc]
  end

  defp do_directories_up_to(current, root, acc) do
    parent = Path.dirname(current)

    if parent == current do
      acc
    else
      do_directories_up_to(parent, root, [current | acc])
    end
  end
end

defmodule L10n.Lock do
  def compute_hash(pot_content, context_content, locale_override) do
    data = pot_content <> "\n---\n" <> context_content <> "\n---\n" <> (locale_override || "")
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  def lock_path(repo_root, pot_relative_path, locale) do
    Path.join([repo_root, ".l10n", pot_relative_path, "#{locale}.lock"])
  end

  def stale?(lock_path, current_hash) do
    case read(lock_path) do
      {:ok, %{"hash" => stored_hash}} -> stored_hash != current_hash
      _ -> true
    end
  end

  def write!(lock_path, hash, model) do
    lock_path |> Path.dirname() |> File.mkdir_p!()

    data = %{
      "hash" => hash,
      "translated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "model" => model
    }

    File.write!(lock_path, JSON.encode!(data))
  end

  defp read(path) do
    case File.read(path) do
      {:ok, content} -> JSON.decode(content)
      {:error, _} -> {:error, :not_found}
    end
  end
end

defmodule L10n.Translator do
  @plural_forms %{
    "es" => "nplurals=2; plural=n != 1;",
    "ja" => "nplurals=1; plural=0;",
    "ko" => "nplurals=1; plural=0;",
    "ru" => "nplurals=3; plural=n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2;",
    "zh_Hans" => "nplurals=1; plural=0;",
    "zh_Hant" => "nplurals=1; plural=0;"
  }

  def resolve_model(model_string) do
    case String.split(model_string, ":", parts: 2) do
      ["ollama", model_id] ->
        ReqLLM.put_key(:openai_api_key, "ollama")

        ReqLLM.model!(%{
          provider: :openai,
          id: model_id,
          base_url: "http://localhost:11434/v1"
        })

      _ ->
        model_string
    end
  end

  def translate(pot_content, locale, language, context_body, locale_override, model) do
    plural_forms = Map.get(@plural_forms, locale, "nplurals=2; plural=n != 1;")

    system_prompt = """
    You are a professional translator specializing in software localization.
    You translate Gettext PO template files from English to #{language} (#{locale}).

    Output ONLY a valid Gettext .po file. No markdown fences, no explanation, no preamble.

    Rules:
    1. The first entry must be the PO header with this exact metadata:
       - Language: #{locale}
       - MIME-Version: 1.0
       - Content-Type: text/plain; charset=UTF-8
       - Content-Transfer-Encoding: 8bit
       - Plural-Forms: #{plural_forms}
    2. Preserve all msgid values exactly as they appear in the source.
    3. Translate each msgid into the corresponding msgstr for #{language}.
    4. Preserve all Elixir interpolation variables like %{name} exactly as-is in the translation.
    5. Preserve all HTML tags exactly as-is in the translation.
    6. Preserve all comment lines (lines starting with #) from the source.
    7. For plural forms (msgid_plural), provide the correct number of msgstr[N] entries for #{language}.
    8. Do not translate proper nouns, brand names, or technical terms unless the context instructs otherwise.
    9. Do not add the fuzzy flag to any translations.
    10. Do not wrap long lines - keep each msgstr on a single line or use the same multi-line format as the source.

    #{context_body}

    #{if locale_override != "", do: "## Locale-specific instructions for #{language}:\n#{locale_override}", else: ""}
    """

    user_prompt = """
    Translate the following .pot file to #{language} (#{locale}):

    #{pot_content}
    """

    import ReqLLM.Context

    messages = [
      system(system_prompt),
      user(user_prompt)
    ]

    resolved_model = resolve_model(model)
    response = ReqLLM.generate_text!(resolved_model, messages, max_tokens: 32_000, receive_timeout: 600_000)

    text =
      case response do
        %ReqLLM.Response{} -> ReqLLM.Response.text(response)
        text when is_binary(text) -> text
      end

    text
    |> String.trim()
    |> String.replace(~r/^```[a-z]*\n/, "")
    |> String.replace(~r/\n```$/, "")
    |> String.trim()
  end

  def translate_all(pot_content, targets, context_body, model, l10n_dir, repo_root, pot_relative_path, opts) do
    force = Keyword.get(opts, :force, false)

    targets
    |> Task.async_stream(
      fn target ->
        locale = target["locale"]
        language = target["language"]
        locale_override = Keyword.get(opts, :locale_override_fn, fn _ -> "" end).(locale)

        hash =
          L10n.Lock.compute_hash(
            pot_content,
            context_body <> locale_override,
            locale_override
          )

        lock_path = L10n.Lock.lock_path(repo_root, pot_relative_path, locale)

        if not force and not L10n.Lock.stale?(lock_path, hash) do
          {:skipped, locale}
        else
          try do
            po_content = translate(pot_content, locale, language, context_body, locale_override, model)

            case L10n.Validator.validate(po_content) do
              :ok ->
                po_filename = Path.basename(pot_relative_path, ".pot") <> ".po"
                output_path = Path.join([l10n_dir, target["path"], po_filename])
                output_path |> Path.dirname() |> File.mkdir_p!()
                File.write!(output_path, po_content <> "\n")
                L10n.Lock.write!(lock_path, hash, model)
                {:translated, locale}

              {:error, reason} ->
                {:error, locale, reason}
            end
          rescue
            e -> {:error, locale, Exception.message(e)}
          end
        end
      end,
      max_concurrency: Keyword.get(opts, :max_concurrency, 4),
      timeout: Keyword.get(opts, :timeout, 300_000)
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end
end

defmodule L10n.Validator do
  def validate(po_content) do
    case Expo.PO.parse_string(po_content) do
      {:ok, _po} -> :ok
      {:error, error} -> {:error, inspect(error)}
    end
  end
end

defmodule L10n.CLI do
  def run(argv) do
    {opts, _rest} = parse_args(argv)
    repo_root = find_repo_root()

    IO.puts("Scanning for L10N.md files...")

    l10n_files = find_l10n_files_with_sources(repo_root)

    if Enum.empty?(l10n_files) do
      IO.puts("No L10N.md files with sources found.")
      System.halt(0)
    end

    results =
      Enum.flat_map(l10n_files, fn l10n_dir ->
        process_l10n_dir(l10n_dir, repo_root, opts)
      end)

    print_summary(results)
  end

  defp process_l10n_dir(l10n_dir, repo_root, opts) do
    {frontmatter, context_body} = L10n.Context.resolve_chain(l10n_dir, repo_root)

    model = Keyword.get(opts, :model) || Map.get(frontmatter, "model", "anthropic:claude-sonnet-4-6")
    sources = Map.get(frontmatter, "sources", [])
    target_path_template = Map.get(frontmatter, "target_path", "priv/gettext/{locale}/LC_MESSAGES")
    raw_targets = Map.get(frontmatter, "targets", %{})

    all_targets =
      raw_targets
      |> normalize_targets(target_path_template)

    targets =
      case Keyword.get(opts, :locale) do
        nil -> all_targets
        locale -> Enum.filter(all_targets, &(&1["locale"] == locale))
      end

    if Enum.empty?(targets) do
      IO.puts("  No matching targets found.")
      []
    else
      pot_files =
        Enum.flat_map(sources, fn pattern ->
          Path.join(l10n_dir, pattern) |> Path.wildcard()
        end)

      Enum.flat_map(pot_files, fn pot_path ->
        pot_relative = Path.relative_to(pot_path, repo_root)
        pot_content = File.read!(pot_path)
        domain = Path.basename(pot_path, ".pot")

        IO.puts("  Translating #{domain}...")

        locale_override_fn = fn locale ->
          L10n.Context.load_locale_override(l10n_dir, repo_root, locale)
        end

        L10n.Translator.translate_all(
          pot_content,
          targets,
          context_body,
          model,
          l10n_dir,
          repo_root,
          pot_relative,
          force: Keyword.get(opts, :force, false),
          locale_override_fn: locale_override_fn,
          max_concurrency: Keyword.get(opts, :concurrency, 4),
          timeout: Keyword.get(opts, :timeout, 300_000)
        )
      end)
    end
  end

  defp normalize_targets(targets, path_template) when is_map(targets) do
    Enum.map(targets, fn {locale, language} ->
      path = String.replace(path_template, "{locale}", locale)
      %{"locale" => locale, "language" => language, "path" => path}
    end)
  end

  defp normalize_targets(targets, _path_template) when is_list(targets), do: targets

  defp parse_args(argv) do
    {opts, rest, _} =
      OptionParser.parse(argv,
        strict: [force: :boolean, locale: :string, model: :string, concurrency: :integer, timeout: :integer],
        aliases: [f: :force, l: :locale, m: :model, c: :concurrency, t: :timeout]
      )

    {opts, rest}
  end

  defp find_repo_root do
    {root, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"])
    String.trim(root)
  end

  defp find_l10n_files_with_sources(repo_root) do
    Path.join([repo_root, "**", "L10N.md"])
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      {frontmatter, _body} = L10n.Context.parse_file(path)
      Map.has_key?(frontmatter, "sources")
    end)
    |> Enum.map(&Path.dirname/1)
  end

  defp print_summary(results) do
    translated = Enum.count(results, &match?({:translated, _}, &1))
    skipped = Enum.count(results, &match?({:skipped, _}, &1))
    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    IO.puts("\n--- Summary ---")
    IO.puts("  Translated: #{translated}")
    IO.puts("  Skipped (up to date): #{skipped}")
    IO.puts("  Errors: #{length(errors)}")

    Enum.each(errors, fn {:error, locale, reason} ->
      IO.puts("    #{locale}: #{reason}")
    end)

    if length(errors) > 0 do
      System.halt(1)
    end
  end
end

L10n.CLI.run(System.argv())
