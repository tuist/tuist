/** @jsx jsx */
import { jsx, MenuButton } from 'theme-ui'

import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faUserAstronaut,
  faKey,
  faUsers,
  faFileCode,
  faLayerGroup,
  faTerminal,
  faCloud,
} from '@fortawesome/free-solid-svg-icons'

const Signing = () => {
  return (
    <FontAwesomeIcon sx={{ width: 20, height: 20 }} icon={faKey} size="sm" />
  )
}
const Astronaut = () => {
  return (
    <FontAwesomeIcon
      sx={{ width: 20, height: 20 }}
      icon={faUserAstronaut}
      size="sm"
    />
  )
}
const Terminal = () => {
  return (
    <FontAwesomeIcon
      sx={{ width: 20, height: 20 }}
      icon={faTerminal}
      size="sm"
    />
  )
}
const Users = () => {
  return (
    <FontAwesomeIcon sx={{ width: 20, height: 20 }} icon={faUsers} size="sm" />
  )
}
const Cloud = () => {
  return (
    <FontAwesomeIcon sx={{ width: 20, height: 20 }} icon={faCloud} size="sm" />
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
export {
  Signing,
  Astronaut,
  Users,
  Contributors,
  Architectures,
  Terminal,
  Cloud,
}
