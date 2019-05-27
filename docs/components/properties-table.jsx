import React from 'react'
import { Responsive, Label, Table } from 'semantic-ui-react'
import styled from 'styled-components'
import StyledCode from "./styled-code"

const PropertiesTable = ({ props }) => {
  return (
    <Table celled>
      <Responsive as={Table.Header} {...Responsive.onlyComputer}>
        <Table.Row>
          <Table.HeaderCell>Property</Table.HeaderCell>
          <Table.HeaderCell>Description</Table.HeaderCell>
          <Table.HeaderCell>Type</Table.HeaderCell>
          <Table.HeaderCell>Optional</Table.HeaderCell>
          <Table.HeaderCell>Default</Table.HeaderCell>
        </Table.Row>
      </Responsive>

      <Table.Body>
        {props.map((prop, index) => {
          let type
          if (prop.typeLink) {
            type = <a href={prop.typeLink}>{prop.type}</a>
          } else {
            type = <span>{prop.type}</span>
          }

          const optionalValue = prop.optional ? 'Yes' : 'No'

          return (
            <Table.Row warning={prop.deprecated} key={index}>
              <Table.Cell>
                {prop.deprecated && <Label ribbon>Deprecated</Label>}
                {prop.name}
              </Table.Cell>
              <Table.Cell>{prop.description}</Table.Cell>
              <Table.Cell>
                <Responsive as="b" {...Responsive.onlyMobile}>
                  Type:{' '}
                </Responsive>
                <StyledCode>{type}</StyledCode>
              </Table.Cell>
              <Table.Cell>
                <Responsive as="b" {...Responsive.onlyMobile}>
                  Optional:{' '}
                </Responsive>
                {optionalValue}
              </Table.Cell>
              <Table.Cell>
                <Responsive as="b" {...Responsive.onlyMobile}>
                  Default:{' '}
                </Responsive>
                <StyledCode>{prop.default}</StyledCode>
              </Table.Cell>
            </Table.Row>
          )
        })}
      </Table.Body>
    </Table>
  )
}

export default PropertiesTable
