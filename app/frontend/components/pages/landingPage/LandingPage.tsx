import React, { ReactNode } from 'react';
import '@shopify/polaris/build/esm/styles.css';
import '@shopify/polaris-viz/build/esm/styles.css';
import { Frame, Text } from '@shopify/polaris';
import TuistCloudAppProvider from '../../TuistCloudAppProvider';
import { BrowserRouter } from 'react-router-dom';
import {
  BuildTimesChart,
  CommandEventItemShowcase,
  Footer,
  HighlightText,
  TopBar,
} from './components';
import styles from './LandingPage.module.scss';

export const LandingPage = () => {
  return (
    <TuistCloudAppProvider>
      <BrowserRouter>
        <Frame>
          <TopBar />
          <div className={styles.LoadingPageBox}>
            <Section>
              <div style={{ width: '50%' }}>
                <Text variant="heading4xl" as="h1" alignment="center">
                  Supercharge your developers' productivity with Tuist
                  Cloud
                </Text>
              </div>
              <div className={styles.Stack}>
                <BuildTimesChart />
                <HighlightText
                  title="Tired of long build times?"
                  subtitle="We make your projects lean by caching your targets and your
          dependencies in the cloud. All synchronized between CI and
          your team."
                />
              </div>
            </Section>
            <Section>
              <div className={styles.Stack}>
                <HighlightText
                  title="Analytics"
                  subtitle="Are you wondering how long your tuist commands take? How efficient caching of your project is? We will give you insight, so you can focus on optimizing what matters"
                />
                <CommandEventItemShowcase />
              </div>
            </Section>
          </div>
          <Footer />
        </Frame>
      </BrowserRouter>
    </TuistCloudAppProvider>
  );
};

const Section = ({ children }: { children: ReactNode }) => {
  return (
    <div
      style={{
        alignItems: 'center',
        display: 'flex',
        flexDirection: 'column',
        paddingTop: '50px',
      }}
    >
      {children}
    </div>
  );
};
