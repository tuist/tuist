import { TuistIcon } from '@/components/icons/TuistIcon';
import { Image, Link, Stack, Text } from '@shopify/polaris';
import React from 'react';
import styles from './TopBar.module.scss';
import { GithubIcon } from '@/components/icons';

export const TopBar = () => {
  return (
    <div className={styles.TopBar}>
      <TuistIcon />
      <Image
        source="../../assets/logo.svg"
        alt="Tuist logo"
        width="40px"
        style={{ marginRight: '20px' }}
      />
      <Text variant="headingLg" as="h2">
        Tuist Cloud
      </Text>
      <div style={{ flex: 1 }} />
      <Stack>
        <Link
          removeUnderline
          url="https://docs.tuist.io/cloud/get-started/"
          external
        >
          <Text variant="headingMd" as="h3">
            Docs
          </Text>
        </Link>
        <Link removeUnderline url="users/sign_in" external>
          <Text variant="headingMd" as="h3">
            Login
          </Text>
        </Link>
        <Link removeUnderline url="users/sign_in" external>
          <GithubIcon />
        </Link>
      </Stack>
    </div>
  );
};
