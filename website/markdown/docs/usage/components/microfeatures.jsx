/** @jsx jsx */
import { jsx, Styled, useThemeUI, useColorMode } from 'theme-ui'
import { useResponsiveValue } from '@theme-ui/match-media'
import { Graphviz } from 'graphviz-react'

const useTextColor = () => {
  const { theme } = useThemeUI()
  const [colorMode, _] = useColorMode()
  return theme.colors.text
}

const useBackgroundColor = () => {
  const { theme } = useThemeUI()
  const [colorMode, _] = useColorMode()
  return theme.colors.background
}

const CrossPlatform = () => {
  const textColor = useTextColor()
  const backgroundColor = useBackgroundColor()
  const width = useResponsiveValue(['100%', '600'])

  return (
    <Graphviz
      options={{ width: width }}
      dot={`digraph {
        graph [bgcolor="${backgroundColor}"];
        µSearchiOS [color="${textColor}", fontcolor="${textColor}"];
        µSearchmacOS [color="${textColor}", fontcolor="${textColor}"];
        µSearchwatchOS [color="${textColor}", fontcolor="${textColor}"];
        µSearch [color="${textColor}", fontcolor="${textColor}"];
        µSearchiOS -> µSearch [color="${textColor}"];
        µSearchmacOS -> µSearch [color="${textColor}"];
        µSearchwatchOS -> µSearch [color="${textColor}"];
      }`}
    />
  )
}

const MicroFeature = () => {
  const textColor = useTextColor()
  const backgroundColor = useBackgroundColor()
  const width = useResponsiveValue(['100%', '300'])

  return (
    <div sx={{ py: 2 }}>
      <Graphviz
        options={{ width: width }}
        dot={`digraph {
        graph [bgcolor="${backgroundColor}"];
        Example [color="${textColor}", fontcolor="${textColor}"];
        Source [color="${textColor}", fontcolor="${textColor}"];
        Testing [color="${textColor}", fontcolor="${textColor}"];
        Tests [color="${textColor}", fontcolor="${textColor}"];

        Example -> Source [color="${textColor}"];
        Example -> Testing [color="${textColor}"];
        Tests -> Source [color="${textColor}"];
        Tests -> Testing [color="${textColor}"];
        Testing -> Source [color="${textColor}"];
      }`}
      />
    </div>
  )
}

const Layers = () => {
  const textColor = useTextColor()
  const backgroundColor = useBackgroundColor()
  const width = useResponsiveValue(['100%', '400'])

  return (
    <div sx={{ py: 3 }}>
      <Graphviz
        options={{ width: width }}
        dot={`digraph {
            graph [bgcolor="${backgroundColor}"];

            Application [color="${textColor}", fontcolor="${textColor}"];
            µSearch [color="${textColor}", fontcolor="${textColor}"];
            µHome [color="${textColor}", fontcolor="${textColor}"];
            µProfile [color="${textColor}", fontcolor="${textColor}"];
            µFeatures [color="${textColor}", fontcolor="${textColor}"];
            µCore [color="${textColor}", fontcolor="${textColor}"];
            µUI [color="${textColor}", fontcolor="${textColor}"];
            µTesting [color="${textColor}", fontcolor="${textColor}"];

            Application -> µSearch [color="${textColor}"];
            Application -> µHome [color="${textColor}"];
            Application -> µProfile [color="${textColor}"];
            µSearch -> µFeatures [color="${textColor}"];
            µHome -> µFeatures [color="${textColor}"];
            µProfile -> µFeatures [color="${textColor}"];
            µFeatures -> µCore [color="${textColor}"];
            µFeatures -> µUI [color="${textColor}"];
            µFeatures -> µTesting [color="${textColor}"];
            }`}
      />
    </div>
  )
}

export { CrossPlatform, MicroFeature, Layers }
