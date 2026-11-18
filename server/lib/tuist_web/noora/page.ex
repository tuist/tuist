defmodule TuistWeb.Noora.Page do
  @moduledoc """
  Defines a page of the Noora documentation at `/noora`.

  A component page declares the function components it documents and its
  examples:

      defmodule TuistWeb.Noora.Pages.Button do
        use TuistWeb.Noora.Page,
          title: "Button",
          description: "Triggers an action or navigates to another location.",
          components: [{Noora.Button, :button}]

        example "Variants", description: "Use primary for the main action." do
          ~H\"\"\"
          <.button label="Save" variant="primary" />
          \"\"\"
        end
      end

  Each `example` block renders live on the page, and its exact source is shown
  as the example's code, so the two cannot drift apart. The API reference is
  read from the components' `attr` and `slot` declarations.

  Pages that are not about a single component (the introduction and the
  foundations) define `content/1` instead of, or in addition to, examples.
  Pass `nav_title:` when the sidebar should name the page differently from
  its heading.
  """

  @callback content(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @optional_callbacks content: 1

  defmacro __using__(opts) do
    quote do
      @behaviour TuistWeb.Noora.Page

      use Phoenix.Component
      use Noora

      # `use Noora` leaves out Noora.Time, whose `time/1` would otherwise
      # clash with callers' own imports.
      import Noora.Time
      import TuistWeb.Noora.Components, only: [docs_code_window: 1, rich_text: 1]
      import TuistWeb.Noora.Page, only: [example: 2, example: 3]

      Module.register_attribute(__MODULE__, :noora_examples, accumulate: true)

      @noora_page_opts unquote(opts)

      @before_compile TuistWeb.Noora.Page
    end
  end

  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :noora_page_opts)
    title = Keyword.fetch!(opts, :title)
    slug = Keyword.get_lazy(opts, :slug, fn -> slugify(title) end)

    quote do
      def title, do: unquote(title)
      def nav_title, do: unquote(Keyword.get(opts, :nav_title, title))
      def slug, do: unquote(slug)
      def description, do: unquote(Keyword.get(opts, :description))
      def components, do: unquote(Keyword.get(opts, :components, []))
      def guidelines, do: unquote(Keyword.get(opts, :guidelines, []))
      def examples, do: Enum.reverse(@noora_examples)
    end
  end

  @doc """
  Declares an example rendered live on the page, with its source shown as code.

  The block must be a single `~H` sigil. Options:

    * `:description` - one sentence shown under the example title.
    * `:layout` - how the preview arranges its children: `:row` (default)
      wraps them horizontally and centers them, `:column` stacks them at full
      width, `:start` wraps them from the start edge, `:rows` stacks them
      from the start edge and lays out each child's items as a row, `:stack`
      does the same centered, with 16px between rows and items, and `:list`
      stacks the children as one centered group, aligned to each other's
      start edge, with 16px between them.
    * `:toast` - renders the example as a toast: the preview shows a "Show
      toast" button that pops the rendered output into the bottom corner of
      the page, where it dismisses itself after a few seconds. Pass
      `:preserve` instead of `true` for a toast that stays until dismissed.
  """
  defmacro example(title, opts \\ [], do: block) do
    source = source!(block, __CALLER__)
    id = slugify(title)
    function = :"__noora_example_#{String.replace(id, "-", "_")}__"

    quote do
      @noora_examples %{
        id: unquote(id),
        title: unquote(title),
        description: unquote(Keyword.get(opts, :description)),
        layout: unquote(Keyword.get(opts, :layout, :row)),
        toast: unquote(Keyword.get(opts, :toast, false)),
        source: unquote(source),
        highlighted_source: TuistWeb.Noora.Code.highlight(unquote(source)),
        function: unquote(function)
      }

      @doc false
      def unquote(function)(var!(assigns)), do: unquote(block)
    end
  end

  def slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp source!({:sigil_H, _meta, [{:<<>>, _, [source]}, _modifiers]}, _env) when is_binary(source) do
    String.trim_trailing(source)
  end

  defp source!(_block, env) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description: "a Noora example must contain a single ~H sigil without interpolation"
  end
end
