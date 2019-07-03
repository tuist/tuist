const PnpWebpackPlugin = require('pnp-webpack-plugin')

module.exports = {
  test: /\.(ts|tsx)?(\.erb)?$/,
  use: [
    {
      loader: 'ts-loader',
      options: PnpWebpackPlugin.tsLoaderOptions()
    }
  ]
}
