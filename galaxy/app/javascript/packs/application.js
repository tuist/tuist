// Rails
require('@rails/ujs').start()
require('turbolinks').start()
require('@rails/activestorage').start()
require('channels')

// Stimulus
import { Application } from 'stimulus'
import { definitionsFromContext } from 'stimulus/webpack-helpers'
const application = Application.start()
const context = require.context('../controllers', true, /\.js$/)
application.load(definitionsFromContext(context))

// Styles
import '../css/application.scss'
