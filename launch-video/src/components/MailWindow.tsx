import { inboxMessages } from "../data";
import { Icon } from "./Icons";

export type MailMode = "atlas" | "command" | "first-contact" | "inbox" | "reminder" | "thread";
export type ActiveKey = "cmd-k" | "delete" | "e" | "enter" | "f" | "j" | "k" | "r" | "send" | null;

type MailWindowProps = {
  activeKey?: ActiveKey;
  cleanupToast?: string;
  commandBaseMode?: "inbox" | "thread";
  commandProgress?: number;
  commandQuery?: string;
  firstContactReplyOpen?: boolean;
  firstContactReplyProgress?: number;
  forwardMessage?: string;
  forwardOpen?: boolean;
  forwardProgress?: number;
  forwardRecipient?: string;
  forwardSent?: boolean;
  inboxZeroProgress?: number;
  mode: MailMode;
  removedCount?: number;
  replySent?: boolean;
  replyText?: string;
  selectedIndex?: number;
  showCaret?: boolean;
  style?: React.CSSProperties;
  threadProgress?: number;
};

const KeyCap: React.FC<React.PropsWithChildren<{ active?: boolean; dark?: boolean }>> = ({
  active = false,
  children,
  dark = false,
}) => (
  <span className={`key-cap${active ? " active" : ""}${dark ? " dark" : ""}`}>{children}</span>
);

const Sidebar = ({ activeKey, inboxCount = 3 }: { activeKey: ActiveKey; inboxCount?: number }) => (
  <aside className="mail-sidebar">
    <div className="traffic-lights" aria-hidden="true">
      <span className="traffic-light" style={{ background: "#ff5f57" }} />
      <span className="traffic-light" style={{ background: "#febc2e" }} />
      <span className="traffic-light" style={{ background: "#28c840" }} />
    </div>
    <div className="sidebar-stack">
      <div className="sidebar-group">
        <div className="sidebar-row active">
          <span className="sidebar-icon"><Icon name="inbox" size={15} /></span>
          <span>Inbox</span>
          <span className="sidebar-count">{inboxCount || ""}</span>
        </div>
        <div className="sidebar-row">
          <span className="sidebar-icon"><Icon name="star" size={15} /></span>
          <span>Starred</span>
          <span />
        </div>
        <div className="sidebar-row"><span className="sidebar-icon">↗</span><span>Sent</span><span /></div>
        <div className="sidebar-row"><span className="sidebar-icon">□</span><span>Drafts</span><span className="sidebar-count faint">1</span></div>
        <div className="sidebar-row"><span className="sidebar-icon">↓</span><span>Archive</span><span /></div>
      </div>
      <div className="sidebar-group labels-group">
        <div className="sidebar-label">Labels</div>
        <div className="sidebar-row"><span className="sidebar-icon">◇</span><span>Updates</span><span /></div>
        <div className="sidebar-row"><span className="sidebar-icon">○</span><span>Receipts</span><span /></div>
      </div>
    </div>
    <div className="sidebar-spacer" />
    <div className="sidebar-footer">
      <div className="account-status"><span className="status-check">✓</span><span>you@example.com</span></div>
      <div className="sidebar-hairline" />
      <div className="command-status"><span>Command menu</span><KeyCap active={activeKey === "cmd-k"}>⌘ K</KeyCap></div>
    </div>
  </aside>
);

const KeyboardFooter = ({ activeKey }: { activeKey: ActiveKey }) => (
  <footer className="keyboard-footer">
    <span className="shortcut-hint">
      <span className="key-pair"><KeyCap active={activeKey === "j"}>J</KeyCap><KeyCap active={activeKey === "k"}>K</KeyCap></span>
      Move
    </span>
    <span className="shortcut-hint"><KeyCap active={activeKey === "enter"}>↵</KeyCap> Open</span>
    <span className="shortcut-hint"><KeyCap active={activeKey === "e"}>E</KeyCap> Archive</span>
    <span className="shortcut-hint"><KeyCap active={activeKey === "delete"}>⌫</KeyCap> Delete</span>
    <span className="shortcut-hint"><KeyCap active={activeKey === "r"}>R</KeyCap> Reply</span>
  </footer>
);

