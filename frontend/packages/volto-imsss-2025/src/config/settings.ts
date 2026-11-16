import type { ConfigType } from '@plone/registry';
import FooterLogin from '../components/FooterLogin/FooterLogin';

export default function install(config: ConfigType) {
  // Language settings
  config.settings.isMultilingual = false;
  config.settings.supportedLanguages = ['en'];
  config.settings.defaultLanguage = 'en';

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
