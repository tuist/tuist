import ReactRailsUJS from 'react_ujs';

const componentRequireContext = require.context('components', true);

ReactRailsUJS.useContext(componentRequireContext);
