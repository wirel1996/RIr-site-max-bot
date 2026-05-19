import type { Contact } from '../../api/contacts'

const nonEmpty = (s: string | null | undefined) => (s ?? '').trim().length > 0

export function shortLabel(record: Contact): string {
  const parts: string[] = []
  switch (record.category) {
    case 'gspo':
      if (nonEmpty(record.address)) parts.push(record.address!)
      if (nonEmpty(record.name)) parts.push(record.name!)
      break
    case 'phys':
      if (nonEmpty(record.consumer)) parts.push(record.consumer!)
      if (nonEmpty(record.address)) parts.push(record.address!)
      break
    case 'iglakovo':
      if (nonEmpty(record.name)) parts.push(record.name!)
      if (nonEmpty(record.address)) parts.push(record.address!)
      break
    default:
      if (nonEmpty(record.name)) parts.push(record.name!)
      if (nonEmpty(record.address)) parts.push(record.address!)
  }
  const label = parts.join(' — ')
  return label.length > 100 ? label.slice(0, 97) + '...' : label || `#${record.id}`
}
