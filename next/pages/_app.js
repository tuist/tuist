import '../styles/globals.css';
import { GlobalStyles } from 'twin.macro';

function App({ Component, pageProps }) {
    return (
        <div>
            <GlobalStyles />
            <Component {...pageProps} />
        </div>
    );
}

export default App;
