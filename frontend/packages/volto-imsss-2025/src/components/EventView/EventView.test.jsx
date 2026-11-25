import { formatEventDate } from './EventView';

describe('formatEventDate', () => {
  const site = 'America/Chicago';

  it('shows only the date for a one-day, whole-day event', () => {
    // Plone stores a whole-day event as midnight to 23:59:59 in the site's
    // time zone: here 10 October 2026, US Central (UTC-5 in October).
    const content = {
      language: { token: 'en' },
      start: '2026-10-10T05:00:00+00:00',
      end: '2026-10-11T04:59:59+00:00',
      whole_day: true,
    };
    expect(formatEventDate(content, site)).toBe('October 10, 2026');
  });

  it('shows a date range for a whole-day event over several days', () => {
    const content = {
      language: { token: 'en' },
      start: '2026-07-01T05:00:00+00:00',
      end: '2026-07-06T04:59:59+00:00',
      whole_day: true,
    };
    // Newer ICU puts thin spaces around the dash; compare with plain spaces.
    const text = formatEventDate(content, site).replace(/\s/g, ' ');
    expect(text).toBe('July 1 – 5, 2026');
  });

  it('keeps the time for a timed event', () => {
    const content = {
      language: { token: 'en' },
      start: '2026-07-03T13:30:00+00:00',
      end: '2026-07-03T15:00:00+00:00',
      whole_day: false,
    };
    expect(formatEventDate(content, site)).toMatch(/\d:\d\d/);
  });

  it('returns nothing without a start date', () => {
    expect(formatEventDate({ whole_day: true }, site)).toBeNull();
  });
});
