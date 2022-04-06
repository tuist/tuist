import { HomeStoreContext } from '@/stores/HomeStore';
import {
  Button,
  Card,
  Heading,
  Modal,
  Page,
  Stack,
  TextField,
} from '@shopify/polaris';
import { observer } from 'mobx-react-lite';
import React, { useContext, useState } from 'react';
import SettingsPageStore from './SettingsPageStore';

const SettingsPage = observer(() => {
  const homeStore = useContext(HomeStoreContext);
  const [settingsPageStore] = useState(
    () => new SettingsPageStore(homeStore.projectStore),
  );
  return (
    <>
      <Page title="Settings">
        <Card sectioned>
          <Card.Section title="Project Settings">
            <Stack>
              <Stack.Item fill={true}>
                <Stack vertical={true} spacing="extraTight">
                  <Heading>Delete this project</Heading>
                  <p>
                    You cannot undo deleting a project. Be careful!
                  </p>
                </Stack>
              </Stack.Item>
              <Button
                destructive={true}
                onClick={() => {
                  settingsPageStore.isDeleteProjectConfirmModalActive =
                    true;
                }}
              >
                Delete this project
              </Button>
            </Stack>
          </Card.Section>
        </Card>
      </Page>
      <Modal
        open={settingsPageStore.isDeleteProjectConfirmModalActive}
        title={`Are you sure you want to delete the ${
          homeStore.projectStore.project?.slug ?? ''
        } project?`}
        onClose={() => {
          settingsPageStore.deleteProjectConfirmModalDismissed();
        }}
      >
        <Modal.Section>
          <Stack distribution="center">
            <TextField
              label={`To permanently delete the project, type
            ${homeStore.projectStore.project?.slug ?? ''}
            to confirm.`}
              value={settingsPageStore.currentProjectSlugToDelete}
              onChange={(newValue) => {
                settingsPageStore.currentProjectSlugToDelete =
                  newValue;
              }}
            />
            <Button destructive={true} onClick={() => {}}>
              Permanently delete this project
            </Button>
          </Stack>
        </Modal.Section>
      </Modal>
    </>
  );
});

export default SettingsPage;
