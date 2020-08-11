import Head from 'next/head'
import logo from '../../website/static/logo.svg'

function HomePage() {
  const description =
    'Insights about how people use Tuist to help make informed decision and prioritize future work on Tuist.'
  const title = `Tuist Statistics`

  return (
    <div>
      <Head>
        <title>{title}</title>
        <meta name="viewport" content="initial-scale=1.0, width=device-width" />
        <meta name="description" content={description} data-rh="true" />
        <meta property="og:title" content={title} key="title" />
        <meta property="og:description" content={description} data-rh="true" />
        <meta data-rh="true" name="twitter:creator" content="@tuistio" />
        <meta data-rh="true" name="twitter:card" content="summary" />
        <meta data-rh="true" name="twitter:site" content="@tuistio" />
        <link
          rel="apple-touch-icon"
          sizes="57x57"
          href="/apple-icon-57x57.png"
        />
        <link
          rel="apple-touch-icon"
          sizes="60x60"
          href="/apple-icon-60x60.png"
        />
        <link
          rel="apple-touch-icon"
          sizes="72x72"
          href="/apple-icon-72x72.png"
        />
        <link
          rel="apple-touch-icon"
          sizes="76x76"
          href="/apple-icon-76x76.png"
        />
        <link
          rel="apple-touch-icon"
          sizes="114x114"
          href="/apple-icon-114x114.png"
        />
        <link
          rel="apple-touch-icon"
          sizes="120x120"
          href="/apple-icon-120x120.png"
        />
        <link
          rel="apple-touch-icon"
          sizes="144x144"
          href="/apple-icon-144x144.png"
        />
        <link
          rel="apple-touch-icon"
          sizes="152x152"
          href="/apple-icon-152x152.png"
        />
        <link
          rel="apple-touch-icon"
          sizes="180x180"
          href="/apple-icon-180x180.png"
        />
        <link
          rel="icon"
          type="image/png"
          sizes="192x192"
          href="/android-icon-192x192.png"
        />
        <link
          rel="icon"
          type="image/png"
          sizes="32x32"
          href="/favicon-32x32.png"
        />
        <link
          rel="icon"
          type="image/png"
          sizes="96x96"
          href="/favicon-96x96.png"
        />
        <link
          rel="icon"
          type="image/png"
          sizes="16x16"
          href="/favicon-16x16.png"
        />
        <link rel="manifest" href="/manifest.json" />
        <meta name="msapplication-TileColor" content="#ffffff" />
        <meta name="msapplication-TileImage" content="/ms-icon-144x144.png" />
        <meta name="theme-color" content="#ffffff" />
      </Head>

      <div className="relative py-16 bg-white overflow-hidden max-w-screen-lg mx-auto">
        <div className="relative px-4 sm:px-6 lg:px-8">
          <div className="text-lg max-w-prose mx-auto mb-6">
            <div className="flex justify-center mb-16">
              <a href="https://tuist.io">
                <img src={logo} />
              </a>
            </div>
            <p className="text-base text-center leading-6 text-indigo-600 font-semibold tracking-wide uppercase">
              Tuist Stats
            </p>
            <h1 className="mt-2 mb-8 text-3xl text-center leading-8 font-extrabold tracking-tight text-gray-900 sm:text-4xl sm:leading-10">
              Insights about how people use Tuist
            </h1>
            <p className="text-center text-gray-700 leading-8 prose-lg">
              To prioritize the work and make the right decisions, it's
              important to <b>back our decisions with data</b>. For that reason,
              we collect anonymous data and present it on this website for us
              and for the users of the tool.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}

export default HomePage
