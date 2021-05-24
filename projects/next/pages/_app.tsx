// import App from "next/app";
import type { AppProps } from 'next/app'
import { ThemeProvider } from 'theme-ui'
import theme from '../theme'
import '../styles/global.css'

function App({ Component, pageProps }: AppProps) {
  return (
    // @ts-ignore
    <ThemeProvider theme={theme}>
      <Component {...pageProps} />
    </ThemeProvider>
  )
}

export default App
