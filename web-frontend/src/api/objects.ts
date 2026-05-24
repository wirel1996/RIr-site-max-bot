import { api } from './client'

export type ObjectRecord = { id: number; name: string | null; address: string | null; identifier: string | null }

export type ObjectSwitchEvent = {
  id: number
  object_id: number
  kind: 'disconnect' | 'connect'
  act_number: string | null
  event_date: string | null
  place: string | null
  seal_numbers: string[]
  actor_name: string | null
  created_at: number
  updated_at: number
}

export type ObjectDetail = {
  object: ObjectRecord
  contacts: Array<{ id: number; category: string; name: string | null; address: string | null; identifier: string | null }>
  uute: Array<{ id: number; category: string | null; name: string | null; address: string | null; identifier: string | null }>
  water: Array<{
    id: number
    gspo_name: string | null
    standalone_address: string | null
    identifier: string | null
    third_party_disconnection: string | null
    third_party_disconnection_note: string | null
  }>
  switch_events: ObjectSwitchEvent[]
}

export type ObjectSwitchEventPayload = {
  kind: 'disconnect' | 'connect'
  event_date: string
  place?: string
  seal_numbers?: string[]
  actor_name?: string
}

export type ObjectSwitchExportMode = 'full' | 'disconnect' | 'connect'

export type SwitchActAuthor = { login: string; name: string }

export const objectsApi = {
  categories: () => api.get<{ categories: Array<{ key: string; label: string }> }>('/objects/categories'),
  switchActAuthors: () => api.get<{ authors: SwitchActAuthor[] }>('/objects/switch-act-authors'),
  list: (category: string, query = '') =>
    api.get<{ category: string; records: ObjectRecord[] }>(`/objects/${category}?q=${encodeURIComponent(query)}`),
  detail: (category: string, id: number) => api.get<ObjectDetail>(`/objects/${category}/${id}`),
  createSwitchEvent: (category: string, id: number, data: ObjectSwitchEventPayload) =>
    api.post<ObjectSwitchEvent>(`/objects/${category}/${id}/switch-events`, data),
  switchEventsExportUrl: (category: string, mode: ObjectSwitchExportMode = 'full') =>
    `/api/objects/${encodeURIComponent(category)}/export-switch-events?mode=${mode}`,
}
