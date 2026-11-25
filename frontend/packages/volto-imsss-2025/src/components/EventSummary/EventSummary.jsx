/**
 * Event summary in listings and teasers: Volto Light Theme's EventSummary,
 * with the dates worked out in the site's time zone.
 *
 * VLT 7.8.6 (and 8.1.5) prints the start and end dates in the visitor's own
 * time zone. Plone stores a whole-day event as midnight to 23:59:59 in the
 * site's time zone, so visitors east of it saw a one-day event as two days
 * ("October 10 – 11, 2026"). Search results don't say whether an event is
 * whole day, so this uses the site's time zone for every event: each event
 * then shows its dates where it is held, the same for every visitor.
 *
 * Drop this file and its registration in config/settings.ts once VLT does
 * this itself.
 */

import React from 'react';
import { parseDateFromCatalog } from '@kitconcept/volto-light-theme/helpers/dates';
import { smartTextRenderer } from '@kitconcept/volto-light-theme/helpers/smartText';
import config from '@plone/volto/registry';

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

const EventSummary = (props) => {
  const { item, HeadingTag = 'h3', a11yLabelId, hide_description } = props;
  const start = item.start ? parseDateFromCatalog(item.start) : null;
  const end = item.end ? parseDateFromCatalog(item.end) : null;
  const dates = formatSummaryDates({
    start,
    end,
    locale: item.Language,
    timeZone: config.settings.siteTimeZone,
  });
  const headline = [
    dates ? (
      <span className="day" key="day" suppressHydrationWarning>
        {dates}
      </span>
    ) : null,
    item.head_title,
  ]
    .filter((x) => x)
    .flatMap((x) => [' | ', x])
    .slice(1);

  return (
    <>
      {headline.length ? <div className="headline">{headline}</div> : null}
      <HeadingTag className="title" id={a11yLabelId}>
        {item.title ? item.title : item.id}
      </HeadingTag>
      {!hide_description && (
        <p className="description">{smartTextRenderer(item.description)}</p>
      )}
    </>
  );
};

export default EventSummary;
