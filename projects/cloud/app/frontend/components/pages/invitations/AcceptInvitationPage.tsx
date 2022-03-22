import React, { useEffect, useState } from 'react';
import { CalloutCard } from '@shopify/polaris';
import { useNavigate, useParams } from 'react-router-dom';
import AcceptInvitationPageStore from './AcceptInvitationPageStore';
import { useApolloClient } from '@apollo/client';
import { observer } from 'mobx-react-lite';

const AcceptInvitationPage = observer(() => {
  const { token } = useParams();
  const client = useApolloClient();
  const [acceptInvitationPageStore] = useState(
    () => new AcceptInvitationPageStore(client),
  );
  useEffect(() => {
    acceptInvitationPageStore.load(token ?? '');
  }, [token]);

  const navigate = useNavigate();

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
        title={`${acceptInvitationPageStore.inviterEmail} has invited you to join the ${acceptInvitationPageStore.organizationName} organization.`}
        primaryAction={{
          content: 'Accept the invitation',
          onAction: async () => {
            console.log('Accept me!');
            // TODO: Handle error (e.g. when already signed in but with a different account than the invitation was meant for)
            const slug =
              await acceptInvitationPageStore.acceptInvitation(
                token ?? '',
              );
            console.log('ola');
            console.log(slug);
            navigate(`/${slug}`);
          },
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

export default AcceptInvitationPage;