const Inbox = ({
  activeKey,
  cleanupToast = "",
  inboxZeroProgress = 1,
  removedCount = 0,
  selectedIndex = 0,
}: {
  activeKey: ActiveKey;
  cleanupToast?: string;
  inboxZeroProgress?: number;
  removedCount?: number;
  selectedIndex?: number;
}) => {
  const visibleMessages = inboxMessages.slice(removedCount);
  const remainingUnread = Math.max(0, 3 - removedCount);
  return (
    <>
    <header className="mail-header inbox-header">
      <div className="inbox-heading"><h1 className="mail-title">Inbox</h1><span className="mail-count">{remainingUnread ? `${remainingUnread} unread` : "All caught up"}</span></div>
      <div className="header-actions">
        <div className="glass-button primary"><span>Draft</span><span className="button-key">C</span></div>
      </div>
    </header>
    <section className={`mail-list${visibleMessages.length === 0 ? " empty" : ""}`}>
      {visibleMessages.length === 0 ? (
        <div
          className="inbox-zero"
          style={{
            opacity: inboxZeroProgress,
            transform: `translateY(${(1 - inboxZeroProgress) * 8}px)`,
          }}
        >
          <div className="inbox-zero-mark">✓</div>
          <strong>Inbox zero</strong>
          <span>Nothing left to triage.</span>
        </div>
      ) : visibleMessages.map((message, index) => (
        <div
          className={`mail-row ${message.unread ? "unread" : ""} ${index === selectedIndex ? "selected" : ""}`}
          key={`${message.sender}-${message.subject}`}
        >
          <span className="sender-cell"><span className="unread-dot" style={{ visibility: message.unread ? "visible" : "hidden" }} /><span className="sender-name">{message.sender}</span></span>
          <span className="subject-preview"><span className="row-subject">{message.subject}</span><span className="row-preview">{message.preview}</span></span>
          <span className="row-time">{message.time}</span>
        </div>
      ))}
    </section>
    <KeyboardFooter activeKey={activeKey} />
    {cleanupToast ? <div className="action-toast">{cleanupToast}</div> : null}
    </>
  );
};

const ReaderHeader = ({
  activeKey,
  kind,
}: {
  activeKey: ActiveKey;
  kind: "atlas" | "correspondence" | "first-contact";
}) => {
  const title = kind === "atlas" ? "Updated policy" : kind === "first-contact" ? "Your order shipped" : "Project handoff";
  const sender = kind === "atlas"
    ? "Atlas Health · benefits@atlas.example"
    : kind === "first-contact"
      ? "Northwind · orders@northwind.example"
      : "Ava Patel · ava@northwind.example";
  return (
    <header className="mail-header reader-header">
      <div className="reader-heading">
        <div className="back-button"><Icon name="back" size={15} /></div>
        <div className="reader-subject">
          <strong>{title}</strong>
          <span>{sender}</span>
        </div>
      </div>
      <div className="header-actions">
        {kind === "atlas" ? (
          <div className={`glass-button${activeKey === "f" ? " pressed" : ""}`}><span>Forward</span><span className="button-key muted">F</span></div>
        ) : (
          <div className={`glass-button${activeKey === "r" ? " pressed" : ""}`}><span>Reply</span><span className="button-key muted">R</span></div>
        )}
        <div className={`glass-button${activeKey === "e" ? " pressed" : ""}`}><span>Archive</span><span className="button-key muted">E</span></div>
        <div className="glass-button"><span>More</span><span>•••</span></div>
      </div>
    </header>
  );
};

const ReplyComposer = ({
  name,
  progress = 1,
  replyText,
  sendActive = false,
  sent = false,
  showCaret,
}: {
  name: string;
  progress?: number;
  replyText: string;
  sendActive?: boolean;
  sent?: boolean;
  showCaret: boolean;
}) => (
  <section
    className="reply-composer"
    style={{
      opacity: Math.min(1, Math.max(0, progress)),
      transform: `translateY(${(1 - progress) * 24}px) scale(${0.985 + progress * 0.015})`,
    }}
  >
    <div className="reply-label">Reply to {name}</div>
    <div className={`reply-text${replyText ? " has-copy" : ""}`}>
      {replyText || "Write a reply…"}
      {showCaret ? <span className="text-caret" /> : null}
    </div>
    <footer className="composer-footer">
      <div className="composer-tools"><Icon name="paperclip" size={16} /><span>Aa</span><span>Draft saved automatically</span></div>
      <div className="send-group"><KeyCap active={sendActive}>⌘ ↵</KeyCap><span>{sent ? "Sent" : "Send"}</span><div className={`send-button${replyText ? " enabled" : ""}${sendActive ? " pressed" : ""}${sent ? " sent" : ""}`}>{sent ? "Sent" : "Send"}</div></div>
    </footer>
  </section>
);

