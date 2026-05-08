# Configure req_llm's internal Finch pool BEFORE Mix.install so the application
# supervisor reads it at startup. req_llm hardcodes the Finch instance to
# ReqLLM.Finch in its provider attach steps, so passing :finch via req_http_options
# is silently overridden — sizing this pool is the only thing that takes effect.
# HTTP/1 only avoids Finch issue #265 with large request bodies.
Application.put_env(:req_llm, :finch,
  name: ReqLLM.Finch,
  pools: %{
    default: [protocols: [:http1], size: 1, count: 128]
  }
)

Mix.install([
  {:req_llm, "~> 1.9"},
  {:yaml_elixir, "~> 2.11"},
  {:expo, "~> 1.1"}
])

defmodule L10n.Context do
  @moduledoc """
  Resolves the hierarchical L10N.md context chain.

  L10N.md files can be nested at any level of the directory tree. When resolving
  context for a given directory, all L10N.md files from the repo root down to that
  directory are collected, parsed, and merged. Frontmatter from deeper files overrides
  parent values; markdown bodies are concatenated (root first).

  Per-locale overrides (e.g., `L10N/es.md`) provide additional context specific
  to a single target language.
  """

  @l10n_filename "L10N.md"

  @doc """
  Resolves the full L10N.md context chain from `repo_root` down to `start_dir`.

  Returns `{merged_frontmatter, merged_body, context_files}` where `context_files`
  is a list of `%{path: relative_path, hash: sha256}` maps for each L10N.md file
  in the chain, ordered from root to deepest.
  """
  def resolve_chain(start_dir, repo_root) do
    l10n_paths =
      start_dir
      |> directories_up_to(repo_root)
      |> Enum.map(&Path.join(&1, @l10n_filename))
      |> Enum.filter(&File.exists?/1)

    parsed = Enum.map(l10n_paths, &parse_file/1)

    context_files =
      Enum.map(l10n_paths, fn path ->
        content = File.read!(path)

        %{
          "path" => Path.relative_to(path, repo_root),
          "hash" => hash_content(content)
        }
      end)

    {merged_frontmatter, merged_body} = merge_chain(parsed)
    {merged_frontmatter, merged_body, context_files}
  end

  @doc """
  Loads per-locale override context for the given locale.

  Walks the same directory chain as `resolve_chain/2` and collects any
  `L10N/{locale}.md` files found. Returns `{override_body, override_files}`.
  """
  def load_locale_override(start_dir, repo_root, locale) do
    override_paths =
      start_dir
      |> directories_up_to(repo_root)
      |> Enum.map(&Path.join([&1, "L10N", "#{locale}.md"]))
      |> Enum.filter(&File.exists?/1)

    body =
      override_paths
      |> Enum.map(fn path -> path |> File.read!() |> parse_content() |> elem(1) end)
      |> Enum.join("\n\n")

    override_files =
      Enum.map(override_paths, fn path ->
        content = File.read!(path)

        %{
          "path" => Path.relative_to(path, repo_root),
          "hash" => hash_content(content)
        }
      end)

    {body, override_files}
  end

  @doc """
  Parses a single L10N.md file into `{frontmatter_map, body_string}`.
  """
  def parse_file(path) do
    path |> File.read!() |> parse_content()
  end

  @doc """
  Splits a string into YAML frontmatter and markdown body.

  Expects content in the format:
      ---
      key: value
      ---
      Markdown body here

  Returns `{frontmatter_map, body_string}`. If no frontmatter delimiters
  are found, returns `{%{}, content}`.
  """
  def parse_content(content) do
    case String.split(content, ~r/^---\s*$/m, parts: 3) do
      ["", frontmatter, body] ->
        {:ok, parsed} = YamlElixir.read_from_string(frontmatter)
        {parsed, String.trim(body)}

      _ ->
        {%{}, String.trim(content)}
    end
  end

  @doc """
  Computes a SHA-256 hex digest of the given content.
  """
  def hash_content(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
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
  @moduledoc """
  Manages lock files that track translation state.

  Each lock file is a JSON document stored at `.l10n/{source_path}/{locale}.lock`
  and contains the full context tree used to produce the translation, including
  individual hashes for the source file and each L10N.md context file.
  A translation is considered stale when any of these hashes change.

  To avoid unnecessary retranslations, source reference comments are normalized
  before hashing so line-number-only churn in `#:` comments does not invalidate
  existing translations.
  """

  @reference_comment_prefix "#: "

  @doc """
  Computes a composite SHA-256 hash from the source content, merged context body,
  and any per-locale override content. This single hash is used for quick
  staleness comparison.
  """
  def compute_hash(source_content, context_content, locale_override, source_format \\ :gettext) do
    data =
      normalized_source_content(source_content, source_format) <>
        "\n---\n" <> context_content <> "\n---\n" <> (locale_override || "")

    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  @doc """
  Computes the source hash stored in the lock file.

  The hash uses normalized reference comments so line-number-only changes in
  Gettext references do not force retranslation.
  """
  def source_hash(source_content, source_format \\ :gettext) do
    normalized_source_content(source_content, source_format)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Returns the file path for a lock file given the repo root, the relative path
  of the source file, and the target locale.

  Example: `lock_path("/repo", "server/priv/docs/en/index.md", "es")`
  returns `"/repo/.l10n/server/priv/docs/en/index.md/es.lock"`
  """
  def lock_path(repo_root, source_relative_path, locale) do
    Path.join([repo_root, ".l10n", source_relative_path, "#{locale}.lock"])
  end

  @doc """
  Returns `true` if the lock file is missing or its stored hash
  differs from `current_hash`.
  """
  def stale?(lock_path, current_hash) do
    case read(lock_path) do
      {:ok, %{"hash" => stored_hash}} -> stored_hash != current_hash
      _ -> true
    end
  end

  @doc """
  Writes a lock file with the full dependency tree.

  The lock represents the hash as a tree of inputs:
  - `source`: the file that was translated
  - `context`: nested L10N.md chain (root -> child -> child), with
    locale overrides attached to the deepest context node

  This makes it easy to see exactly which files contributed to the
  composite hash and why a re-translation was triggered.
  """
  def write!(lock_path, attrs) do
    lock_path |> Path.dirname() |> File.mkdir_p!()

    data =
      %{
        "hash" => attrs.hash,
        "model" => attrs.model,
        "translated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "hash_tree" => %{
          "source" => %{
            "file" => attrs.source_file,
            "hash" => attrs.source_hash
          },
          "context" => build_context_tree(attrs.context_files, attrs.locale_override_files)
        }
      }

    File.write!(lock_path, pretty_json(data))
  end

  defp build_context_tree([], []), do: nil
  defp build_context_tree([], _), do: nil

  defp build_context_tree([root | rest], locale_override_files) do
    node = %{
      "file" => root["path"],
      "hash" => root["hash"]
    }

    case rest do
      [] ->
        maybe_attach_overrides(node, locale_override_files)

      _ ->
        child = build_context_tree(rest, locale_override_files)
        Map.put(node, "child", child)
    end
  end

  defp maybe_attach_overrides(node, []), do: node

  defp maybe_attach_overrides(node, override_files) do
    override_tree = build_override_tree(override_files)
    Map.put(node, "locale_override", override_tree)
  end

  defp build_override_tree([single]), do: %{"file" => single["path"], "hash" => single["hash"]}

  defp build_override_tree([first | rest]) do
    %{
      "file" => first["path"],
      "hash" => first["hash"],
      "child" => build_override_tree(rest)
    }
  end

  defp read(path) do
    case File.read(path) do
      {:ok, content} -> JSON.decode(content)
      {:error, _} -> {:error, :not_found}
    end
  end

  defp normalized_source_content(content, source_format)
       when source_format in [:gettext, "gettext", nil] do
    normalized_pot_content(content)
  end

  defp normalized_source_content(content, _source_format), do: content

  defp normalized_pot_content(content) do
    content
    |> String.split("\n", trim: false)
    |> normalize_pot_lines([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp normalize_pot_lines([], acc), do: acc

  defp normalize_pot_lines([@reference_comment_prefix <> _ = line | rest], acc) do
    {reference_lines, remaining_lines} = take_reference_block([line | rest], [])
    normalized_line = normalize_reference_block(reference_lines)
    normalize_pot_lines(remaining_lines, [normalized_line | acc])
  end

  defp normalize_pot_lines([line | rest], acc) do
    normalize_pot_lines(rest, [line | acc])
  end

  defp take_reference_block([@reference_comment_prefix <> _ = line | rest], acc) do
    take_reference_block(rest, [line | acc])
  end

  defp take_reference_block(lines, acc) do
    {Enum.reverse(acc), lines}
  end

  defp normalize_reference_block(reference_lines) do
    references =
      reference_lines
      |> Enum.flat_map(&reference_tokens/1)
      |> Enum.map(&normalize_reference/1)
      |> Enum.uniq()
      |> Enum.sort()

    @reference_comment_prefix <> Enum.join(references, " ")
  end

  defp reference_tokens(@reference_comment_prefix <> references) do
    String.split(references, ~r/\s+/, trim: true)
  end

  defp normalize_reference(reference) do
    String.replace(reference, ~r/:\d+$/, "")
  end

  defp pretty_json(value, indent \\ 0) do
    pad = String.duplicate("  ", indent)
    inner_pad = String.duplicate("  ", indent + 1)

    case value do
      map when is_map(map) ->
        entries =
          map
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.map(fn {k, v} ->
            "#{inner_pad}#{JSON.encode!(k)}: #{pretty_json(v, indent + 1)}"
          end)
          |> Enum.join(",\n")

        "{\n#{entries}\n#{pad}}"

      list when is_list(list) ->
        if list == [] do
          "[]"
        else
          entries =
            list
            |> Enum.map(fn v -> "#{inner_pad}#{pretty_json(v, indent + 1)}" end)
            |> Enum.join(",\n")

          "[\n#{entries}\n#{pad}]"
        end

      other ->
        JSON.encode!(other)
    end
  end
end

defmodule L10n.Translator do
  @moduledoc """
  Translates .pot files to target locales using an LLM via req_llm.

  Builds a structured prompt with translation rules, context from the L10N.md
  chain, and the full .pot source content. Supports any provider that req_llm
  supports (Anthropic, OpenAI, Ollama, etc.).
  """

  @default_timeout 900_000
  @max_attempts 3
  @base_retry_delay_ms 1_000
  @retryable_statuses [429, 500, 502, 503, 504]
  @retryable_transport_reasons [:closed, :timeout, :econnrefused, :econnreset]

  @plural_forms %{
    "es" => "nplurals=2; plural=n != 1;",
    "ja" => "nplurals=1; plural=0;",
    "ka" => "nplurals=2; plural=n != 1;",
    "ko" => "nplurals=1; plural=0;",
    "ru" =>
      "nplurals=3; plural=n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2;",
    "yue_Hant" => "nplurals=1; plural=0;",
    "zh_Hans" => "nplurals=1; plural=0;",
    "zh_Hant" => "nplurals=1; plural=0;"
  }

  @doc """
  Resolves a model string into a req_llm-compatible model reference.

  Handles `"ollama:model_name"` by configuring a local OpenAI-compatible
  endpoint at `localhost:11434`. All other model strings (e.g.,
  `"anthropic:claude-sonnet-4-6"`, `"openai:gpt-4.1"`) are passed through
  directly to req_llm.
  """
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

  @doc """
  Translates a single .pot file content to the given locale.

  Constructs a system prompt with translation rules and L10N.md context,
  sends the full .pot content as the user message, and returns the
  translated .po file content as a string.
  """
  def translate(pot_content, locale, language, context_body, locale_override, model, timeout) do
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

    case generate_text_with_retries(resolved_model, messages, timeout, locale) do
      {:ok, response} ->
        text =
          response
          |> ReqLLM.Response.text()
          |> String.trim()
          |> String.replace(~r/^```[a-z]*\n/, "")
          |> String.replace(~r/\n```$/, "")
          |> String.trim()

        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def generate_text_with_retries(resolved_model, messages, timeout, locale, attempt \\ 1) do
    case ReqLLM.generate_text(resolved_model, messages,
           max_tokens: 64_000,
           receive_timeout: timeout
         ) do
      {:ok, response} ->
        {:ok, response}

      {:error, error} ->
        handle_retry(error, resolved_model, messages, timeout, locale, attempt)
    end
  end

  defp handle_retry(error, resolved_model, messages, timeout, locale, attempt) do
    case retry_delay_ms(error, attempt) do
      nil ->
        {:error, Exception.message(error)}

      delay ->
        IO.puts(
          "    #{locale}: transient provider error, retrying in #{delay} ms (attempt #{attempt + 1}/#{@max_attempts})"
        )

        Process.sleep(delay)
        generate_text_with_retries(resolved_model, messages, timeout, locale, attempt + 1)
    end
  end

  defp retry_delay_ms(error, attempt) when attempt < @max_attempts do
    if retryable_error?(error), do: backoff_delay_ms(attempt)
  end

  defp retry_delay_ms(_error, _attempt), do: nil

  defp retryable_error?(%ReqLLM.Error.API.Request{status: status})
       when status in @retryable_statuses,
       do: true

  defp retryable_error?(%ReqLLM.Error.API.Response{status: status})
       when status in @retryable_statuses,
       do: true

  defp retryable_error?(%ReqLLM.Error.API.Request{cause: %Req.TransportError{reason: reason}})
       when reason in @retryable_transport_reasons,
       do: true

  defp retryable_error?(%Req.TransportError{reason: reason})
       when reason in @retryable_transport_reasons,
       do: true

  defp retryable_error?(_error), do: false

  defp backoff_delay_ms(attempt) do
    @base_retry_delay_ms * Integer.pow(2, attempt - 1)
  end

  @doc """
  Translates a .pot file to all target locales in parallel.

  For each target, checks the lock file to skip up-to-date translations
  (unless `force: true`). Successful translations are validated, written
  to disk, and locked. Returns a list of `{:translated, locale}`,
  `{:skipped, locale}`, or `{:error, locale, reason}` tuples.
  """
  def translate_all(
        pot_content,
        targets,
        context_body,
        model,
        l10n_dir,
        repo_root,
        pot_relative_path,
        context_files,
        opts
      ) do
    request_timeout = Keyword.get(opts, :timeout, @default_timeout)
    force = Keyword.get(opts, :force, false)
    source_hash = L10n.Lock.source_hash(pot_content)

    targets
    |> Task.async_stream(
      fn target ->
        locale = target["locale"]
        language = target["language"]

        {locale_override, locale_override_files} =
          Keyword.get(opts, :locale_override_fn, fn _ -> {"", []} end).(locale)

        hash =
          L10n.Lock.compute_hash(
            pot_content,
            context_body,
            locale_override
          )

        lock_path = L10n.Lock.lock_path(repo_root, pot_relative_path, locale)

        if not force and not L10n.Lock.stale?(lock_path, hash) do
          {:skipped, locale}
        else
          try do
            with {:ok, po_content} <-
                   translate(
                     pot_content,
                     locale,
                     language,
                     context_body,
                     locale_override,
                     model,
                     request_timeout
                   ),
                 :ok <- L10n.Validator.validate(po_content) do
              po_filename = Path.basename(pot_relative_path, ".pot") <> ".po"
              output_path = Path.join([l10n_dir, target["path"], po_filename])
              output_path |> Path.dirname() |> File.mkdir_p!()
              File.write!(output_path, po_content <> "\n")

              L10n.Lock.write!(lock_path, %{
                hash: hash,
                model: model,
                source_file: pot_relative_path,
                source_hash: source_hash,
                context_files: context_files,
                locale_override_files: locale_override_files
              })

              {:translated, locale}
            else
              {:error, reason} -> {:error, locale, reason}
            end
          rescue
            e -> {:error, locale, Exception.message(e)}
          end
        end
      end,
      max_concurrency: Keyword.get(opts, :max_concurrency, 7),
      timeout: request_timeout + 30_000,
      on_timeout: :kill_task
    )
    |> Enum.zip(targets)
    |> Enum.map(fn
      {{:ok, result}, _target} ->
        result

      {{:exit, :timeout}, target} ->
        {:error, target["locale"], "timed out after #{request_timeout} ms"}

      {{:exit, reason}, target} ->
        {:error, target["locale"], inspect(reason)}
    end)
  end
end

defmodule L10n.Validator do
  @moduledoc """
  Validates translated .po file content.

  Uses `Expo.PO.parse_string/1` to verify the output is syntactically
  valid Gettext PO format.
  """

  @doc """
  Validates that the given string is a syntactically valid .po file.
  Returns `:ok` or `{:error, reason}`.
  """
  def validate(po_content) do
    case Expo.PO.parse_string(po_content) do
      {:ok, _po} -> :ok
      {:error, error} -> {:error, inspect(error)}
    end
  end
end

defmodule L10n.MarkdownValidator do
  @moduledoc """
  Validates translated Tuist documentation markdown.

  The checks intentionally focus on the proprietary structure the docs renderer
  depends on: frontmatter, explicit heading IDs, component tags, links, code
  blocks, and GitHub-style alert markers.
  """

  @frontmatter_regex ~r/\A---\s*\n(?<frontmatter>.*?)\n---\s*\n(?<body>.*)\z/s
  @fenced_code_block_regex ~r/^```[^\n]*\n.*?^```\s*$/ms
  @heading_id_regex ~r/\{#[A-Za-z0-9_-]+\}/
  @alert_marker_regex ~r/^\s*>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/m
  @directive_marker_regex ~r/^:{3,4}[^\n]*$/m
  @inline_code_regex ~r/`([^`\n]+)`/
  @markdown_link_target_regex ~r/\[[^\]\n]+\]\(([^)\s]+)(?:\s+"[^"]*")?\)/
  @attribute_target_regex ~r/\b(?:href|to|src|link)=["']([^"']+)["']/
  @raw_url_regex ~r/https?:\/\/[^\s\])<>"']+/
  @component_tag_regex ~r/<\/?(\.?localized_link|LocalizedLink|HomeCards|HomeCard|Noora\.[A-Za-z0-9_.]+)(?:\s|>|\/)/
  @html_tag_regex ~r/<\/?(a|details|summary|img)(?:\s|>|\/)/
  @heex_expression_regex ~r/(<%.*?%>|\{@[A-Za-z0-9_]+\})/s
  @script_setup_regex ~r/<script\s+setup>.*?<\/script>/s

  @doc """
  Returns `:ok` when the translated markdown preserves the renderer-sensitive
  structure from the source document.
  """
  def validate(source_content, translated_content) do
    with {:ok, source} <- split_document(source_content),
         {:ok, translated} <- split_document(translated_content),
         :ok <- validate_frontmatter(source, translated),
         :ok <-
           validate_sequence(
             "fenced code blocks",
             code_blocks(source.body),
             code_blocks(translated.body)
           ),
         :ok <-
           validate_sequence(
             "inline code spans",
             inline_code_spans(source.body),
             inline_code_spans(translated.body)
           ),
         :ok <-
           validate_sequence(
             "heading anchors",
             heading_ids(source.body),
             heading_ids(translated.body)
           ),
         :ok <-
           validate_sequence(
             "GitHub alert markers",
             alert_markers(source.body),
             alert_markers(translated.body)
           ),
         :ok <-
           validate_sequence(
             "directive markers",
             directive_markers(source.body),
             directive_markers(translated.body)
           ),
         :ok <-
           validate_sequence(
             "link targets",
             link_targets(source.body),
             link_targets(translated.body)
           ),
         :ok <-
           validate_sequence(
             "component tags",
             component_tags(source.body),
             component_tags(translated.body)
           ),
         :ok <- validate_sequence("HTML tags", html_tags(source.body), html_tags(translated.body)),
         :ok <-
           validate_sequence(
             "HEEx expressions",
             heex_expressions(source.body),
             heex_expressions(translated.body)
           ),
         :ok <-
           validate_sequence(
             "script setup blocks",
             script_setup_blocks(source.body),
             script_setup_blocks(translated.body)
           ) do
      :ok
    end
  end

  defp split_document(content) do
    case Regex.named_captures(@frontmatter_regex, content) do
      %{"frontmatter" => frontmatter, "body" => body} ->
        with {:ok, attrs} <- parse_frontmatter(frontmatter) do
          {:ok, %{frontmatter: frontmatter, attrs: attrs, body: body}}
        end

      _ ->
        {:ok, %{frontmatter: nil, attrs: %{}, body: content}}
    end
  end

  defp parse_frontmatter(frontmatter) do
    case YamlElixir.read_from_string(frontmatter) do
      {:ok, attrs} when is_map(attrs) ->
        {:ok, attrs}

      _ ->
        case JSON.decode(frontmatter) do
          {:ok, attrs} when is_map(attrs) -> {:ok, attrs}
          {:error, error} -> {:error, "invalid frontmatter: #{inspect(error)}"}
          _ -> {:error, "frontmatter must be a map"}
        end
    end
  end

  defp validate_frontmatter(%{frontmatter: nil}, %{frontmatter: nil}), do: :ok

  defp validate_frontmatter(%{frontmatter: nil}, %{frontmatter: _}) do
    {:error, "translated document unexpectedly added frontmatter"}
  end

  defp validate_frontmatter(%{frontmatter: _}, %{frontmatter: nil}) do
    {:error, "translated document is missing frontmatter"}
  end

  defp validate_frontmatter(source, translated) do
    source_keys = source.attrs |> Map.keys() |> Enum.sort()
    translated_keys = translated.attrs |> Map.keys() |> Enum.sort()

    if source_keys == translated_keys do
      :ok
    else
      {:error, "frontmatter keys changed"}
    end
  end

  defp validate_sequence(_name, source_values, source_values), do: :ok

  defp validate_sequence(name, _source_values, _translated_values) do
    {:error, "#{name} changed during markdown translation"}
  end

  defp code_blocks(body), do: regex_values(@fenced_code_block_regex, body)

  defp inline_code_spans(body) do
    body
    |> remove_code_blocks()
    |> regex_values(@inline_code_regex)
  end

  defp heading_ids(body), do: regex_values(@heading_id_regex, body)

  defp alert_markers(body) do
    @alert_marker_regex
    |> Regex.scan(body)
    |> Enum.map(fn [_, marker] -> marker end)
  end

  defp directive_markers(body), do: regex_values(@directive_marker_regex, body)

  defp link_targets(body) do
    body_without_code = remove_code_blocks(body)

    markdown_targets = capture_values(@markdown_link_target_regex, body_without_code)
    attribute_targets = capture_values(@attribute_target_regex, body_without_code)
    raw_urls = regex_values(@raw_url_regex, body_without_code)

    markdown_targets ++ attribute_targets ++ raw_urls
  end

  defp component_tags(body) do
    @component_tag_regex
    |> Regex.scan(body)
    |> Enum.map(fn [_, tag] -> tag end)
  end

  defp html_tags(body) do
    @html_tag_regex
    |> Regex.scan(body)
    |> Enum.map(fn [_, tag] -> tag end)
  end

  defp heex_expressions(body), do: regex_values(@heex_expression_regex, body)
  defp script_setup_blocks(body), do: regex_values(@script_setup_regex, body)

  defp remove_code_blocks(body) do
    Regex.replace(@fenced_code_block_regex, body, "")
  end

  defp regex_values(%Regex{} = regex, content) do
    regex
    |> Regex.scan(content)
    |> Enum.map(&List.first/1)
  end

  defp regex_values(content, %Regex{} = regex), do: regex_values(regex, content)

  defp capture_values(regex, content) do
    regex
    |> Regex.scan(content)
    |> Enum.map(fn [_, value | _] -> value end)
  end
end

defmodule L10n.MarkdownTranslator do
  @moduledoc """
  Translates Tuist documentation markdown to target locales using an LLM.
  """

  @default_timeout 900_000

  @doc """
  Translates a single markdown document to the given locale.
  """
  def translate(markdown_content, locale, language, context_body, locale_override, model, timeout) do
    system_prompt = """
    You are a professional translator specializing in technical documentation.
    You translate Tuist documentation markdown from English to #{language} (#{locale}).

    Output ONLY the complete translated markdown file. No markdown fences, no explanation, no preamble.

    Rules:
    1. Preserve the frontmatter delimiters (`---`) and all frontmatter keys.
    2. Translate human-readable frontmatter values such as `title` and `description`, but preserve placeholders such as `:title`.
    3. Preserve all heading IDs exactly, for example `{#install-tuist}`.
    4. Preserve all URLs, email addresses, file paths, command names, inline code spans, fenced code blocks, and code fence language labels exactly.
    5. Preserve GitHub alert markers exactly, for example `> [!TIP]`, but translate the alert title and prose.
    6. Preserve Tuist docs components and Phoenix components exactly, including `<.localized_link>`, `<LocalizedLink>`, `<HomeCards>`, `<HomeCard>`, and `Noora.*` tags.
    7. Preserve renderer-sensitive attributes exactly when they contain links or paths, including `href`, `to`, `src`, and `link`.
    8. Translate visible prose, Markdown link text, headings, table prose, and human-readable component attributes such as `title`, `details`, and `linkText`.
    9. Do not translate proper nouns, product names, or technical terms unless the localization context explicitly says otherwise.
    10. Do not use em dashes. Use regular hyphens or rephrase.

    #{context_body}

    #{if locale_override != "", do: "## Locale-specific instructions for #{language}:\n#{locale_override}", else: ""}
    """

    user_prompt = """
    Translate the following markdown file to #{language} (#{locale}):

    #{markdown_content}
    """

    import ReqLLM.Context

    messages = [
      system(system_prompt),
      user(user_prompt)
    ]

    resolved_model = L10n.Translator.resolve_model(model)

    case L10n.Translator.generate_text_with_retries(resolved_model, messages, timeout, locale) do
      {:ok, response} ->
        text =
          response
          |> ReqLLM.Response.text()
          |> String.trim()
          |> String.replace(~r/^```[a-zA-Z0-9_-]*\n/, "")
          |> String.replace(~r/\n```$/, "")
          |> String.trim()

        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Translates a markdown file to all target locales in parallel.
  """
  def translate_all(
        markdown_content,
        targets,
        context_body,
        model,
        l10n_dir,
        repo_root,
        source_relative_path,
        source_path_relative_to_l10n_dir,
        context_files,
        opts
      ) do
    request_timeout = Keyword.get(opts, :timeout, @default_timeout)
    force = Keyword.get(opts, :force, false)
    source_language = Keyword.get(opts, :source_language, "en")
    source_hash = L10n.Lock.source_hash(markdown_content, :markdown)

    output_relative_path =
      localized_relative_path(source_path_relative_to_l10n_dir, source_language)

    targets
    |> Task.async_stream(
      fn target ->
        locale = target["locale"]
        language = target["language"]

        {locale_override, locale_override_files} =
          Keyword.get(opts, :locale_override_fn, fn _ -> {"", []} end).(locale)

        hash =
          L10n.Lock.compute_hash(
            markdown_content,
            context_body,
            locale_override,
            :markdown
          )

        lock_path = L10n.Lock.lock_path(repo_root, source_relative_path, locale)

        if not force and not L10n.Lock.stale?(lock_path, hash) do
          {:skipped, locale}
        else
          try do
            with {:ok, translated_content} <-
                   translate(
                     markdown_content,
                     locale,
                     language,
                     context_body,
                     locale_override,
                     model,
                     request_timeout
                   ),
                 :ok <- L10n.MarkdownValidator.validate(markdown_content, translated_content) do
              output_path = Path.join([l10n_dir, target["path"], output_relative_path])
              output_path |> Path.dirname() |> File.mkdir_p!()
              File.write!(output_path, translated_content <> "\n")

              L10n.Lock.write!(lock_path, %{
                hash: hash,
                model: model,
                source_file: source_relative_path,
                source_hash: source_hash,
                context_files: context_files,
                locale_override_files: locale_override_files
              })

              {:translated, locale}
            else
              {:error, reason} -> {:error, locale, reason}
            end
          rescue
            e -> {:error, locale, Exception.message(e)}
          end
        end
      end,
      max_concurrency: Keyword.get(opts, :max_concurrency, 7),
      timeout: request_timeout + 30_000,
      on_timeout: :kill_task
    )
    |> Enum.zip(targets)
    |> Enum.map(fn
      {{:ok, result}, _target} ->
        result

      {{:exit, :timeout}, target} ->
        {:error, target["locale"], "timed out after #{request_timeout} ms"}

      {{:exit, reason}, target} ->
        {:error, target["locale"], inspect(reason)}
    end)
  end

  defp localized_relative_path(source_path, source_language) do
    case Path.split(source_path) do
      [^source_language | rest] -> Path.join(rest)
      _ -> source_path
    end
  end
end

defmodule L10n.CLI do
  @moduledoc """
  Entry point for the translation script.

  Parses CLI arguments, discovers L10N.md files with `sources` configured,
  resolves context chains, and orchestrates parallel translation across
  all target locales.

  ## Usage

      elixir translate.exs [options]

  ## Options

    * `--force`, `-f` — Re-translate all files, ignoring lock state
    * `--locale`, `-l` — Translate only the specified locale (e.g., `--locale es`)
    * `--model`, `-m` — Override the LLM model from L10N.md (e.g., `--model openai:gpt-4.1`)
    * `--concurrency`, `-c` — Max parallel translations per locale within one source file (default: 7)
    * `--pot-concurrency` — Max parallel source files being translated at once (default: 4)
    * `--timeout`, `-t` — Timeout in ms per translation request (default: 900000)
  """

  @default_timeout 900_000

  @doc """
  Main entry point. Parses argv and runs the translation pipeline.
  """
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
    {frontmatter, context_body, context_files} = L10n.Context.resolve_chain(l10n_dir, repo_root)

    model = Keyword.get(opts, :model) || Map.get(frontmatter, "model", "openai:gpt-4.1-mini")
    sources = Map.get(frontmatter, "sources", [])

    source_format =
      Map.get(frontmatter, "format") || Map.get(frontmatter, "source_format") || "gettext"

    source_language = Map.get(frontmatter, "source_language", "en")

    target_path_template =
      Map.get(frontmatter, "target_path", "priv/gettext/{locale}/LC_MESSAGES")

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
      source_files =
        Enum.flat_map(sources, fn pattern ->
          Path.join(l10n_dir, pattern) |> Path.wildcard()
        end)

      source_files
      |> Task.async_stream(
        fn source_path ->
          source_relative = Path.relative_to(source_path, repo_root)
          source_path_relative_to_l10n_dir = Path.relative_to(source_path, l10n_dir)
          source_content = File.read!(source_path)
          domain = source_relative |> Path.basename() |> Path.rootname()

          IO.puts("  Translating #{domain}...")

          locale_override_fn = fn locale ->
            L10n.Context.load_locale_override(l10n_dir, repo_root, locale)
          end

          case source_format do
            "markdown" ->
              L10n.MarkdownTranslator.translate_all(
                source_content,
                targets,
                context_body,
                model,
                l10n_dir,
                repo_root,
                source_relative,
                source_path_relative_to_l10n_dir,
                context_files,
                force: Keyword.get(opts, :force, false),
                locale_override_fn: locale_override_fn,
                max_concurrency: Keyword.get(opts, :concurrency, 7),
                source_language: source_language,
                timeout: Keyword.get(opts, :timeout, @default_timeout)
              )

            _ ->
              L10n.Translator.translate_all(
                source_content,
                targets,
                context_body,
                model,
                l10n_dir,
                repo_root,
                source_relative,
                context_files,
                force: Keyword.get(opts, :force, false),
                locale_override_fn: locale_override_fn,
                max_concurrency: Keyword.get(opts, :concurrency, 7),
                timeout: Keyword.get(opts, :timeout, @default_timeout)
              )
          end
        end,
        max_concurrency: Keyword.get(opts, :pot_concurrency, 4),
        # source-level timeout is infinite; per-locale tasks have their own timeout
        timeout: :infinity
      )
      |> Enum.flat_map(fn {:ok, results} -> results end)
    end
  end

  @doc false
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
        strict: [
          force: :boolean,
          locale: :string,
          model: :string,
          concurrency: :integer,
          pot_concurrency: :integer,
          timeout: :integer
        ],
        aliases: [f: :force, l: :locale, m: :model, c: :concurrency, t: :timeout]
      )

    {opts, rest}
  end

  defp find_repo_root do
    {root, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"])
    String.trim(root)
  end

  @doc false
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
