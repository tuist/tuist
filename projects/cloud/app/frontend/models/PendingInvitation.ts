import { PendingInvitationFragment } from '@/graphql/types';

export interface PendingInvitation {
  id: string;
  inviteeEmail: string;
  accepted: boolean;
}

export const mapPendingInvitation = ({
  id,
  inviteeEmail,
  accepted,
}: PendingInvitationFragment) => {
  return {
    id,
    inviteeEmail,
    accepted,
  } as PendingInvitation;
};
