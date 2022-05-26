import { CacheHitRateAverageFragment } from '@/graphql/types';

export interface CacheHitRateAverage {
  date: Date;
  cacheHitRateAverage: number;
}

export const mapCacheHitRateAverage: (
  cacheHitRateAverageFragment: CacheHitRateAverageFragment,
) => CacheHitRateAverage = ({ date, cacheHitRateAverage }) => {
  return {
    date: new Date(date),
    cacheHitRateAverage,
  };
};
