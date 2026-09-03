# Mail launch film

The source for Mail's 19-second launch video, README hero, and GitHub social card. Every mailbox, sender, address, and message shown here is fictional.

## Preview

```bash
npm install
npm run dev
```

Remotion Studio opens at the local URL printed in the terminal.

## Render

```bash
npm run render
npm run render:hero
npm run render:social
```

Outputs are written to the git-ignored `out/` directory. The approved public exports live in `../docs/assets/`.

The film is 570 frames at 30 fps: exactly 19 seconds. Motion is frame-driven with Remotion interpolation so preview and render stay deterministic.

The cut opens with one restrained launch pop, then moves through K + Enter, an immediate reply and send, Command-K search, and a forwarded message. It finishes with a Command-K reminder, two deletes, and a flat, rapid archive pass to Inbox zero. Its motion direction follows Figma's [Principles in Motion](https://www.figma.com/blog/principles-in-motion/): clear intent, fast match cuts, short anticipation, controlled overshoot, and sound that reinforces each action.
