const path = require('path')

const configFile = path.join(__dirname, '../../../tsconfig.json')
module.exports = {
  test: function(modulePath) {
    return (
      (modulePath.endsWith('.ts') || modulePath.endsWith('.tsx')) &&
      !(modulePath.endsWith('test.ts') || modulePath.endsWith('test.tsx'))
    )
  },
  use: [
    {
      loader: 'ts-loader',
      options: {
        configFile,
      },
    },
  ],
}
