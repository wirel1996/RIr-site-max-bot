import { api } from './client'

export type ObjectRecord = { id: number; name: string | null; address: string | null; identifier: string | null }

export type ObjectDetail = {
  object: ObjectRecord
  contacts: Array<{ id: number; category: string; name: string | null; address: string | null; identifier: string | null }>
  uute: Array<{ id: number; category: string | null; name: string | null; address: string | null; identifier: string | null }>
  water: Array<{ id: number; gspo_name: string | null; standalone_address: string | null; identifier: string | null }>
}

export const objectsApi = {
  categories: () => api.get<{ categories: Array<{ key: string; label: string }> }>('/objects/categories'),
  list: (category: string, query = '') =>
    api.get<{ category: string; records: ObjectRecord[] }>(`/objects/${category}?q=${encodeURIComponent(query)}`),
  detail: (category: string, id: number) => api.get<ObjectDetail>(`/objects/${category}/${id}`),
}
