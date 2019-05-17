import React from 'react'
import { Label, Table } from 'semantic-ui-react'

const EnumTable = ({ cases }) => {
  return (
    <Table celled>
      <Table.Header>
        <Table.Row>
          <Table.HeaderCell>Case</Table.HeaderCell>
          <Table.HeaderCell>Description</Table.HeaderCell>
        </Table.Row>
      </Table.Header>

      <Table.Body>
        {cases.map((prop, index) => {
          return (
            <Table.Row warning={prop.deprecated} key={index}>
              <Table.Cell singleLine>
                {prop.deprecated && <Label ribbon>Deprecated</Label>}
                {prop.case}
              </Table.Cell>
              <Table.Cell>{prop.description}</Table.Cell>
            </Table.Row>
          )
        })}
      </Table.Body>
    </Table>
  )
}

export default EnumTable
