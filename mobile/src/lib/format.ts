/** 'Smith, John' → 'John Smith'. */
export function formatName(raw: string) {
  if (raw.includes(',')) {
    const parts = raw.split(',');
    if (parts.length >= 2) return `${parts[1].trim()} ${parts[0].trim()}`;
  }
  return raw;
}

/** 'Smith, John' → 'JS'. Falls back to '?' for an empty name. */
export function initialsFor(raw: string) {
  const parts = formatName(raw).split(' ').filter((p) => p.length > 0);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return parts.length > 0 ? parts[0][0].toUpperCase() : '?';
}

const shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const longMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** May 3. */
export const formatShortMeetDate = (d: Date) => `${shortMonths[d.getMonth()]} ${d.getDate()}`;

/** May 2026. */
export const monthLabel = (d: Date) => `${longMonths[d.getMonth()]} ${d.getFullYear()}`;

/** '2026-05-03' → "May '26". */
export function formatChartShortDate(date: string) {
  const m = /^(\d{4})-(\d{2})/.exec(date);
  return m ? `${shortMonths[Number(m[2]) - 1]} '${m[1].slice(2)}` : date;
}

/** '2026-05-03' → 'May 3, 2026'. */
export function formatChartFullDate(date: string) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(date);
  return m ? `${shortMonths[Number(m[2]) - 1]} ${Number(m[3])}, ${m[1]}` : date;
}
