import { Text } from '@shopify/polaris';
import React from 'react';

import styles from './HighlightText.module.scss';

interface Props {
  title: string;
  subtitle: string;
}

export const HighlightText = ({ title, subtitle }: Props) => {
  return (
    <span className={styles.HighlightText}>
      <Text variant="headingXl" as="h2">
        {title}
      </Text>
      <div style={{ marginTop: '10px' }}>
        <Text variant="bodyLg" as="p" color="subdued">
          {subtitle}
        </Text>
      </div>
    </span>
  );
};
