import { Audio } from "@remotion/media";
import {
  AbsoluteFill,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { AmbientBackground } from "./components/AmbientBackground";
import { ActiveKey, MailMode, MailWindow } from "./components/MailWindow";

const quickReply = "Perfect — Thursday works. See you then.";
const forwardRecipient = "maya@studio.example";
const forwardNote = "Thought you’d want this.";

const typedText = (copy: string, frame: number, start: number, end: number) => {
  const count = Math.floor(
    interpolate(frame, [start, end], [0, copy.length], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    }),
  );
  return copy.slice(0, count);
};

const isBetween = (frame: number, start: number, end: number) => frame >= start && frame < end;

const removedCountForFrame = (frame: number) => {
  if (frame >= 527) return 8;
  if (frame >= 514) return 7;
  if (frame >= 501) return 6;
  if (frame >= 488) return 5;
  if (frame >= 475) return 4;
  if (frame >= 464) return 3;
  if (frame >= 451) return 2;
  if (frame >= 438) return 1;
  return 0;
};

const cleanupToastForFrame = (frame: number) => {
  if (frame >= 514 && frame < 527) return "4 conversations archived";
  if (frame >= 501 && frame < 514) return "3 conversations archived";
  if (frame >= 488 && frame < 501) return "2 conversations archived";
  if (frame >= 475 && frame < 488) return "Conversation archived";
  if (frame >= 464 && frame < 475) return "2 conversations deleted";
  if (frame >= 451 && frame < 464) return "Conversation deleted";
  if (frame >= 438 && frame < 451) return "Reminder set for tomorrow, 9:00 AM";
  return "";
};

