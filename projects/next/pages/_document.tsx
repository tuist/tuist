import Document, { Main, NextScript } from 'next/document'
import { InitializeColorMode } from 'theme-ui'

export default class extends Document {
  static async getInitialProps(ctx) {
    const initialProps = await Document.getInitialProps(ctx)
    return { ...initialProps }
  }

  render() {
    // Replace html lang attribute value with your language.
    return (
      <html lang="en">
        <body>
          <InitializeColorMode />
          <Main />
          <NextScript />
        </body>
      </html>
    )
  }
}
