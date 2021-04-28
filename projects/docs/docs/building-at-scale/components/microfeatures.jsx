import React from 'react'
import { Graphviz } from 'graphviz-react'

const MicroFeature = () => {
  return (
    <div>
      <Graphviz
        dot={`digraph {
        FeatureExample;
        FeatureInterface;
        Feature;
        FeatureTesting;
        FeatureTests;
        FeatureExample -> Feature;
        FeatureExample -> FeatureTesting;
        FeatureTests -> Feature;
        FeatureTests -> FeatureTesting;
        FeatureTesting -> FeatureInterface;
        Feature -> FeatureInterface;
      }`}
      />
    </div>
  )
}

const Layers = () => {
  return (
    <div>
      <Graphviz
        dot={`digraph {
            Application;
            µSearch;
            µHome;
            µProfile;
            µFeatures;
            µCore;
            µUI;
            µTesting;
            Application -> µSearch;
            Application -> µHome;
            Application -> µProfile;
            µSearch -> µFeatures;
            µHome -> µFeatures;
            µProfile -> µFeatures;
            µFeatures -> µCore;
            µFeatures -> µUI;
            µFeatures -> µTesting;
            }`}
      />
    </div>
  )
}

export { MicroFeature, Layers }