const Thread = ({
  activeKey,
  progress = 1,
  replySent = false,
  replyText = "",
  showCaret = false,
}: {
  activeKey: ActiveKey;
  progress?: number;
  replySent?: boolean;
  replyText?: string;
  showCaret?: boolean;
}) => (
  <>
    <ReaderHeader activeKey={activeKey} kind="correspondence" />
    <section className="reader-area">
      <div className="conversation" style={{ opacity: progress, transform: `translateY(${(1 - progress) * 176}px)` }}>
        <div className="compact-message"><strong>You</strong><span>Here is the first draft and the open question on timing.</span><time>Aug 27</time></div>
        <div className="compact-message"><strong>Ava Patel</strong><span>Looks good. I left two comments in the document.</span><time>Aug 28</time></div>
        <div className="compact-message"><strong>You</strong><span>Both comments are resolved. Thursday still works on my side.</span><time>Aug 31</time></div>
        <article className="expanded-message">
          <div className="message-meta"><div><strong>Ava Patel</strong><span>From ava@northwind.example</span><span>to you@example.com</span></div><div><span>Today, 10:42</span><span>Project handoff</span></div></div>
          <div className="message-copy">Everything is ready for Thursday. I added the final notes and moved the open questions to the top so we can make the decisions quickly.<br /><br />No need to prepare anything else. See you then.</div>
        </article>
        <ReplyComposer name="Ava Patel" replyText={replyText} sendActive={activeKey === "send"} sent={replySent} showCaret={showCaret} />
      </div>
    </section>
  </>
);

const FirstContact = ({
  activeKey,
  replyOpen = false,
  replyProgress = 1,
  replyText = "",
  showCaret = false,
}: {
  activeKey: ActiveKey;
  replyOpen?: boolean;
  replyProgress?: number;
  replyText?: string;
  showCaret?: boolean;
}) => (
  <>
    <ReaderHeader activeKey={activeKey} kind="first-contact" />
    <section className="reader-area">
      <div className="conversation first-contact-conversation">
        <article className="expanded-message first-contact-message">
          <div className="message-meta"><div><strong>Northwind</strong><span>From orders@northwind.example</span><span>to you@example.com</span></div><div><span>Today, 9:18</span><span>Your order shipped</span></div></div>
          <div className="message-copy">Package 10482 is on its way and is expected Thursday afternoon.<br /><br />Reply here if the delivery details need to change.</div>
        </article>
        {replyOpen ? <ReplyComposer name="Northwind" progress={replyProgress} replyText={replyText} showCaret={showCaret} /> : null}
      </div>
    </section>
  </>
);

const ForwardComposer = ({
  activeKey,
  message,
  progress = 1,
  recipient,
  sent = false,
  showCaret = false,
}: {
  activeKey: ActiveKey;
  message: string;
  progress?: number;
  recipient: string;
  sent?: boolean;
  showCaret?: boolean;
}) => (
  <section
    className="reply-composer forward-composer"
    style={{
      opacity: Math.min(1, Math.max(0, progress)),
      transform: `translateY(${(1 - progress) * 22}px) scale(${0.985 + progress * 0.015})`,
    }}
  >
    <div className="reply-label">Forward message</div>
    <div className="forward-recipient">
      <span>To</span>
      <span className={recipient ? "recipient-pill" : "recipient-placeholder"}>{recipient || "Add recipient…"}</span>
      {showCaret && !message ? <span className="text-caret" /> : null}
    </div>
    <div className={`reply-text${message ? " has-copy" : ""}`}>
      {message || "Add a note…"}
      {showCaret && message ? <span className="text-caret" /> : null}
      <div className="forwarded-card"><strong>Atlas Health</strong><span>Updated policy</span><small>The latest coverage summary is ready to review.</small></div>
    </div>
    <footer className="composer-footer">
      <div className="composer-tools"><Icon name="paperclip" size={16} /><span>Aa</span><span>{sent ? "Message forwarded" : "Draft saved automatically"}</span></div>
      <div className="send-group"><KeyCap active={activeKey === "send"}>⌘ ↵</KeyCap><div className={`send-button enabled${activeKey === "send" ? " pressed" : ""}${sent ? " sent" : ""}`}>{sent ? "Sent" : "Send"}</div></div>
    </footer>
  </section>
);

