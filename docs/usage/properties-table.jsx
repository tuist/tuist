import React from 'react'
import { Icon, Label, Menu, Table } from 'semantic-ui-react'

const PropertiesTable = ({ props }) => {
  return (
    <Table celled>
      <Table.Header>
        <Table.Row>
          <Table.HeaderCell>Property</Table.HeaderCell>
          <Table.HeaderCell>Description</Table.HeaderCell>
          <Table.HeaderCell>Type</Table.HeaderCell>
          <Table.HeaderCell>Optional</Table.HeaderCell>
          <Table.HeaderCell>Default</Table.HeaderCell>
        </Table.Row>
      </Table.Header>

      <Table.Body>
        {props.map(prop => {
          let type
          if (prop.typeLink) {
            type = <a href={prop.typeLink}>{prop.type}</a>
          } else {
            type = <span>{prop.type}</span>
          }

          return (
            <Table.Row>
              <Table.Cell>{prop.name}</Table.Cell>
              <Table.Cell>{prop.description}</Table.Cell>
              <Table.Cell>{type}</Table.Cell>
              <Table.Cell>{prop.optional ? 'Yes' : 'No'}</Table.Cell>
              <Table.Cell>{prop.default}</Table.Cell>
            </Table.Row>
          )
        })}
      </Table.Body>
    </Table>
  )
}

export default PropertiesTable
