type IconProps = {
  name: "archive" | "back" | "clock" | "compose" | "inbox" | "paperclip" | "search" | "send" | "signature" | "spark" | "star";
  size?: number;
};

export const Icon: React.FC<IconProps> = ({ name, size = 18 }) => {
  const paths: Record<IconProps["name"], React.ReactNode> = {
    archive: <path d="M4 8h16v11H4zM3 4h18v4H3zm6 8h6" />,
    back: <path d="m15 18-6-6 6-6" />,
    clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
    compose: <path d="M13.5 5.5 18.5 10.5 8 21H3v-5zM15 4l2-2 5 5-2 2" />,
    inbox: <path d="M4 5h16v14H4zM4 13h5l2 3h2l2-3h5" />,
    paperclip: <path d="m9 12 6-6a3 3 0 0 1 4 4l-8 8a5 5 0 0 1-7-7l8-8" />,
    search: <path d="m20 20-4.4-4.4M10.5 18a7.5 7.5 0 1 1 0-15 7.5 7.5 0 0 1 0 15Z" />,
    send: <path d="m3 3 19 9-19 9 4-9zM7 12h15" />,
    signature: <path d="M4 17c2-4 3-9 5-9 3 0-1 8 2 8 2 0 3-4 5-4 1 0 1 3 4 3M4 20h16" />,
    spark: <path d="m12 2 1.7 5.3L19 9l-5.3 1.7L12 16l-1.7-5.3L5 9l5.3-1.7zM19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z" />,
    star: <path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-2.9-5.6 2.9 1.1-6.2L3 9.6l6.2-.9z" />,
  };

  return (
    <svg
      aria-hidden="true"
      fill="none"
      height={size}
      viewBox="0 0 24 24"
      width={size}
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth={1.7}
    >
      {paths[name]}
    </svg>
  );
};
