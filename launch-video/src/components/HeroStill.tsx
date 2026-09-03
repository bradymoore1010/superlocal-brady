import { AbsoluteFill } from "remotion";
import { AmbientBackground } from "./AmbientBackground";
import { Icon } from "./Icons";
import { MailWindow } from "./MailWindow";

export const HeroStill: React.FC = () => (
  <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
    <AmbientBackground frame={210} />
    <MailWindow mode="inbox" selectedIndex={0} />
  </AbsoluteFill>
);

export const SocialStill: React.FC = () => (
  <AbsoluteFill>
    <AmbientBackground frame={315} />
    <div className="social-layout">
      <div className="social-copy">
        <h1>Mail, at keyboard speed.</h1>
        <p>A native, minimalist Gmail client for macOS.</p>
      </div>
      <div className="social-window-wrap">
        <MailWindow mode="thread" replyText="Thursday works. See you then." style={{ position: "absolute", inset: 0, width: 1250, height: 760 }} />
      </div>
      <div className="mail-mark" style={{ position: "absolute", right: 56, bottom: 48, width: 78, height: 78, borderRadius: 22 }}>
        <Icon name="inbox" size={38} />
      </div>
    </div>
  </AbsoluteFill>
);
