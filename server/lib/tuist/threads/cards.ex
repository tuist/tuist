defmodule Tuist.Threads.Cards do
  @moduledoc """
  Builds and checks the cards a Thread's model writes with the `show_ui` tool:
  one TSX module for NSH (https://nsh.dev), which Tuist Guild's clients run
  natively in a frame of the card's size class (`guild/crates/core`).

  The NSH command line bundles the module and opens it headless, at the
  frame's height and at a narrow and a wide width, before anyone sees it. A
  card that doesn't compile, throws, or doesn't fit its frame is refused with
  what went wrong, so the model can fix it and call the tool again.

  The module is untrusted, and the bundler reads whatever path it imports from
  this machine's disk. So it may import only `nsh` and its modules, checked
  before the build; the bundle's source map must list no module but the card;
  and a failed build's output goes back to the model only when it quotes no
  other file. The card runs in NSH's QuickJS VM, which declares no capability
  but the host's `reply` function, so it reaches no network, file, process or
  clipboard. The command line runs with an empty environment in a disposable
  directory, under time, CPU and address-space limits, with its output capped,
  and a node checks at most two cards at once.
  """

  alias Tuist.Environment

  # Frame heights in points, as the Guild core gives them (`present_card`).
  @heights %{"compact" => 120, "medium" => 240, "tall" => 400}
  # A phone's narrowest conversation and a tablet's or desktop's.
  @widths [320, 600]
  @source_limit 64 * 1024
  # The Guild core drops larger cards.
  @bundle_limit 256 * 1024
  @timeout 30_000
  @feedback_limit 4_000
  # What one command may write: a card at NSH's node limit traces well under it.
  @output_limit 2 * 1024 * 1024
  # The command line's own limits, enforced by the kernel: CPU seconds, and
  # address space in KB (it needs about 1 GB with room for many threads).
  @cpu_seconds 30
  @address_space_kb 4 * 1024 * 1024
  # Cards checked at once on a node, each up to a minute of CPU.
  @slots 2
  @registry Tuist.Threads.Cards.Slots

  @foreign "The card imports a file outside it. A card is one module and may import only `nsh` and its modules, such as `nsh/base`."

  @nsh_json JSON.encode!(%{
              name: "Card",
              id: "dev.tuist.thread-card",
              version: "1.0.0",
              build: 1,
              capabilities: %{host: ["reply"]}
            })

  defmodule Output do
    @moduledoc false
    # What a command writes, up to `limit` bytes; past it, the rest is read
    # and dropped, so a card that logs without end can't fill the node's memory.
    defstruct limit: 0, size: 0, chunks: [], overflow?: false

    def text(%__MODULE__{chunks: chunks}), do: chunks |> Enum.reverse() |> IO.iodata_to_binary()

    defimpl Collectable do
      def into(output) do
        {output,
         fn
           %{overflow?: true} = acc, {:cont, _} ->
             acc

           acc, {:cont, chunk} ->
             size = acc.size + byte_size(chunk)

             if size > acc.limit,
               do: %{acc | chunks: [], overflow?: true},
               else: %{acc | size: size, chunks: [chunk | acc.chunks]}

           acc, :done ->
             acc

           _acc, :halt ->
             :ok
         end}
      end
    end
  end

  def sizes, do: @heights |> Map.keys() |> Enum.sort()

  def available?, do: is_binary(Environment.nsh_path())

  @doc """
  The card's NSH JavaScript bundle, or `{:error, feedback}` saying what to
  fix in `tsx`.
  """
  def build(tsx, size) when is_binary(tsx) and is_binary(size) do
    with {:ok, height} <- height(size),
         :ok <- check_source(tsx),
         {:ok, nsh} <- nsh(),
         :ok <- take_slot() do
      {:ok, dir} = Briefly.create(type: :directory)

      try do
        File.write!(Path.join(dir, "App.tsx"), tsx)
        File.write!(Path.join(dir, "nsh.json"), @nsh_json)
        File.write!(Path.join(dir, "check.test.tsx"), test_file(height))

        with {:ok, _} <- nsh |> run(["build", "App.tsx", "--release", "--out", "out"], dir) |> quoting_only_card(),
             :ok <- only_card_bundled(dir),
             {:ok, trace} <- run(nsh, ["test", "check.test.tsx", "--trace"], dir),
             :ok <- fits(trace, height) do
          bundle(Path.join(dir, "out/bundle.js"))
        end
      after
        File.rm_rf(dir)
        Registry.unregister(@registry, :build)
      end
    end
  end

  def build(_tsx, _size), do: {:error, "Give the card's TSX as `tsx` and its size class as `size`."}

  @doc """
  The registry that counts the cards a node is checking; the application
  starts it.
  """
  def child_spec(_), do: Registry.child_spec(keys: :duplicate, name: @registry)

  # Registers first and counts after, so two callers racing for the last slot
  # may both be refused but never both admitted.
  defp take_slot do
    {:ok, _} = Registry.register(@registry, :build, nil)

    if length(Registry.lookup(@registry, :build)) <= @slots do
      :ok
    else
      Registry.unregister(@registry, :build)
      {:error, "The server is checking other cards. Try again in a moment, or answer in text."}
    end
  end

  defp height(size) do
    case @heights do
      %{^size => height} -> {:ok, height}
      _ -> {:error, "Unknown size #{inspect(size)}: use one of #{Enum.join(sizes(), ", ")}."}
    end
  end

  defp nsh do
    case Environment.nsh_path() do
      nil -> {:error, "Cards can't be shown on this server."}
      path -> {:ok, path}
    end
  end

  @doc """
  Checks the card's TSX before anything reads it. It errs towards refusing:
  it can't tell code from strings, comments and JSX text, so it also looks
  there. The checks after the build are what decide.
  """
  def check_source(tsx) do
    specifiers = Regex.scan(~r/\b(?:from|import)\s*["']([^"']*)["']/, tsx, capture: :all_but_first)

    cond do
      byte_size(tsx) > @source_limit ->
        {:error, "The card's TSX is longer than #{div(@source_limit, 1024)} KB. Show less."}

      # JavaScript allows comments where the patterns below expect only
      # whitespace, so refusing them there leaves nothing between.
      Regex.match?(~r{\b(?:from|import|require)\s*/[*/]}, tsx) ->
        {:error, "Put no comment right after `import`, `from` or `require`."}

      Regex.match?(~r/\bimport\s*[(.]|\brequire\s*\(/, tsx) ->
        {:error,
         "Import modules statically at the top of the card; `import()`, `import.meta` and `require` aren't available. " <>
           "If it's text, not code, word it differently."}

      bad = Enum.find(specifiers, fn [specifier] -> not Regex.match?(~r{\Ansh(/[a-z0-9-]+)*\z}, specifier) end) ->
        {:error,
         "The card imports #{inspect(hd(bad))}. A card is one module and may import only `nsh` and its modules, such as `nsh/base`. " <>
           "If it's text, not an import, word it differently."}

      true ->
        :ok
    end
  end

  defp test_file(height) do
    """
    import { open, test } from "nsh/test";

    for (const width of #{JSON.encode!(@widths)}) {
      test(`at ${width} points wide`, async () => {
        await open("./App.tsx", { width, height: #{height}, host: { handlers: { reply: () => null } } });
      });
    }
    """
  end

  defp run(nsh, args, dir) do
    # The command line and the card's VM see none of the server's environment.
    env =
      System.get_env()
      |> Map.new(fn {key, _} -> {key, nil} end)
      |> Map.merge(%{"PATH" => "/usr/local/bin:/usr/bin:/bin", "HOME" => dir, "NO_COLOR" => "1"})

    # The kernel stops it past its CPU time and address space (Linux only:
    # macOS refuses an address-space limit), so it can't take the node down.
    limits =
      if :os.type() == {:unix, :linux},
        do: "ulimit -t #{@cpu_seconds} && ulimit -v #{@address_space_kb}",
        else: "ulimit -t #{@cpu_seconds}"

    # As `Tuist.Processor.XCActivityLogParser` does: `MuonTrap.cmd`
    # acknowledges output over the child's stdin, which exits the caller with
    # `:epipe` when the command exits first. Plain muontrap still kills the
    # command when the task stops.
    task =
      Task.async(fn ->
        System.cmd(
          MuonTrap.muontrap_path(),
          ["--", "/bin/sh", "-c", ~s(#{limits} && exec "$0" "$@"), nsh | args],
          cd: dir,
          env: env,
          stderr_to_stdout: true,
          into: %Output{limit: @output_limit}
        )
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      nil ->
        {:error, "The card took longer than #{div(@timeout, 1000)} seconds to build and open."}

      {:ok, {%Output{overflow?: true}, _}} ->
        {:error, "The card wrote more than #{div(@output_limit, 1024 * 1024)} MB while building and opening. Don't log."}

      {:ok, {output, 0}} ->
        {:ok, Output.text(output)}

      {:ok, {output, _status}} ->
        {:error, feedback(Output.text(output), dir)}
    end
  end

  # A failed build may quote the files the card imports, such as a parse
  # error's code frame, so its output reaches the model only when every
  # place it points to is the card's own.
  defp quoting_only_card({:error, feedback} = error) do
    places = Regex.scan(~r/([^\s\[\]()"'`]+):\d+:\d+/, feedback, capture: :all_but_first)
    if Enum.all?(places, &(&1 in [["App.tsx"], ["./App.tsx"]])), do: error, else: {:error, @foreign}
  end

  defp quoting_only_card(result), do: result

  # The bundler lists every module it read in the source map: only the card,
  # since nsh's modules stay outside the bundle.
  defp only_card_bundled(dir) do
    with {:ok, map} <- File.read(Path.join(dir, "out/bundle.js.map")),
         {:ok, %{"sources" => ["App.tsx"]}} <- JSON.decode(map) do
      :ok
    else
      _ -> {:error, @foreign}
    end
  end

  # What the command line said about the card, without the directory it ran
  # in, its warnings, timings and the trace's mount batches.
  defp feedback(output, dir) do
    output
    |> String.replace(dir <> "/", "")
    |> String.replace(dir, ".")
    |> String.replace(~r/\e\[[0-9;]*m/, "")
    |> String.split("\n")
    |> Enum.reject(&Regex.match?(~r/^\s*(warn |perf |✓ |── )|^\s+[A-Z]\w* \{/, &1))
    |> Enum.join("\n")
    |> String.trim()
    |> String.slice(0, @feedback_limit)
  end

  defp bundle(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @bundle_limit -> {:ok, File.read!(path)}
      {:ok, _} -> {:error, "The card's bundle is larger than #{div(@bundle_limit, 1024)} KB. Show less."}
      {:error, _} -> {:error, "The card didn't build."}
    end
  end

  @doc """
  Whether every view the card opened with fits its frame, from the mount
  batches `nsh test --trace` prints for each `open`. Views inside a scroll
  view or a list may extend past it, since the person scrolls them.
  """
  def fits(trace, height) do
    trace
    |> String.split("\n")
    |> Enum.chunk_while(nil, &chunk_open/2, &{:cont, &1, nil})
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn lines -> overflow(Enum.reverse(lines), height) end)
    |> case do
      nil -> :ok
      message -> {:error, message}
    end
  end

  defp chunk_open(line, acc) do
    cond do
      String.starts_with?(line, "── open(") and acc -> {:cont, acc, [line]}
      String.starts_with?(line, "── open(") -> {:cont, [line]}
      acc -> {:cont, [line | acc]}
      true -> {:cont, nil}
    end
  end

  defp overflow(lines, height) do
    tree =
      Enum.reduce(lines, %{parents: %{}, kinds: %{}, frames: %{}}, fn line, tree ->
        cond do
          match = Regex.run(~r/Create \{ id: (\d+), kind: (\w+)/, line) ->
            [_, id, kind] = match
            put_in(tree, [:kinds, id], kind)

          match = Regex.run(~r/Insert \{ parent: (\d+), child: (\d+)/, line) ->
            [_, parent, child] = match
            put_in(tree, [:parents, child], parent)

          match = Regex.run(~r/(?:Remove|Delete) \{[^}]*?(?:child|id): (\d+)/, line) ->
            [_, id] = match
            update_in(tree, [:parents], &Map.delete(&1, id))

          match = Regex.run(~r/Frame \{ id: (\d+), x: (-?[\d.]+), y: (-?[\d.]+), w: ([\d.]+), h: ([\d.]+)/, line) ->
            [_, id | values] = match
            put_in(tree, [:frames, id], Enum.map(values, &number/1))

          true ->
            tree
        end
      end)

    root = Enum.find_value(tree.parents, fn {child, parent} -> if parent == "1", do: child end)
    width = with [_, _, w, _] <- tree.frames[root], do: w

    bottom =
      tree.frames
      |> Map.keys()
      |> Enum.reject(&scrolled?(tree, &1))
      |> Enum.map(&absolute(tree, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn [_x, y, _w, h] -> y + h end)
      |> Enum.max(fn -> 0 end)

    if bottom > height + 1 do
      "The card's content is #{round(bottom)} points tall at #{round(width || 0)} points wide, but its frame is #{height}. " <>
        "Use a larger size, show less, or put long content in a `Scroll`."
    end
  end

  # Inside a scroll view or a list, below the card's root.
  defp scrolled?(tree, id) do
    case tree.parents[id] do
      nil -> false
      "1" -> false
      parent -> tree.kinds[parent] in ["Scroll", "List"] or scrolled?(tree, parent)
    end
  end

  # The view's frame in the card's coordinates, if it's on screen.
  defp absolute(tree, id) do
    with [x, y, w, h] <- tree.frames[id], parent when is_binary(parent) <- tree.parents[id] do
      case parent do
        "1" ->
          [x, y, w, h]

        _ ->
          with [px, py, _, _] <- absolute(tree, parent), do: [px + x, py + y, w, h]
      end
    else
      _ -> nil
    end
  end

  defp number(text) do
    case Float.parse(text) do
      {value, _} -> value
      :error -> 0.0
    end
  end
end
