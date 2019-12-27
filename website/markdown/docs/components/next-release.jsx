/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import React from 'react'
import moment from 'moment'

const NextRelease = () => {
  const week = moment().week()
  let releaseDate
  if (week % 2 == 0) {
    releaseDate = moment()
      .endOf('week')
      .day(5)
  } else {
    releaseDate = moment()
      .endOf('week')
      .day(-2)
  }
  return (
    <Styled.p>
      The next version of might get released on September{' '}
      <Styled.b>{releaseDate.format('dddd, MMMM Do')}</Styled.b>
    </Styled.p>
  )
}

export default NextRelease
