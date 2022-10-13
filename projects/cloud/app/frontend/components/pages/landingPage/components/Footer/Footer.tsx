import { Link as PolarisLink, Stack, Text } from '@shopify/polaris';
import { TuistIcon } from '@/components/icons/TuistIcon';
import React from 'react';
import styles from './Footer.module.scss';

interface FooterLinkProps {
  text: string;
  url: string;
}

const Link = ({ text, url }: FooterLinkProps) => {
  return (
    <PolarisLink removeUnderline monochrome external url={url}>
      <Text variant="bodyLg" as="p" color="subdued">
        {text}
      </Text>
    </PolarisLink>
  );
};

export const Footer = () => {
  return (
    <div className={styles.Footer}>
      <div className={styles.LinksStack}>
        <Stack vertical spacing="tight">
          <Text variant="headingMd" as="h3">
            Learn more
          </Text>
          <Link
            text="Docs"
            url="https://docs.tuist.io/cloud/get-started"
          />
          <Link text="Blog" url="https://tuist.io/blog" />
          <Link
            text="Releases"
            url="https://github.com/tuist/tuist/releases"
          />
        </Stack>
        <Stack vertical spacing="tight">
          <Text variant="headingMd" as="h3">
            About tuist
          </Text>
          <Link text="Twitter" url="https://twitter.com/tuistio" />
          <Link text="GitHub" url="https://github.com/tuist/tuist" />
        </Stack>
      </div>
      <Text variant="bodyLg" as="p">
        Tuist © Copyright 2022. All rights reserved.
      </Text>
    </div>
  );
};
