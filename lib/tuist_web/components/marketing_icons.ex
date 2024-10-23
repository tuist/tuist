defmodule TuistWeb.MarketingIcons do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component

  @default_icon_size 24

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def close_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M18 6L6 18M6 6L18 18"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def menu_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M3 12H15M3 6H21M3 18H21"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def plus_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M12 5V19M5 12H19"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def check_circle_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M7.5 12L10.5 15L16.5 9M22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12Z"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_arrow_narrow_right(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 18 14"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M1 7H17M17 7L11 1M17 7L11 13"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_plus(assigns) do
    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M12 5V19M5 12H19"
        stroke="black"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_minus(assigns) do
    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M5 12H19"
        stroke="black"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_slack(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M4.00006 12C4.00006 12.5304 3.78935 13.0391 3.41427 13.4142C3.0392 13.7893 2.53049 14 2.00006 14C1.46963 14 0.96092 13.7893 0.585847 13.4142C0.210775 13.0391 6.10352e-05 12.5304 6.10352e-05 12C6.10352e-05 11.4696 0.210775 10.9609 0.585847 10.5858C0.96092 10.2107 1.46963 10 2.00006 10H4.00006V12ZM5.00006 12C5.00006 11.4696 5.21077 10.9609 5.58585 10.5858C5.96092 10.2107 6.46963 10 7.00006 10C7.53049 10 8.0392 10.2107 8.41427 10.5858C8.78935 10.9609 9.00006 11.4696 9.00006 12V17C9.00006 17.5304 8.78935 18.0391 8.41427 18.4142C8.0392 18.7893 7.53049 19 7.00006 19C6.46963 19 5.96092 18.7893 5.58585 18.4142C5.21077 18.0391 5.00006 17.5304 5.00006 17V12ZM7.00006 4C6.46963 4 5.96092 3.78929 5.58585 3.41421C5.21077 3.03914 5.00006 2.53043 5.00006 2C5.00006 1.46957 5.21077 0.960859 5.58585 0.585786C5.96092 0.210714 6.46963 0 7.00006 0C7.53049 0 8.0392 0.210714 8.41427 0.585786C8.78935 0.960859 9.00006 1.46957 9.00006 2V4H7.00006ZM7.00006 5C7.53049 5 8.0392 5.21071 8.41427 5.58579C8.78935 5.96086 9.00006 6.46957 9.00006 7C9.00006 7.53043 8.78935 8.03914 8.41427 8.41421C8.0392 8.78929 7.53049 9 7.00006 9H2.00006C1.46963 9 0.96092 8.78929 0.585847 8.41421C0.210775 8.03914 6.10352e-05 7.53043 6.10352e-05 7C6.10352e-05 6.46957 0.210775 5.96086 0.585847 5.58579C0.96092 5.21071 1.46963 5 2.00006 5H7.00006ZM15.0001 7C15.0001 6.46957 15.2108 5.96086 15.5858 5.58579C15.9609 5.21071 16.4696 5 17.0001 5C17.5305 5 18.0392 5.21071 18.4143 5.58579C18.7893 5.96086 19.0001 6.46957 19.0001 7C19.0001 7.53043 18.7893 8.03914 18.4143 8.41421C18.0392 8.78929 17.5305 9 17.0001 9H15.0001V7ZM14.0001 7C14.0001 7.53043 13.7893 8.03914 13.4143 8.41421C13.0392 8.78929 12.5305 9 12.0001 9C11.4696 9 10.9609 8.78929 10.5858 8.41421C10.2108 8.03914 10.0001 7.53043 10.0001 7V2C10.0001 1.46957 10.2108 0.960859 10.5858 0.585786C10.9609 0.210714 11.4696 0 12.0001 0C12.5305 0 13.0392 0.210714 13.4143 0.585786C13.7893 0.960859 14.0001 1.46957 14.0001 2V7ZM12.0001 15C12.5305 15 13.0392 15.2107 13.4143 15.5858C13.7893 15.9609 14.0001 16.4696 14.0001 17C14.0001 17.5304 13.7893 18.0391 13.4143 18.4142C13.0392 18.7893 12.5305 19 12.0001 19C11.4696 19 10.9609 18.7893 10.5858 18.4142C10.2108 18.0391 10.0001 17.5304 10.0001 17V15H12.0001ZM12.0001 14C11.4696 14 10.9609 13.7893 10.5858 13.4142C10.2108 13.0391 10.0001 12.5304 10.0001 12C10.0001 11.4696 10.2108 10.9609 10.5858 10.5858C10.9609 10.2107 11.4696 10 12.0001 10H17.0001C17.5305 10 18.0392 10.2107 18.4143 10.5858C18.7893 10.9609 19.0001 11.4696 19.0001 12C19.0001 12.5304 18.7893 13.0391 18.4143 13.4142C18.0392 13.7893 17.5305 14 17.0001 14H12.0001Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_x(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M12.1857 7.6797L18.7429 0H15.8162L10.8114 5.8653L6.37143 0H0L7.43429 9.819L0.447619 18H3.37524L8.80857 11.637L13.6286 18H20L12.1857 7.6797ZM9.91905 10.3347L8.54286 8.5176L3.2 1.4643H5.4L9.71238 7.1496L11.0867 8.9676L16.8181 16.5357H14.6181L9.91905 10.3347Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_github(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M10 0C8.68678 0 7.38642 0.258658 6.17317 0.761205C4.95991 1.26375 3.85752 2.00035 2.92893 2.92893C1.05357 4.8043 0 7.34784 0 10C0 14.42 2.87 18.17 6.84 19.5C7.34 19.58 7.5 19.27 7.5 19V17.31C4.73 17.91 4.14 15.97 4.14 15.97C3.68 14.81 3.03 14.5 3.03 14.5C2.12 13.88 3.1 13.9 3.1 13.9C4.1 13.97 4.63 14.93 4.63 14.93C5.5 16.45 6.97 16 7.54 15.76C7.63 15.11 7.89 14.67 8.17 14.42C5.95 14.17 3.62 13.31 3.62 9.5C3.62 8.39 4 7.5 4.65 6.79C4.55 6.54 4.2 5.5 4.75 4.15C4.75 4.15 5.59 3.88 7.5 5.17C8.29 4.95 9.15 4.84 10 4.84C10.85 4.84 11.71 4.95 12.5 5.17C14.41 3.88 15.25 4.15 15.25 4.15C15.8 5.5 15.45 6.54 15.35 6.79C16 7.5 16.38 8.39 16.38 9.5C16.38 13.32 14.04 14.16 11.81 14.41C12.17 14.72 12.5 15.33 12.5 16.26V19C12.5 19.27 12.66 19.59 13.17 19.5C17.14 18.16 20 14.42 20 10C20 8.68678 19.7413 7.38642 19.2388 6.17317C18.7362 4.95991 17.9997 3.85752 17.0711 2.92893C16.1425 2.00035 15.0401 1.26375 13.8268 0.761205C12.6136 0.258658 11.3132 0 10 0Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_mastodon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M20.94 14C20.66 15.41 18.5 16.96 15.97 17.26C14.66 17.41 13.37 17.56 12 17.5C9.74998 17.39 7.99998 16.96 7.99998 16.96V17.58C8.31998 19.8 10.22 19.93 12.03 20C13.85 20.05 15.47 19.54 15.47 19.54L15.55 21.19C15.55 21.19 14.27 21.87 12 22C10.75 22.07 9.18998 21.97 7.37998 21.5C3.45998 20.45 2.77998 16.26 2.67998 12L2.66998 8.57C2.66998 4.23 5.49998 2.96 5.49998 2.96C6.94998 2.3 9.40998 2 11.97 2H12.03C14.59 2 17.05 2.3 18.5 2.96C18.5 2.96 21.33 4.23 21.33 8.57C21.33 8.57 21.37 11.78 20.94 14ZM18 8.91C18 7.83 17.7 7 17.15 6.35C16.59 5.72 15.85 5.39 14.92 5.39C13.86 5.39 13.05 5.8 12.5 6.62L12 7.5L11.5 6.62C10.94 5.8 10.14 5.39 9.06998 5.39C8.14998 5.39 7.40998 5.72 6.83998 6.35C6.28998 7 5.99998 7.83 5.99998 8.91V14.17H8.09998V9.06C8.09998 8 8.54998 7.44 9.45998 7.44C10.46 7.44 10.96 8.09 10.96 9.37V12.16H13.03V9.37C13.03 8.09 13.53 7.44 14.54 7.44C15.44 7.44 15.89 8 15.89 9.06V14.17H18V8.91Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_peertube(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      width={@size}
      height={@size}
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path fill="currentColor" d="m3 0v12l9-6zm0 12v12l9-6zm9-6v12l9-6z" />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_linkedin(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M20.47 1.9999H3.53C3.33958 1.99725 3.1505 2.03214 2.97356 2.10258C2.79663 2.17302 2.6353 2.27762 2.4988 2.41041C2.36229 2.5432 2.25328 2.70158 2.17799 2.87651C2.1027 3.05143 2.06261 3.23947 2.06 3.4299V20.5699C2.06261 20.7603 2.1027 20.9484 2.17799 21.1233C2.25328 21.2982 2.36229 21.4566 2.4988 21.5894C2.6353 21.7222 2.79663 21.8268 2.97356 21.8972C3.1505 21.9676 3.33958 22.0025 3.53 21.9999H20.47C20.6604 22.0025 20.8495 21.9676 21.0264 21.8972C21.2034 21.8268 21.3647 21.7222 21.5012 21.5894C21.6377 21.4566 21.7467 21.2982 21.822 21.1233C21.8973 20.9484 21.9374 20.7603 21.94 20.5699V3.4299C21.9374 3.23947 21.8973 3.05143 21.822 2.87651C21.7467 2.70158 21.6377 2.5432 21.5012 2.41041C21.3647 2.27762 21.2034 2.17302 21.0264 2.10258C20.8495 2.03214 20.6604 1.99725 20.47 1.9999ZM8.09 18.7399H5.09V9.7399H8.09V18.7399ZM6.59 8.4799C6.17626 8.4799 5.77947 8.31554 5.48691 8.02298C5.19435 7.73043 5.03 7.33363 5.03 6.9199C5.03 6.50616 5.19435 6.10937 5.48691 5.81681C5.77947 5.52425 6.17626 5.3599 6.59 5.3599C6.80969 5.33498 7.03217 5.35675 7.24287 5.42378C7.45357 5.49081 7.64774 5.60159 7.81265 5.74886C7.97757 5.89613 8.10952 6.07657 8.19987 6.27838C8.29021 6.48018 8.33692 6.69879 8.33692 6.9199C8.33692 7.141 8.29021 7.35961 8.19987 7.56141C8.10952 7.76322 7.97757 7.94366 7.81265 8.09093C7.64774 8.23821 7.45357 8.34898 7.24287 8.41601C7.03217 8.48304 6.80969 8.50481 6.59 8.4799ZM18.91 18.7399H15.91V13.9099C15.91 12.6999 15.48 11.9099 14.39 11.9099C14.0527 11.9124 13.7242 12.0182 13.4488 12.2131C13.1735 12.408 12.9645 12.6826 12.85 12.9999C12.7717 13.2349 12.7378 13.4825 12.75 13.7299V18.7299H9.75C9.75 18.7299 9.75 10.5499 9.75 9.7299H12.75V10.9999C13.0225 10.527 13.4189 10.1374 13.8964 9.8731C14.374 9.60878 14.9146 9.47975 15.46 9.4999C17.46 9.4999 18.91 10.7899 18.91 13.5599V18.7399Z"
        fill="currentColor"
      />
    </svg>
    """
  end
end
