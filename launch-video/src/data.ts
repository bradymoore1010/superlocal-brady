export type MailMessage = {
  sender: string;
  email: string;
  subject: string;
  preview: string;
  time: string;
  unread: boolean;
  correspondence: boolean;
};

export const inboxMessages: MailMessage[] = [
  {
    sender: "Ava Patel",
    email: "ava@northwind.example",
    subject: "Project handoff",
    preview: "Everything is ready for Thursday. I added the final notes…",
    time: "10:42",
    unread: true,
    correspondence: true,
  },
  {
    sender: "Northwind",
    email: "orders@northwind.example",
    subject: "Your order shipped",
    preview: "Track package 10482 and view the latest delivery estimate.",
    time: "9:18",
    unread: true,
    correspondence: false,
  },
  {
    sender: "Theo Martin",
    email: "theo@studio.example",
    subject: "Coffee next week",
    preview: "Tuesday at 9 works for me. Want to meet downtown?",
    time: "8:54",
    unread: true,
    correspondence: true,
  },
  {
    sender: "Studio Supply",
    email: "hello@studiosupply.example",
    subject: "September receipt",
    preview: "Your receipt for order 2187 is attached.",
    time: "Yesterday",
    unread: false,
    correspondence: false,
  },
  {
    sender: "Jules Park",
    email: "jules@paper.example",
    subject: "Re: Product notes",
    preview: "The keyboard flow feels right. One thought on the reply field…",
    time: "Yesterday",
    unread: false,
    correspondence: true,
  },
  {
    sender: "Nimbus",
    email: "security@nimbus.example",
    subject: "Security sign-in",
    preview: "A new sign-in was approved from your Mac.",
    time: "Mon",
    unread: false,
    correspondence: false,
  },
  {
    sender: "Paper",
    email: "team@paper.example",
    subject: "Welcome to your workspace",
    preview: "Your first collaborative canvas is ready.",
    time: "Mon",
    unread: false,
    correspondence: false,
  },
  {
    sender: "Atlas Health",
    email: "benefits@atlas.example",
    subject: "Updated policy",
    preview: "The latest coverage summary is ready to review.",
    time: "Fri",
    unread: false,
    correspondence: false,
  },
];
