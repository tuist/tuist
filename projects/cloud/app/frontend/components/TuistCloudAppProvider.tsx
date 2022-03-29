import React from 'react';
import { AppProvider } from '@shopify/polaris';
import { Link as ReactRouterLink } from 'react-router-dom';

interface TuistCloudAppProviderProps {
  children: JSX.Element;
}

const TuistCloudAppProvider = ({
  children,
}: TuistCloudAppProviderProps) => {
  const theme = {
    logo: {
      width: 124,
      topBarSource:
        'https://cdn.shopify.com/s/files/1/0446/6937/files/jaded-pixel-logo-color.svg?6215648040070010999',
      contextualSaveBarSource:
        'https://cdn.shopify.com/s/files/1/0446/6937/files/jaded-pixel-logo-gray.svg?6215648040070010999',
      url: 'http://jadedpixel.com',
      accessibilityLabel: 'Jaded Pixel',
    },
  };
  return (
    <AppProvider
      theme={theme}
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
      {children}
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
