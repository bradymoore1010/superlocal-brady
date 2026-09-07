export function calendarMinute(y: number, top: number, hourHeight: number): number {
  return Math.max(0, Math.min(1410, Math.floor((y - top) / hourHeight * 2) * 30));
}
export function calendarRange(anchor: number, current: number): { start: number; duration: number } {
  const start = Math.min(anchor, current);
  return { start, duration: anchor === current ? Math.min(60, 1440 - start) : Math.abs(current - anchor) + 30 };
}
