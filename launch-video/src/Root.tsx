import "./index.css";
import { Composition, Still } from "remotion";
import { HeroStill, SocialStill } from "./components/HeroStill";
import { LaunchFilm } from "./LaunchFilm";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="MailLaunch"
        component={LaunchFilm}
        durationInFrames={570}
        fps={30}
        width={1920}
        height={1080}
      />
      <Still id="MailHero" component={HeroStill} width={1600} height={900} />
      <Still id="MailSocial" component={SocialStill} width={1280} height={640} />
    </>
  );
};
