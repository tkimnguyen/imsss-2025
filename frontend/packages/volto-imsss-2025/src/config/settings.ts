import type { ConfigType } from '@plone/registry';
import FooterLogin from '../components/FooterLogin/FooterLogin';
import EventView from '../components/EventView/EventView';

export default function install(config: ConfigType) {
  // Language settings
  config.settings.isMultilingual = false;
  config.settings.supportedLanguages = ['en'];
  config.settings.defaultLanguage = 'en';

  // Plone's time zone (Site Setup > Date and Time). Plone stores a whole-day
  // event as midnight to 23:59:59 in this zone; the event view needs it to
  // show the right day to visitors elsewhere.
  config.settings.siteTimeZone = 'America/Chicago';

  // Event pages: VLT's view, but whole-day events show the date only.
  // VLT registers its own EventView; this add-on loads after VLT.
  config.views.contentTypesViews.Event = EventView;

  // Move the Log in link from the header's top row to the end of the footer.
  // VLT registers Anontools in the headerTools slot; this add-on loads after
  // VLT, so the registration is there to remove.
  config.unRegisterSlotComponent('headerTools', 'Anontools', 0);
  config.registerSlotComponent({
    slot: 'postFooter',
    name: 'FooterLogin',
    component: FooterLogin,
  });

  return config;
}
