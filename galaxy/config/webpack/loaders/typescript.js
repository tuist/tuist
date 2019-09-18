const path = require('path')

const configFile = path.join(__dirname, '../../../tsconfig.json')
module.exports = {
  test: /\.tsx?$/,
  use: [
    {
      loader: 'ts-loader',
      options: {
        configFile,
      },
    },
  ],
}
