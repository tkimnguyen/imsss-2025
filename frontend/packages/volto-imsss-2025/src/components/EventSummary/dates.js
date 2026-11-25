/**
 * Event dates for listings and teasers, in a given time zone.
 * Kept apart from EventSummary.jsx so it can be tested without the theme.
 */
export const formatSummaryDates = ({ start, end, locale, timeZone }) => {
  if (!start) return null;
  const formatter = new Intl.DateTimeFormat(locale || 'default', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    ...(timeZone ? { timeZone } : {}),
  });
  return end ? formatter.formatRange(start, end) : formatter.format(start);
};
