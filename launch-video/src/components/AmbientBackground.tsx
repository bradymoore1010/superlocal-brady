import { interpolate } from "remotion";

export const AmbientBackground: React.FC<{ frame: number }> = ({ frame }) => {
  const drift = interpolate(frame, [0, 570], [-3, 6], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const lift = interpolate(frame, [0, 285, 570], [2, -4, 3], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        overflow: "hidden",
        background:
          "radial-gradient(95% 130% at 10% 70%, rgba(12,91,79,.98), transparent 62%), radial-gradient(75% 100% at 94% 84%, rgba(3,53,48,.98), transparent 58%), #215c52",
      }}
    >
      <div
        style={{
          position: "absolute",
          width: "66%",
          height: "120%",
          left: `${18 + drift}%`,
          top: `${-42 + lift}%`,
          borderRadius: "50%",
          background: "rgba(229, 218, 149, 0.82)",
          filter: "blur(116px)",
          transform: `rotate(${interpolate(frame, [0, 570], [-11, -3])}deg)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          width: "48%",
          height: "100%",
          right: `${-18 - drift / 2}%`,
          bottom: `${-33 - lift}%`,
          borderRadius: "50%",
          background: "rgba(89, 181, 159, 0.78)",
          filter: "blur(118px)",
          transform: `rotate(${interpolate(frame, [0, 570], [8, 19])}deg)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          width: "28%",
          height: "82%",
          left: `${-7 + drift / 3}%`,
          bottom: "-20%",
          borderRadius: "50%",
          background: "rgba(7, 52, 46, 0.86)",
          filter: "blur(88px)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: 0.14,
          backgroundImage:
            "linear-gradient(90deg, rgba(255,255,255,.22) 1px, transparent 1px), linear-gradient(rgba(255,255,255,.12) 1px, transparent 1px)",
          backgroundSize: "160px 160px",
          transform: `translate(${drift * 1.5}px, ${lift * 2}px)`,
          maskImage: "linear-gradient(to bottom, transparent, black 24%, black 76%, transparent)",
        }}
      />
    </div>
  );
};
