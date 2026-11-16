import Anontools from '@kitconcept/volto-light-theme/components/Anontools/Anontools';

/**
 * The Log in (or Log out) link, moved from the header's top row to the
 * bottom of the footer to save vertical space at the top of the page.
 * Reuses VLT's Anontools so it shows the same links the header did.
 */
const FooterLogin = () => (
  <div className="footer-login">
    <Anontools />
  </div>
);

export default FooterLogin;
