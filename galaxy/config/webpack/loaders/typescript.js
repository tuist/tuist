const path = require('path')
// const PnpWebpackPlugin = require('pnp-webpack-plugin')

const configFile = path.join(__dirname, '../../../tsconfig.json')
module.exports = {
  test: /\.(ts|tsx)?(\.erb)?$/,
  use: [
    {
      loader: 'ts-loader',
      options: {
        // ...PnpWebpackPlugin.tsLoaderOptions(),
        configFile,
      },
    },
  ],
}
