/* eslint-disable */
import 'stylesheets/server-side';

const images = require.context('../images', true);
const imagePath = (name) => images(name, true);

// Rails
require('@rails/ujs').start();
