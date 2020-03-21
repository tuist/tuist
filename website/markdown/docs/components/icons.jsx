/** @jsx jsx */
import { jsx, MenuButton } from 'theme-ui'

import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faCloud, faUsers, faFileCode, faLayerGroup } from '@fortawesome/free-solid-svg-icons'

const Cloud = () => {
    return <FontAwesomeIcon
        sx={{}}
        icon={faCloud}
        size="lg"
    />
}
const Users = () => {
    return <FontAwesomeIcon
        sx={{}}
        icon={faUsers}
        size="lg"
    />
}
const Contributors = () => {
    return <FontAwesomeIcon
        sx={{}}
        icon={faFileCode}
        size="lg"
    />
}
const Architectures = () => {
    return <FontAwesomeIcon
        sx={{}}
        icon={faLayerGroup}
        size="lg"
    />
}
export { Cloud, Users, Contributors, Architectures }