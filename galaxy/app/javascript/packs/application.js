// Rails
// Stimulus
import { Application } from 'stimulus';
import { definitionsFromContext } from 'stimulus/webpack-helpers';

// Styles
import '../css/application.scss';

require('@rails/ujs').start();
require('turbolinks').start();
require('@rails/activestorage').start();
require('../channels');

const application = Application.start();
const context = require.context('../controllers', true, /\.js$/);
application.load(definitionsFromContext(context));
