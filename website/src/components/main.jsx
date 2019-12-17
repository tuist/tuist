/** @jsx jsx */
import { jsx } from 'theme-ui'

const Main = ({ children, py }) => {
  if (!py) {
    py = 4
  }
  return (
    <div
      sx={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
      }}
    >
      <div
        sx={{
          mt: 3,
          px: [2, 5],
          py: py,
          borderTopLeftRadius: 2,
          borderTopRightRadius: 2,
          width: theme => ['90%', '90%', '80%', '80%', theme.breakpoints.md],
        }}
      >
        {children}
      </div>
    </div>
  )
}

export default Main
