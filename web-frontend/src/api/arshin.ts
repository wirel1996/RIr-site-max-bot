import { api } from './client'
import type { MeteringRecord } from './metering'

export type ArshinItem = {
  vri_id?: string
  id?: string
  mi_number?: string
  mit_notation?: string
  mit_title?: string
  org_title?: string
  verification_date?: string
  valid_date?: string
  result_docnum?: string
  registry_url?: string
  applicability?: boolean | string
  _year?: string
  // any other fields
  [key: string]: unknown
}

export type ArshinForm = {
  org_title: string
  year: string
  mi_number: string
  mit_notation: string
}

export type ArshinSearchResponse = {
  text: string
  items: ArshinItem[]
  year: string
}

export type ArshinMeterSearchRequest = {
  serial: string
  serial_candidates?: string[]
  result_docnum?: string
  valid_until?: string
  year?: string
  org_title?: string
  mit_notation?: string
  preferred_mit_notation?: string
  serial_key?: string
  meter_label?: string
}

export type ArshinMeterApplyRequest = {
  serial_key: string
  item: ArshinItem
}

export type ArshinMeterApplyResponse = {
  record: MeteringRecord
  applicability: boolean
  serial_mismatch?: {
    serial_key: string
    current: string
    found: string
  } | null
}

export type ArshinMeterSearchResponse = ArshinSearchResponse & {
  years_tried: string[]
  suggested_years: string[]
  used_preferred_type: boolean
}

export const arshinApi = {
  options: () => api.get<{ years: string[]; orgs: string[] }>('/arshin/years'),
  search: (form: ArshinForm) => api.post<ArshinSearchResponse>('/arshin/search', form),
  searchMeter: (payload: ArshinMeterSearchRequest) =>
    api.post<ArshinMeterSearchResponse>('/arshin/search-meter', payload),
  applyMeter: (uuteId: number, payload: ArshinMeterApplyRequest) =>
    api.post<ArshinMeterApplyResponse>(`/metering/gspo/${uuteId}/arshin-apply`, payload),
  pdfBlob: async (item: ArshinItem): Promise<Blob> => {
    const res = await fetch('/api/arshin/pdf', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ item }),
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return res.blob()
  },
}
