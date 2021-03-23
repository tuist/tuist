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

const MicroFeature = () => {
  const textColor = useTextColor()
  const backgroundColor = useBackgroundColor()
  const width = useResponsiveValue(['100%', '400'])

  return (
    <div sx={{ py: 0 }}>
      <Graphviz
        options={{ width: width }}
        dot={`digraph {
        graph [bgcolor="${backgroundColor}"];
        FeatureExample [color="${textColor}", fontcolor="${textColor}"];
        FeatureInterface [color="${textColor}", fontcolor="${textColor}"];
        Feature [color="${textColor}", fontcolor="${textColor}"];
        FeatureTesting [color="${textColor}", fontcolor="${textColor}"];
        FeatureTests [color="${textColor}", fontcolor="${textColor}"];

        FeatureExample -> Feature [color="${textColor}"];
        FeatureExample -> FeatureTesting [color="${textColor}"];
        FeatureTests -> Feature [color="${textColor}"];
        FeatureTests -> FeatureTesting [color="${textColor}"];
        FeatureTesting -> FeatureInterface [color="${textColor}"];
        Feature -> FeatureInterface [color="${textColor}"];
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

export { MicroFeature, Layers }
