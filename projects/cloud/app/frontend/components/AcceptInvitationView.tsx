import React, { useEffect, useState } from 'react';
import { CalloutCard } from '@shopify/polaris';
import { useParams } from 'react-router-dom';
import AcceptInvitationViewStore from '@/stores/AcceptInvitationViewStore';
import { useApolloClient } from '@apollo/client';
import { observer } from 'mobx-react-lite';

const AcceptInvitationView = observer(() => {
  const { token } = useParams();
  const client = useApolloClient();
  const [acceptInvitationViewStore] = useState(
    () => new AcceptInvitationViewStore(client),
  );
  useEffect(() => {
    console.log('loading');
    acceptInvitationViewStore.load(token ?? '');
  }, [token]);
  return (
    <div
      style={{
        marginTop: '100px',
        justifyContent: 'center',
        display: 'flex',
      }}
    >
      {/* @ts-ignore */}
      <CalloutCard
        title={`${acceptInvitationViewStore.inviterEmail} has invited you to join the ${acceptInvitationViewStore.organizationName} organization.`}
        primaryAction={{
          content: 'Accept the invitation',
        }}
      >
        <p>
          Accepting this invitation will give you access to the
          organization's projects.
        </p>
      </CalloutCard>
    </div>
  );
});

export default AcceptInvitationView;
