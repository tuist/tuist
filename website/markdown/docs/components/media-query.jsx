import React from "react"
import { createMedia } from "@artsy/fresnel"

const { MediaContextProvider, Media  } = createMedia({
  breakpoints: {
    sm: 0,
    md: 768,
    lg: 1024,
    xl: 1192,
  },
})

export { MediaContextProvider, Media }
