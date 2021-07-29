/* eslint no-console:0 */
import Bugsnag from '@bugsnag/js';
import BugsnagPluginReact from '@bugsnag/plugin-react';
import RailsUJS from '@rails/ujs';
import ReactRailsUJS from 'react_ujs';

// Styles
import '@shopify/polaris/dist/styles.css';

RailsUJS.start();

// Bugsnag
if (ENVIRONMENT !== 'development') {
  Bugsnag.start({
    apiKey: BUGSNAG_FRONTEND_API_KEY,
    plugins: [new BugsnagPluginReact()],
  });
}

// Images
require.context('../images', true);

// React
const componentRequireContext = require.context('components', true);

ReactRailsUJS.useContext(componentRequireContext);
