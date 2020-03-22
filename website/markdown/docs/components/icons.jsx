/** @jsx jsx */
import { jsx, MenuButton } from 'theme-ui'

import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faCloud,
  faUsers,
  faFileCode,
  faLayerGroup,
} from '@fortawesome/free-solid-svg-icons'

const Cloud = () => {
  return (
    <FontAwesomeIcon sx={{ width: 20, height: 20 }} icon={faCloud} size="sm" />
  )
}
const Users = () => {
  return (
    <FontAwesomeIcon sx={{ width: 20, height: 20 }} icon={faUsers} size="sm" />
  )
}
const Contributors = () => {
  return (
    <FontAwesomeIcon
      sx={{ width: 20, height: 20 }}
      icon={faFileCode}
      size="sm"
    />
  )
}
const Architectures = () => {
  return (
    <FontAwesomeIcon
      sx={{ width: 20, height: 20 }}
      icon={faLayerGroup}
      size="sm"
    />
  )
}
export { Cloud, Users, Contributors, Architectures }