const AtlasThread = ({
  activeKey,
  forwardMessage = "",
  forwardOpen = false,
  forwardProgress = 1,
  forwardRecipient = "",
  forwardSent = false,
  showCaret = false,
}: {
  activeKey: ActiveKey;
  forwardMessage?: string;
  forwardOpen?: boolean;
  forwardProgress?: number;
  forwardRecipient?: string;
  forwardSent?: boolean;
  showCaret?: boolean;
}) => (
  <>
    <ReaderHeader activeKey={activeKey} kind="atlas" />
    <section className="reader-area">
      <div className="conversation atlas-conversation">
        <article className="expanded-message atlas-message">
          <div className="message-meta"><div><strong>Atlas Health</strong><span>From benefits@atlas.example</span><span>to you@example.com</span></div><div><span>Friday, 3:46 PM</span><span>Updated policy</span></div></div>
          <div className="message-copy">The updated coverage summary is ready. The key changes and enrollment dates are highlighted on the first page.<br /><br />Review the attached policy before Friday.</div>
        </article>
        {forwardOpen ? (
          <ForwardComposer
            activeKey={activeKey}
            message={forwardMessage}
            progress={forwardProgress}
            recipient={forwardRecipient}
            sent={forwardSent}
            showCaret={showCaret}
          />
        ) : null}
      </div>
    </section>
  </>
);

const CommandAction = ({ icon, shortcut, subtitle, title, selected = false }: {
  icon: React.ComponentProps<typeof Icon>["name"];
  shortcut?: string;
  subtitle?: string;
  title: string;
  selected?: boolean;
}) => (
  <div className={`command-row${selected ? " selected" : ""}`}>
    <Icon name={icon} size={16} />
    <div><span>{title}</span>{selected && subtitle ? <small>{subtitle}</small> : null}</div>
    {shortcut ? <KeyCap dark={selected}>{shortcut}</KeyCap> : <span />}
  </div>
);

const CommandPalette = ({ progress = 1, query = "", showCaret = false }: { progress?: number; query?: string; showCaret?: boolean }) => {
  const hasQuery = query.length > 0;
  const isReminderQuery = query.toLowerCase().startsWith("r");
  return (
    <div className="command-scrim">
      <section
        className="command-modal"
        style={{
          opacity: Math.min(1, Math.max(0, progress)),
          transform: `translateY(${(1 - progress) * 24}px) scale(${0.94 + progress * 0.06})`,
        }}
      >
        <div className="command-search"><Icon name="search" size={17} /><span className={hasQuery ? "" : "command-search-placeholder"}>{query || "Search mail or run a command…"}</span>{showCaret ? <span className="text-caret" /> : null}</div>
        <div className="command-results">
          {hasQuery && isReminderQuery ? (
            <>
              <div className="command-label">Actions</div>
              <CommandAction icon="clock" subtitle="Hide this conversation until a chosen time" title="Remind me…" selected />
            </>
          ) : hasQuery ? (
            <>
              <div className="command-label">Mail</div>
              <div className="mail-result selected">
                <Icon name="inbox" size={15} />
                <div><span><strong>Atlas Health</strong><em>Updated policy</em></span><small>The latest coverage summary is ready to review.</small></div>
                <time>Fri</time>
              </div>
            </>
          ) : (
            <>
              <div className="command-label">Actions</div>
              <CommandAction icon="compose" shortcut="C" subtitle="Start a new email" title="Compose message" selected />
              <CommandAction icon="search" shortcut="/" title="Search mail" />
              <CommandAction icon="clock" title="Schedule send" />
              <CommandAction icon="signature" shortcut="S" title="Set signatures" />
              <CommandAction icon="archive" shortcut="E" title="Archive current" />
              <CommandAction icon="clock" title="Remind me…" />
            </>
          )}
        </div>
        <footer className="command-footer"><span><KeyCap>↑</KeyCap> <KeyCap>↓</KeyCap> Select &nbsp; <KeyCap>↵</KeyCap> Run</span><span><KeyCap>Esc</KeyCap> Close</span></footer>
      </section>
    </div>
  );
};

