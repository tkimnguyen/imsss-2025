/**
 * Event page view: Volto Light Theme's EventView, plus whole-day events.
 *
 * VLT 7.8.6 (and 8.1.5) always prints the start and end with hours and
 * minutes, so a whole-day event reads "October 10, 2026, 12:00 AM – 11:59 PM",
 * and in the visitor's own time zone, which can move it onto the next day.
 * For whole-day events this view prints the date only, worked out in the
 * site's time zone (`config.settings.siteTimeZone`). Timed events are shown
 * exactly as VLT shows them.
 *
 * Drop this file and its registration in config/settings.ts once VLT handles
 * whole-day events itself.
 */

import React from 'react';
import PropTypes from 'prop-types';
import { hasBlocksData } from '@plone/volto/helpers/Blocks/Blocks';
import { flattenHTMLToAppURL } from '@plone/volto/helpers/Url/Url';
import { Container as SemanticContainer } from 'semantic-ui-react';
import RenderBlocks from '@plone/volto/components/theme/View/RenderBlocks';
import config from '@plone/volto/registry';

const EventTextfieldView = ({ content }) => {
  const Image = config.getComponent({ name: 'Image' }).component;
  return (
    <React.Fragment>
      {content.title && (
        <h1 className="documentFirstHeading">{content.title}</h1>
      )}
      {content.description && (
        <p className="documentDescription">{content.description}</p>
      )}
      {content.preview_image && (
        <Image
          className="document-image ui right floated image"
          item={content}
          imageField="preview_image"
          alt=""
        />
      )}
      {content.text && (
        <div
          dangerouslySetInnerHTML={{
            __html: flattenHTMLToAppURL(content.text.data),
          }}
        />
      )}
    </React.Fragment>
  );
};

export const formatEventDate = (content, siteTimeZone) => {
  const language = content.language?.token || 'default';
  const start = content.start ? new Date(content.start) : null;
  const end = content.end ? new Date(content.end) : null;
  if (!start) return null;
  const isOpenEnd = !!content.open_end;

  const options = content.whole_day
    ? {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        ...(siteTimeZone ? { timeZone: siteTimeZone } : {}),
      }
    : {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: 'numeric',
        minute: 'numeric',
      };
  const formatter = new Intl.DateTimeFormat(language, options);
  // formatRange prints a single date when start and end fall on the same day.
  return !end || isOpenEnd
    ? formatter.format(start)
    : formatter.formatRange(start, end);
};

const EventView = (props) => {
  const { content } = props;
  const Container =
    config.getComponent({ name: 'Container' }).component || SemanticContainer;
  const formattedDate = formatEventDate(
    content,
    config.settings.siteTimeZone,
  );

  return (
    <Container id="page-document" className="view-wrapper event-view">
      <div className="dates">
        {formattedDate ? (
          <span className="day" suppressHydrationWarning>
            {formattedDate}
          </span>
        ) : null}{' '}
        {content?.head_title && (
          <span className="head-title"> {content?.head_title}</span>
        )}
      </div>
      {hasBlocksData(content) ? (
        <RenderBlocks {...props} />
      ) : (
        <EventTextfieldView {...props} />
      )}
    </Container>
  );
};

EventView.propTypes = {
  content: PropTypes.shape({
    title: PropTypes.string,
    description: PropTypes.string,
    text: PropTypes.shape({
      data: PropTypes.string,
    }),
    start: PropTypes.string,
    end: PropTypes.string,
    open_end: PropTypes.bool,
    whole_day: PropTypes.bool,
  }).isRequired,
};

export default EventView;
