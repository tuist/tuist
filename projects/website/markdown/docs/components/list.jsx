/** @jsx jsx */
import { jsx } from 'theme-ui'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faFolder, faFileCode } from '@fortawesome/free-regular-svg-icons'
import { faSwift } from '@fortawesome/free-brands-svg-icons'

const List = ({ children }) => {
  return (
    <div sx={{ display: 'flex', flexDirection: 'column', p: 3 }}>
      {children}
    </div>
  )
}

const ListItem = ({ children }) => {
  return (
    <div sx={{ display: 'flex', flexDirection: 'row', pt: 2 }}>{children}</div>
  )
}

const ListIcon = ({ name }) => {
  let icon
  if (name == 'code') {
    icon = faFileCode
  } else if (name == 'swift') {
    icon = faSwift
  } else if (name == 'folder') {
    icon = faFolder
  }
  return (
    <div>
      <FontAwesomeIcon
        sx={{ pr: 3 }}
        icon={icon}
        size="sm"
        sx={{ height: 30, width: 30 }}
      />
    </div>
  )
}

const ListContent = ({ children }) => {
  return (
    <div sx={{ flex: 1, display: 'flex', flexDirection: 'column', ml: 2 }}>
      {children}
    </div>
  )
}

const ListHeader = ({ children }) => {
  return <div sx={{ mb: 0, color: 'text' }}>{children}</div>
}

const ListDescription = ({ children }) => {
  return <div sx={{ fontSize: 1, color: 'gray' }}>{children}</div>
}

const ListList = ({ children }) => {
  return <div sx={{ flex: 1 }}>{children}</div>
}

export {
  List,
  ListItem,
  ListIcon,
  ListContent,
  ListHeader,
  ListDescription,
  ListList,
}
