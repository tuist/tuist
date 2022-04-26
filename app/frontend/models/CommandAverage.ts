import { CommandAverageFragment } from '@/graphql/types';

export interface CommandAverage {
  date: Date;
  durationAverage: number;
}

export const mapCommandAverage: (
  commandAverageFragment: CommandAverageFragment,
) => CommandAverage = ({ date, durationAverage }) => {
  return {
    date: new Date(date),
    durationAverage,
  };
};
