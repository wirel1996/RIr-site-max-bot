import { api } from './client'

export type BillingMatch = {
  row: number
  name: string
  address: string
}

export type BillingStatusFilter = 'all' | 'active' | 'inactive'

export type BillingObject = {
  row: number
  sheet: string
  status: string
  contract_name: string
  contract_number: string
  street: string
  house_number: string
  purpose: string
  purpose_2: string
  name: string
  address: string
  reconciliation_date: string
  commissioned: string
  poverka_next: string
  serial: string
  final_date: string
  final_value: string
  current_date: string
  current_value: string
  volume_gvs: string
  seal_number: string
  seal_date: string
  meter_type: string
}

export type BillingListResponse = {
  sheet: string | null
  page: number
  page_size: number
  total: number
  records: BillingObject[]
}

export type BillingSheet = {
  id: number
  name: string
  current: boolean
}

export const billingApi = {
  list: (page = 0, query = '', pageSize = 50, status: BillingStatusFilter = 'active') => {
    const params = new URLSearchParams({ page: String(page), page_size: String(pageSize), status })
    if (query.trim()) params.set('q', query.trim())
    return api.get<BillingListResponse>(`/billing/objects?${params.toString()}`)
  },
  search: (query: string) =>
    api.get<{ query: string; records: BillingMatch[] }>(`/billing/search?q=${encodeURIComponent(query)}`),
  object: (row: number) => api.get<BillingObject>(`/billing/object/${row}`),
  saveReading: (row: number, value: string, date: string) =>
    api.patch<{ ok: true }>(`/billing/object/${row}/reading`, { value, date }),
  updateObject: (row: number, payload: Partial<BillingObject>) =>
    api.patch<BillingObject>(`/billing/object/${row}`, payload),
  createObject: (payload: Partial<BillingObject>) =>
    api.post<BillingObject>('/billing/object', payload),
  sheets: () => api.get<{ sheets: BillingSheet[] }>('/billing/sheets'),
  setCurrentSheet: (sheetId: number) => api.patch<{ sheet: BillingSheet }>('/billing/current-sheet', { sheet_id: sheetId }),
  createNextMonth: () => api.post<{ ok: true; sheet: string }>('/billing/next-month'),
  deleteSheet: (sheetId: number) => api.delete<{ ok: true; deleted: string }>(`/billing/sheet/${sheetId}`),
}
