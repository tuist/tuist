defmodule TuistWeb.Marketing.Components.Posts.Rust.XPost do
  @moduledoc """
  Renders a static card for one of Discord's posts on X about its Rust client,
  quoting the post it shared and linking to the original. The marketing
  content security policy does not load X's embed script, so the card shows
  the post's text and its video poster, and the video plays on X.
  """
  use TuistWeb, :live_component

  @posts %{
    "desktop" => %{
      url: "https://x.com/discord/status/2118401057571369252",
      date: "Nov 5, 2026",
      text:
        "On the left is the Discord you use daily. And on the right is a new version we're working on, rebuilt in Rust",
      quote_name: "Stanislav",
      quote_handle: "svishnevskiy",
      quote_text:
        "The new Discord client using less RAM is just part of the story. Clicking around feels instant, I can't go back. Check out the boot time.",
      poster: "/marketing/images/blog/2026/11/13/rust/discord-desktop.webp",
      poster_alt:
        "Two laptops side by side, the current Discord desktop client on the left and the Rust client on the right"
    },
    "ios" => %{
      url: "https://x.com/discord/status/2120268703799574698",
      date: "Nov 10, 2026",
      text: "The new Rust client will feature the long-awaited mobile account switcher",
      quote_name: "Stanislav",
      quote_handle: "svishnevskiy",
      quote_text:
        "Fast launch times are cool, but actual usage is what matters. Check out the speed of the long-requested mobile account switcher on iOS on the new Rust client. And yes it is just as fast on Android and Desktop.",
      poster: "/marketing/images/blog/2026/11/13/rust/discord-ios.webp",
      poster_alt: "An iPhone running the new Rust-based Discord client, showing the messages list"
    }
  }

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:data, Map.fetch!(@posts, assigns.post))}
  end

  def render(assigns) do
    ~H"""
    <figure data-part="x-post" data-variant="x">
      <style :type={TuistWeb.ColocatedCSS}>
        #marketing-blog-post figure[data-part="x-post"][data-variant="x"] {
          margin: var(--noora-spacing-7) auto;
          max-width: 560px;
          border-radius: 16px;
          border: 1px solid light-dark(#cfd9de, #2f3336);
          background: light-dark(#ffffff, #000000);
          color: light-dark(#0f1419, #e7e9ea);
          padding: 12px 16px 14px;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          font-size: 15px;
          line-height: 20px;

          & a[href] {
            color: inherit;
            text-decoration: none;
          }

          & [data-part="header"] {
            display: flex;
            align-items: center;
            gap: 10px;
          }

          & img[data-part="avatar"] {
            width: 40px;
            max-width: 40px;
            height: 40px;
            border-radius: 50%;
            margin: 0;
            box-shadow: none;
          }

          & [data-part="names"] {
            display: flex;
            flex-direction: column;
            flex: 1;
            min-width: 0;
          }

          & [data-part="name"] {
            font-weight: 700;
          }

          & [data-part="handle"],
          & [data-part="meta"] {
            color: light-dark(#536471, #71767b);
          }

          & [data-part="logo"] {
            width: 20px;
            height: 20px;
            fill: currentColor;
          }

          & [data-part="text"] {
            margin: 10px 0 12px;
            padding: 0;
          }

          & [data-part="quote"] {
            display: block;
            border: 1px solid light-dark(#cfd9de, #2f3336);
            border-radius: 16px;
            overflow: hidden;
          }

          & [data-part="quote-body"] {
            padding: 10px 12px;
          }

          & [data-part="quote-header"] {
            display: flex;
            gap: 4px;
            font-size: 14px;
          }

          & [data-part="quote-text"] {
            margin: 4px 0 0;
            padding: 0;
            font-size: 14px;
          }

          & [data-part="poster"] {
            position: relative;
            display: block;
          }

          & [data-part="poster"] img[src] {
            display: block;
            width: 100%;
            max-width: 100%;
            height: auto;
            margin: 0;
            border-radius: 0;
            box-shadow: none;
          }

          & [data-part="play"] {
            position: absolute;
            inset: 0;
            margin: auto;
            width: 56px;
            height: 56px;
            border-radius: 50%;
            background: rgba(29, 155, 240, 0.92);
            border: 4px solid #ffffff;
            display: grid;
            place-items: center;
          }

          & [data-part="play"] svg {
            width: 22px;
            height: 22px;
            fill: #ffffff;
            margin-left: 3px;
          }

          & [data-part="meta"] {
            margin-top: 12px;
            font-size: 14px;
          }

          & [data-part="meta"] a[href]:hover {
            text-decoration: underline;
          }
        }
      </style>
      <div data-part="header">
        <img
          data-part="avatar"
          src="/marketing/images/blog/2026/11/13/rust/discord-avatar.webp"
          alt="Discord"
          width="40"
          height="40"
        />
        <div data-part="names">
          <a data-part="name" href="https://x.com/discord" target="_blank" rel="noopener">Discord</a>
          <span data-part="handle">@discord</span>
        </div>
        <a href={@data.url} target="_blank" rel="noopener" aria-label="View on X">
          <svg data-part="logo" viewBox="0 0 24 24" aria-hidden="true">
            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
          </svg>
        </a>
      </div>
      <p data-part="text">{@data.text}</p>
      <a data-part="quote" href={@data.url} target="_blank" rel="noopener">
        <div data-part="quote-body">
          <div data-part="quote-header">
            <strong>{@data.quote_name}</strong>
            <span data-part="handle">@{@data.quote_handle}</span>
          </div>
          <p data-part="quote-text">{@data.quote_text}</p>
        </div>
        <span data-part="poster">
          <img src={@data.poster} alt={@data.poster_alt} loading="lazy" />
          <span data-part="play">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
          </span>
        </span>
      </a>
      <div data-part="meta">
        <a href={@data.url} target="_blank" rel="noopener">{@data.date} · Watch the video on X</a>
      </div>
    </figure>
    """
  end
end
