import { formatSummaryDates } from './EventSummary';

// Newer ICU puts thin spaces around the dash; compare with plain spaces.
const plain = (s) => s.replace(/\s/g, ' ');

describe('formatSummaryDates', () => {
  const timeZone = 'America/Chicago';

  it('shows a whole-day event on its own day, wherever the visitor is', () => {
    // 10 October 2026, midnight to 23:59:59 US Central.
    const text = formatSummaryDates({
      start: new Date('2026-10-10T05:00:00+00:00'),
      end: new Date('2026-10-11T04:59:59+00:00'),
      locale: 'en',
      timeZone,
    });
    expect(plain(text)).toBe('October 10, 2026');
  });

  it('shows a range for an event over several days', () => {
    const text = formatSummaryDates({
      start: new Date('2026-07-01T12:00:00+00:00'),
      end: new Date('2026-07-05T11:15:00+00:00'),
      locale: 'en',
      timeZone,
    });
    expect(plain(text)).toBe('July 1 – 5, 2026');
  });

  it('shows the start date alone when there is no end', () => {
    const text = formatSummaryDates({
      start: new Date('2026-05-14T12:00:00+00:00'),
      end: null,
      locale: 'en',
      timeZone,
    });
    expect(plain(text)).toBe('May 14, 2026');
  });

  it('returns nothing without a start date', () => {
    expect(formatSummaryDates({ start: null, end: null })).toBeNull();
  });
});
