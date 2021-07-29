import React, { useState, useCallback } from 'react';
import { TopBar } from '@shopify/polaris';
import { useHistory } from 'react-router-dom';
import {
  projectNewPath,
  organizationNewPath,
  settingsPath,
} from '../utilities/routes';
import signOut from '../networking/signOut';
import { useEnvironment } from '../utilities/EnvironmentProvider';

const TopBarUserMenu = () => {
  const history = useHistory();
  const environment = useEnvironment();

  const [userMenuActive, setUserMenuActive] = useState(false);
  const toggleUserMenuActive = useCallback(
    () => setUserMenuActive((_userMenuActive) => !_userMenuActive),
    [],
  );
  const userMenuActions = [
    {
      items: [
        {
          content: 'New project',
          accessibilityLabel: 'Create a new project',
          onAction: () => {
            history.push(projectNewPath);
          },
        },
        {
          content: 'New organization',
          accesibilityLabel: 'Create a new organization',
          onAction: () => {
            history.push(organizationNewPath);
          },
        },
        {
          content: 'Settings',
          accesibility: 'Check out and change the user settings',
          onAction: () => {
            history.push(settingsPath);
          },
        },
        {
          content: 'Sign out',
          onAction: signOut,
        },
      ],
    },
  ];

  return (
    <TopBar.UserMenu
      actions={userMenuActions}
      name={environment.user.email}
      detail="Test"
      initials="S"
      avatar={environment.user.avatarUrl}
      open={userMenuActive}
      onToggle={toggleUserMenuActive}
    />
  );
};

export default TopBarUserMenu;
