import { api } from './client'

export type JournalWeek = {
  start: string  // ISO Monday YYYY-MM-DD
  end: string    // ISO Friday
  label: string
  has_data: boolean
  contains_today: boolean
}

export type JournalDay = {
  date: string
  date_label: string  // DD.MM
  weekday: string     // Пн / Вт / Ср / Чт / Пт
  sheet: string | null
  has_data: boolean
  time_slots: string[]  // фактические слоты дня (Пт обычно без 16:00-17:00)
}

export type WeekValues = Record<string, Record<string, Record<string, string>>>
//   date -> time -> person -> value

export type JournalWeekData = {
  week: { start: string; end: string; label: string; contains_today: boolean }
  days: JournalDay[]
  people: string[]
  time_slots: string[]
  values: WeekValues
  colors: Record<string, string>
}

export type JournalWeekStatus = {
  week_start: string
  cells_revision: number
  latest_event_id: number
}

export type CellColor = {
  date: string
  time: string
  person: string
  color: string
}

export const journalApi = {
  weeks: () => api.get<{ weeks: JournalWeek[] }>('/journal/weeks'),
  weekStatus: (start: string) =>
    api.get<JournalWeekStatus>(`/journal/week-status?start=${encodeURIComponent(start)}`),
  week: (start: string) =>
    api.get<JournalWeekData>(`/journal/week?start=${encodeURIComponent(start)}`),
  search: (q: string, limit = 50) =>
    api.get<{ results: Array<{ week_start: string; week_label: string; date: string; time: string; person: string; value: string }> }>(
      `/journal/search?q=${encodeURIComponent(q)}&limit=${limit}`,
    ),
  writeCell: (date: string, time: string, person: string, value: string, oldValue?: string) =>
    api.patch<{ ok: true }>('/journal/cell', { date, time, person, value, old_value: oldValue ?? '' }),
  writeCellColors: (cells: CellColor[]) =>
    api.patch<{ ok: true; saved: number }>('/journal/cell-color', { cells }),
  createNextWeek: () =>
    api.post<{ ok: true; start: string; sheet: string }>('/journal/next-week'),
  cellAudit: (date: string, time: string, person: string) =>
    api.get<{ log?: { created_at: number; actor_name: string; actor_login: string; new_value: string } }>(
      `/journal/cell-audit?date=${encodeURIComponent(date)}&time=${encodeURIComponent(time)}&person=${encodeURIComponent(person)}`,
    ),
  cellAuditHistory: (date: string, time: string, person: string, limit = 20) =>
    api.get<{ logs: Array<{ created_at: number; actor_name: string; actor_login: string; old_value: string; new_value: string }> }>(
      `/journal/cell-audit-history?date=${encodeURIComponent(date)}&time=${encodeURIComponent(time)}&person=${encodeURIComponent(person)}&limit=${limit}`,
    ),
  addColumn: (start: string, name: string) =>
    api.post<{ ok: true; sheet: string; person: string; exists: boolean }>('/journal/column', { start, name }),
  deleteColumn: (start: string, name: string) =>
    api.deleteData<{ ok: true; sheet: string; person: string }>('/journal/column', { start, name }),
  renameColumns: (start: string, mapping: Record<string, string>) =>
    api.patch<{ ok: true; sheet: string; renamed: Array<{ from: string; to: string }>; skipped: string[] }>(
      '/journal/columns/rename',
      { start, mapping },
    ),
  enableSaturday: (start: string) =>
    api.post<{ ok: true; already_exists: boolean; date: string }>('/journal/enable-saturday', { start }),
}
