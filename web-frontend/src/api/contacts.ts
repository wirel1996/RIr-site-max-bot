import { api } from './client'

export type Contact = {
  id: number
  category: ContactCategory
  name: string | null
  connection_point: string | null
  consumer: string | null
  manager: string | null
  address: string | null
  phone: string | null
  phone_alt: string | null
  email: string | null
  postal_address: string | null
  notes: string | null
  identifier: string | null
  metering_presence: string | null
  disconnected: string | null
  sync_status: string | null
  sync_note: string | null
  source_row: number | null
  updated_at: number
}

export type ContactCategory = string

export type CategoryInfo = {
  key: ContactCategory
  label: string
  sort_order?: number
  system?: boolean
  count: number
}

export type ContactCategoryRecord = {
  key: ContactCategory
  label: string
  sort_order: number
  system: boolean
  count?: number
}

export type ContactsOverview = {
  categories: CategoryInfo[]
  last_sync_at: number | null
}

export type ContactsListResponse = {
  category: ContactCategory
  label?: string
  page: number
  page_size: number
  total: number
  query: string
  records: Contact[]
}

export type ContactsSearchResponse = {
  query: string
  records: Contact[]
}

export type ContactUpdatePayload = Partial<
  Pick<Contact, 'name' | 'connection_point' | 'consumer' | 'manager' | 'address' | 'phone' | 'phone_alt' | 'email' | 'postal_address' | 'notes' | 'identifier' | 'metering_presence' | 'disconnected'>
>

export const contactsApi = {
  overview: () => api.get<ContactsOverview>('/contacts/overview'),
  categories: () => api.get<{ categories: ContactCategoryRecord[] }>('/contacts/categories'),
  createCategory: (data: { label: string; key?: string; sort_order?: number }) =>
    api.post<ContactCategoryRecord>('/contacts/categories', data),
  updateCategory: (key: ContactCategory, data: { label?: string; sort_order?: number }) =>
    api.patch<ContactCategoryRecord>(`/contacts/categories/${key}`, data),
  deleteCategory: (key: ContactCategory) =>
    api.delete<{ ok: true; category: ContactCategoryRecord }>(`/contacts/categories/${key}`),
  list: (category: ContactCategory, page = 0, query = '') => {
    const params = new URLSearchParams({ page: String(page) })
    if (query.trim()) params.set('q', query.trim())
    return api.get<ContactsListResponse>(`/contacts/category/${category}?${params.toString()}`)
  },
  create: (category: ContactCategory, data: ContactUpdatePayload) =>
    api.post<Contact>(`/contacts/category/${category}`, data),
  detail: (id: number) => api.get<Contact>(`/contacts/${id}`),
  update: (id: number, data: ContactUpdatePayload) =>
    api.patch<Contact>(`/contacts/${id}`, data),
  delete: (id: number) => api.delete<{ ok: true; record: Contact }>(`/contacts/${id}`),
  search: (query: string) =>
    api.get<ContactsSearchResponse>(`/contacts/search?q=${encodeURIComponent(query)}`),
}
