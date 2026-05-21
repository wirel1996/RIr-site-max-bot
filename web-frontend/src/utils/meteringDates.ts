export function parseRuDate(value: string | null | undefined): Date | null {
  const text = String(value ?? '').trim()
  if (!text) return null
  const m = text.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/)
  if (!m) return null
  const d = new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1]))
  return Number.isNaN(d.getTime()) ? null : d
}

export function formatRuDate(date: Date): string {
  const dd = String(date.getDate()).padStart(2, '0')
  const mm = String(date.getMonth() + 1).padStart(2, '0')
  const yyyy = date.getFullYear()
  return `${dd}.${mm}.${yyyy}`
}

export function todayRu(): string {
  return formatRuDate(new Date())
}

export function formatDurationDays(totalDays: number): string {
  if (totalDays <= 0) return '0 дн.'
  const years = Math.floor(totalDays / 365)
  const rem = totalDays % 365
  const months = Math.floor(rem / 30)
  const days = rem % 30
  const parts: string[] = []
  if (years > 0) parts.push(`${years} г.`)
  if (months > 0) parts.push(`${months} мес.`)
  if (days > 0 || parts.length === 0) parts.push(`${days} дн.`)
  return parts.join(' ')
}

export function exploitationPeriodLabel(
  dateInput: string | null | undefined,
  dateOutput: string | null | undefined,
  untilNowLabel: string,
): string | null {
  const start = parseRuDate(dateInput)
  if (!start) return null
  const end = parseRuDate(dateOutput) ?? new Date()
  if (end < start) return null
  const days = Math.floor((end.getTime() - start.getTime()) / 86_400_000)
  const suffix = dateOutput?.trim() ? '' : ` (${untilNowLabel})`
  return `${formatDurationDays(days)}${suffix}`
}
