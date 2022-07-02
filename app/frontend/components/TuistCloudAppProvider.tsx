import React from 'react';
import { AppProvider } from '@shopify/polaris';
import { Link as ReactRouterLink } from 'react-router-dom';
import { PolarisVizProvider } from '@shopify/polaris-viz';

interface TuistCloudAppProviderProps {
  children: JSX.Element;
}

const TuistCloudAppProvider = ({
  children,
}: TuistCloudAppProviderProps) => {
  return (
    <AppProvider
      i18n={{
        Polaris: {
          Avatar: {
            label: 'Avatar',
            labelWithInitials: 'Avatar with initials {initials}',
          },
          ContextualSaveBar: {
            save: 'Save',
            discard: 'Discard',
          },
          TextField: {
            characterCount: '{count} characters',
          },
          TopBar: {
            toggleMenuLabel: 'Toggle menu',
          },
          Modal: {
            iFrameTitle: 'body markup',
          },
          Frame: {
            skipToContent: 'Skip to content',
            navigationLabel: 'Navigation',
            Navigation: {
              closeMobileNavigationLabel: 'Close navigation',
            },
          },
        },
      }}
      linkComponent={Link}
    >
      <PolarisVizProvider>{children}</PolarisVizProvider>
    </AppProvider>
  );
};

export default TuistCloudAppProvider;

/// Inspired by: https://github.com/Shopify/polaris-react/issues/2575#issuecomment-574269370
const Link = (props) => {
  const { url, external, ...rest } = props;
  if (external) {
    const target = external ? '_blank' : undefined;
    const rel = external ? 'noopener noreferrer' : undefined;
    return <a target={target} href={url} rel={rel} {...rest} />;
  }
  return <ReactRouterLink to={url} {...rest} />;
};