export const LaunchFilm: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  let mode: MailMode = "inbox";
  let activeKey: ActiveKey = null;
  let selectedIndex = frame < 36 ? 1 : 0;
  let replyText = "";
  let replySent = false;
  let threadProgress = 1;
  let commandQuery = "";
  let commandProgress = 1;
  let forwardOpen = false;
  let forwardProgress = 1;
  let recipient = "";
  let forwardMessage = "";
  let forwardSent = false;
  let showCaret = false;
  let cleanupToast = "";
  let inboxZeroProgress = 1;
  let removedCount = 0;

  if (isBetween(frame, 31, 39)) activeKey = "k";
  if (isBetween(frame, 44, 52)) activeKey = "enter";

  if (frame >= 52 && frame < 118) {
    mode = "thread";
    threadProgress = interpolate(frame, [52, 61], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    replyText = typedText(quickReply, frame, 65, 100);
    replySent = frame >= 108;
    showCaret = isBetween(frame, 65, 104);
    if (isBetween(frame, 104, 112)) activeKey = "send";
  } else if (frame >= 154 && frame < 226) {
    mode = "command";
    commandProgress = spring({
      frame: frame - 154,
      fps,
      durationInFrames: 13,
      config: { damping: 15, mass: 0.72, stiffness: 210 },
    });
    commandQuery = typedText("atlas", frame, 190, 214);
    showCaret = isBetween(frame, 190, 218);
    if (isBetween(frame, 148, 158)) activeKey = "cmd-k";
    if (isBetween(frame, 218, 226)) activeKey = "enter";
  } else if (frame >= 226 && frame < 366) {
    mode = "atlas";
    forwardOpen = frame >= 263;
    forwardProgress = spring({
      frame: frame - 263,
      fps,
      durationInFrames: 13,
      config: { damping: 15, mass: 0.72, stiffness: 210 },
    });
    recipient = typedText(forwardRecipient, frame, 270, 302);
    forwardMessage = typedText(forwardNote, frame, 306, 336);
    forwardSent = frame >= 350;
    showCaret = isBetween(frame, 270, 340);
    if (isBetween(frame, 254, 263)) activeKey = "f";
    if (isBetween(frame, 342, 352)) activeKey = "send";
  } else if (frame >= 366) {
    removedCount = removedCountForFrame(frame);
    cleanupToast = cleanupToastForFrame(frame);
    inboxZeroProgress = interpolate(frame, [527, 539], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    selectedIndex = 0;

    if (frame >= 376 && frame < 415) {
      mode = "command";
      commandProgress = spring({
        frame: frame - 376,
        fps,
        durationInFrames: 11,
        config: { damping: 18, mass: 0.7, stiffness: 220 },
      });
      commandQuery = typedText("remind", frame, 389, 404);
      showCaret = isBetween(frame, 389, 407);
      if (isBetween(frame, 376, 386)) activeKey = "cmd-k";
      if (isBetween(frame, 407, 415)) activeKey = "enter";
    } else if (frame >= 415 && frame < 438) {
      mode = "reminder";
      commandProgress = spring({
        frame: frame - 415,
        fps,
        durationInFrames: 10,
        config: { damping: 18, mass: 0.7, stiffness: 220 },
      });
      if (isBetween(frame, 430, 438)) activeKey = "enter";
    } else if (isBetween(frame, 443, 451) || isBetween(frame, 456, 464)) {
      activeKey = "delete";
    } else if (
      isBetween(frame, 469, 475)
      || isBetween(frame, 482, 488)
      || isBetween(frame, 495, 501)
      || isBetween(frame, 508, 514)
      || isBetween(frame, 521, 527)
    ) {
      activeKey = "e";
    }
  }

  const camera = cameraForFrame(frame, fps);

  return (
    <AbsoluteFill>
      <AmbientBackground frame={frame} />
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          transform: `translate(${camera.x}px, ${camera.y}px) scale(${camera.scale})`,
          transformOrigin: camera.origin,
        }}
      >
        <MailWindow
          activeKey={activeKey}
          cleanupToast={cleanupToast}
          commandBaseMode="inbox"
          commandProgress={commandProgress}
          commandQuery={commandQuery}
          forwardMessage={forwardMessage}
          forwardOpen={forwardOpen}
          forwardProgress={forwardProgress}
          forwardRecipient={recipient}
          forwardSent={forwardSent}
          inboxZeroProgress={inboxZeroProgress}
          mode={mode}
          removedCount={removedCount}
          replySent={replySent}
          replyText={replyText}
          selectedIndex={selectedIndex}
          showCaret={showCaret}
          threadProgress={threadProgress}
        />
      </AbsoluteFill>
      <Audio src={staticFile("mail-ambient.wav")} volume={(audioFrame) => interpolateVolume(audioFrame)} />
      {[31, 44, 104, 148, 218, 254, 342, 376, 407, 430, 443, 456, 469, 482, 495, 508, 521].map((start) => (
        <Sequence from={start} durationInFrames={4} key={`tap-${start}`}>
          <Audio src={staticFile("ui-tap.wav")} volume={0.72} />
        </Sequence>
      ))}
      {[52, 118, 226, 366, 415, 438].map((start) => (
        <Sequence from={start} durationInFrames={10} key={`whoosh-${start}`}>
          <Audio src={staticFile("ui-whoosh.wav")} volume={0.72} />
        </Sequence>
      ))}
      {[0, 154, 263, 376, 415, 527].map((start) => (
        <Sequence from={start} durationInFrames={6} key={`pop-${start}`}>
          <Audio src={staticFile("ui-pop.wav")} volume={() => (start === 0 ? 0.42 : 0.6)} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

const cameraForFrame = (frame: number, fps: number) => {
  const launch = spring({
    frame,
    fps,
    durationInFrames: 30,
    config: { damping: 20, mass: 0.78, stiffness: 180 },
  });

  if (frame < 52) {
    return {
      origin: "50% 52%",
      scale: 0.965 + launch * 0.035,
      x: 0,
      y: 16 * (1 - launch),
    };
  }

  if (frame < 118) {
    const open = interpolate(frame, [52, 61], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    return {
      origin: "55% 56%",
      scale: 1 + open * 0.052,
      x: -8 * open,
      y: 18 * (1 - open) - 12 * open,
    };
  }

  if (frame < 154) {
    const home = interpolate(frame, [118, 132], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    return { origin: "50% 52%", scale: 1.052 - home * 0.052, x: -8 * (1 - home), y: -12 * (1 - home) };
  }

  if (frame < 226) {
    const command = spring({
      frame: frame - 154,
      fps,
      durationInFrames: 15,
      config: { damping: 16, mass: 0.72, stiffness: 205 },
    });
    return { origin: "50% 48%", scale: 1 + command * 0.075, x: 0, y: -8 * command };
  }

  if (frame < 366) {
    const open = interpolate(frame, [226, 237], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    const forward = interpolate(frame, [263, 278], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    return {
      origin: "56% 58%",
      scale: 1.075 - open * 0.035 + forward * 0.035,
      x: -6 * forward,
      y: -8 - 16 * forward,
    };
  }

  const home = interpolate(frame, [366, 380], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const commandFocus = interpolate(frame, [376, 390, 424, 438], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const finish = interpolate(frame, [527, 570], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return {
    origin: "50% 52%",
    scale: 1.075 - home * 0.075 + commandFocus * 0.052 - finish * 0.014,
    x: -6 * (1 - home),
    y: -24 * (1 - home),
  };
};

const interpolateVolume = (frame: number) => {
  if (frame < 24) return (frame / 24) * 0.76;
  if (frame > 540) return Math.max(0, (570 - frame) / 30) * 0.76;
  return 0.76;
};