const ReminderPicker = ({ activeKey, progress = 1 }: { activeKey: ActiveKey; progress?: number }) => (
  <div className="command-scrim">
    <section
      className="reminder-modal"
      style={{
        opacity: Math.min(1, Math.max(0, progress)),
        transform: `translateY(${(1 - progress) * 18}px) scale(${0.96 + progress * 0.04})`,
      }}
    >
      <header className="reminder-header">
        <span className="reminder-icon"><Icon name="clock" size={17} /></span>
        <div><strong>Remind me</strong><span>Bring this conversation back to your inbox.</span></div>
      </header>
      <div className="reminder-options">
        <div className="reminder-option selected"><div><strong>Tomorrow morning</strong><span>Thursday, 9:00 AM</span></div><KeyCap dark active={activeKey === "enter"}>↵</KeyCap></div>
        <div className="reminder-option"><div><strong>Later today</strong><span>6:00 PM</span></div></div>
        <div className="reminder-option"><div><strong>Tomorrow afternoon</strong><span>Thursday, 1:00 PM</span></div></div>
        <div className="reminder-option"><div><strong>Next Monday</strong><span>9:00 AM</span></div></div>
      </div>
      <footer className="reminder-footer"><span><KeyCap>↑</KeyCap> <KeyCap>↓</KeyCap> Select</span><span><KeyCap>Esc</KeyCap> Cancel</span></footer>
    </section>
  </div>
);

export const MailWindow: React.FC<MailWindowProps> = ({
  activeKey = null,
  cleanupToast = "",
  commandBaseMode = "thread",
  commandProgress = 1,
  commandQuery = "",
  firstContactReplyOpen = false,
  firstContactReplyProgress = 1,
  forwardMessage = "",
  forwardOpen = false,
  forwardProgress = 1,
  forwardRecipient = "",
  forwardSent = false,
  inboxZeroProgress = 1,
  mode,
  removedCount = 0,
  replySent = false,
  replyText = "",
  selectedIndex = 0,
  showCaret = false,
  style,
  threadProgress = 1,
}) => {
  const baseMode = mode === "command" || mode === "reminder" ? commandBaseMode : mode;
  return (
    <section className="mail-frame" style={style}>
      <div className="mail-workspace">
        <Sidebar activeKey={activeKey} inboxCount={Math.max(0, 3 - removedCount)} />
        <main className={`mail-main ${baseMode === "thread" || baseMode === "first-contact" || baseMode === "atlas" ? "reader-mode" : ""}`}>
          {baseMode === "thread" ? <Thread activeKey={activeKey} progress={threadProgress} replySent={replySent} replyText={replyText} showCaret={showCaret} /> : null}
          {baseMode === "first-contact" ? <FirstContact activeKey={activeKey} replyOpen={firstContactReplyOpen} replyProgress={firstContactReplyProgress} replyText={replyText} showCaret={showCaret} /> : null}
          {baseMode === "atlas" ? <AtlasThread activeKey={activeKey} forwardMessage={forwardMessage} forwardOpen={forwardOpen} forwardProgress={forwardProgress} forwardRecipient={forwardRecipient} forwardSent={forwardSent} showCaret={showCaret} /> : null}
          {baseMode === "inbox" ? <Inbox activeKey={activeKey} cleanupToast={cleanupToast} inboxZeroProgress={inboxZeroProgress} removedCount={removedCount} selectedIndex={selectedIndex} /> : null}
        </main>
      </div>
      {mode === "command" ? <CommandPalette progress={commandProgress} query={commandQuery} showCaret={showCaret} /> : null}
      {mode === "reminder" ? <ReminderPicker activeKey={activeKey} progress={commandProgress} /> : null}
    </section>
  );
};
