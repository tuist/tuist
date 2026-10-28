import dashboard from './build-health.json';

const panel = (id: number) => dashboard.panels.find((item) => item.id === id)!;

describe('standard build health dashboard', () => {
  it('presents automatic percentile counts neutrally while preserving the metric key', () => {
    expect(panel(6).title).toBe('Failed or slow builds');
    expect(panel(6).options.colorMode).toBe('none');
    expect(panel(6).targets[0]).toMatchObject({ metric: 'builds_needing_attention' });
    expect(panel(6).description).toContain('not a regression');
    expect(panel(4).description).toContain('fixed duration limit');
  });

  it('charts exclusive categories and shows total failures separately without changing query frames', () => {
    expect(panel(8).title).toBe('Failure categories');
    expect(panel(8).targets[0].queryType).toBe('buildFailureReasons');
    expect(panel(8).transformations).toEqual([
      {
        id: 'filterByValue',
        options: {
          type: 'exclude',
          match: 'all',
          filters: [{ fieldName: 'Failure category', config: { id: 'equal', options: { value: 'All failures' } } }],
        },
      },
    ]);
    expect(panel(16).targets[0]).toMatchObject({ metric: 'failed_builds' });
  });

  it('groups each savings value beside its coverage and puts the automatic estimate first', () => {
    expect(panel(14).title).toBe('Cumulative task time saved');
    expect(panel(14).description).toContain('Gradle-only');
    expect(panel(14).description).toContain('does not measure elapsed');
    for (const [valueId, coverageId] of [
      [14, 15],
      [5, 12],
    ]) {
      const value = panel(valueId);
      const coverage = panel(coverageId);
      expect(coverage.gridPos.y).toBe(value.gridPos.y);
      expect(coverage.gridPos.x).toBe(value.gridPos.x + value.gridPos.w);
    }
    expect(panel(14).gridPos.x).toBeLessThan(panel(5).gridPos.x);
    expect(panel(14).gridPos.y).toBe(panel(5).gridPos.y);
  });
});
