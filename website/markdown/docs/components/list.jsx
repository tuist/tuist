/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faFolder } from '@fortawesome/free-regular-svg-icons'
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

const ListIcon = ({ children, name }) => {
  let icon
  if (name == 'swift') {
    icon = faSwift
  } else if (name == 'folder') {
    icon = faFolder
  }
  return (
    <div>
      <FontAwesomeIcon sx={{ pr: 3 }} icon={icon} size="s" />
    </div>
  )
}

const ListContent = ({ children }) => {
  return (
    <div sx={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
      {children}
    </div>
  )
}

const ListHeader = ({ children, folder }) => {
  return (
    <div sx={{ mb: 0, color: folder ? 'primary' : 'inherited' }}>
      {children}
    </div>
  )
}

const ListDescription = ({ children }) => {
  return <div sx={{ fontSize: 1, color: 'gray3' }}>{children}</div>
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
