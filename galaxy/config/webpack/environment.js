const { environment } = require('@rails/webpacker')
const typescript =  require('./loaders/typescript')

const webpack = require('webpack')

environment.plugins.append(
  'Provide',
  new webpack.ProvidePlugin({
    $: 'jquery',
    jQuery: 'jquery',
    Popper: ['popper.js', 'default'],
  })
)

environment.loaders.prepend('typescript', typescript)
module.exports = environment
