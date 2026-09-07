/** Present recognized Gmail reply history without changing stored email or adding frames. */
export function groupReplyCards(doc: Document): boolean {
  const selector = '.gmail_quote > blockquote';
  const quotes = Array.from(doc.body.querySelectorAll(selector));
  // Ambiguous quotations and rich informational mail retain their original layout.
  if (!quotes.length || quotes.length > 100 || quotes.some(quote =>
    !quote.parentElement?.querySelector('.gmail_attr') ||
    !/wrote:\s*$/.test(quote.parentElement.querySelector('.gmail_attr')?.textContent ?? '')
  )) return false;

  const result = doc.createDocumentFragment();
  let content: Element = doc.body;
  let attribution: Element | null = null;
  for (;;) {
    const quote = content.querySelector(selector);
    const wrapper = quote?.parentElement;
    const card = doc.createElement('section');
    card.className = 'personal-reply-card';
    card.setAttribute('aria-label', attribution?.textContent?.trim() || 'Latest message');
    if (attribution) card.append(attribution);
    if (quote && wrapper) {
      wrapper.remove();
      quote.remove();
    }
    card.append(...Array.from(content.childNodes));
    result.append(card);
    if (!quote || !wrapper) break;
    attribution = wrapper;
    attribution.className = 'personal-reply-attribution';
    content = quote;
  }
  // Gmail nests newest to oldest; display the extracted cards oldest first.
  doc.body.replaceChildren(...Array.from(result.childNodes).reverse());
  const style = doc.createElement('style');
  style.textContent = `
    body { background: #f3f4f5; }
    .personal-reply-card { margin: 0 0 12px; padding: 20px; border: 1px solid #e5e5e5; border-radius: 12px; background: #fff; color: #292929; overflow-wrap: anywhere; }
    .personal-reply-card:last-child { margin-bottom: 0; }
    .personal-reply-attribution { margin-bottom: 16px; color: #5d5d5d; font: 12px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; }
  `;
  doc.head.append(style);
  return true;
}
