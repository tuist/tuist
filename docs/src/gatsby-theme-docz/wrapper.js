import * as React from 'react'
import { Helmet } from 'react-helmet'

const Wrapper = ({ children }) => <React.Fragment>
    <Helmet>
        <meta charSet="utf-8" />
        <link rel="stylesheet" href="//cdn.jsdelivr.net/npm/semantic-ui@2.4.2/dist/semantic.min.css" />
    </Helmet>
    {children}
</React.Fragment>
export default Wrapper