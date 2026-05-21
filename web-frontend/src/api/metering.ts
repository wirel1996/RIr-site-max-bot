import { api } from './client'

export type MeteringRecord = {
  id: number
  object_id: number | null
  list_number: string | null
  contract_number: string | null
  name: string | null
  address: string | null
  identifier: string | null
  input_kind: string | null
  date_input_uute: string | null
  admit_until: string | null
  date_output_uute: string | null
  output_reason: string | null
  act_primary_number: string | null
  act_periodic_number: string | null
  registration_date: string | null
  violations: string | null
  project: string | null
  verifier: string | null
  documents: string | null
  commercial_accounting: string | null
  heat_load: string | null
  hot_water_load: string | null
  ventilation_load: string | null
  contract_flow: string | null
  distance: string | null
  diameter: string | null
  connection_point_number: string | null
  installation_point: string | null
  calculator_type: string | null
  flowmeter_1: string | null
  flowmeter_2: string | null
  temp_sensor_1: string | null
  temp_sensor_2: string | null
  pressure_sensor_1: string | null
  pressure_sensor_2: string | null
  calculator_serial: string | null
  flowmeter_serial_1: string | null
  flowmeter_serial_2: string | null
  temp_sensor_serial_1: string | null
  temp_sensor_serial_2: string | null
  pressure_sensor_serial_1: string | null
  pressure_sensor_serial_2: string | null
  calculator_verification_date: string | null
  flowmeter_verification_date_1: string | null
  flowmeter_verification_date_2: string | null
  temp_sensor_verification_date_1: string | null
  temp_sensor_verification_date_2: string | null
  pressure_sensor_verification_date_1: string | null
  pressure_sensor_verification_date_2: string | null
  nearest_verification_date: string | null
  seal_calculator: string | null
  seal_flowmeter_1: string | null
  seal_flowmeter_2: string | null
  seal_flowmeter_3: string | null
  seal_flowmeter_4: string | null
  seal_temp_sensor_1: string | null
  seal_temp_sensor_2: string | null
  seal_temp_sensor_3: string | null
  seal_temp_sensor_4: string | null
  seal_cut_1: string | null
  seal_cut_2: string | null
  seal_cut_3: string | null
  seal_cut_4: string | null
  seal_cut_5: string | null
  seal_cut_6: string | null
  seals_checked: string | null
  system_type: string | null
  service_org: string | null
  readings_date: string | null
  reading_q: string | null
  reading_m1: string | null
  reading_v1: string | null
  reading_m2: string | null
  reading_v2: string | null
  reading_t1: string | null
  reading_t2: string | null
  reading_p1: string | null
  reading_p2: string | null
  accepted_by: string | null
  check_date: string | null
  check_violations: string | null
  check_note: string | null
  periods?: Array<{ index: number; date1: string; date2: string }>
  extra_seals?: { flowmeter: Record<string, string>; temp_sensor: Record<string, string> }
  exploitation_period?: string | null
  arshin_checks?: Record<string, {
    valid_date?: string
    verification_date?: string
    applicability: boolean
    org_title?: string
    mi_number?: string
    mit_notation?: string
    registry_url?: string
    yadisk_path?: string
    checked_at?: number
  }>
}

export type MeteringListResponse = {
  category: string
  page: number
  page_size: number
  total: number
  query: string
  records: MeteringRecord[]
  last_import: {
    filename: string
    imported_at: number
    added_count: number
    updated_count: number
    skipped_count: number
    total_rows: number
  } | null
}

export type CreateMeteringPayload = {
  object_id: number
  calculator_type?: string
  calculator_serial?: string
  calculator_verification_date?: string
  flowmeter_1?: string
  flowmeter_serial_1?: string
  flowmeter_verification_date_1?: string
  flowmeter_2?: string
  flowmeter_serial_2?: string
  flowmeter_verification_date_2?: string
  flowmeter_3?: string
  flowmeter_serial_3?: string
  flowmeter_verification_date_3?: string
  flowmeter_4?: string
  flowmeter_serial_4?: string
  flowmeter_verification_date_4?: string
  temp_sensor_1?: string
  temp_sensor_serial_1?: string
  temp_sensor_verification_date_1?: string
  temp_sensor_2?: string
  temp_sensor_serial_2?: string
  temp_sensor_verification_date_2?: string
  temp_sensor_3?: string
  temp_sensor_serial_3?: string
  temp_sensor_verification_date_3?: string
  temp_sensor_4?: string
  temp_sensor_serial_4?: string
  temp_sensor_verification_date_4?: string
  pressure_sensor_1?: string
  pressure_sensor_serial_1?: string
  pressure_sensor_verification_date_1?: string
  pressure_sensor_2?: string
  pressure_sensor_serial_2?: string
  pressure_sensor_verification_date_2?: string
  pressure_sensor_3?: string
  pressure_sensor_serial_3?: string
  pressure_sensor_verification_date_3?: string
  pressure_sensor_4?: string
  pressure_sensor_serial_4?: string
  pressure_sensor_verification_date_4?: string
  system_type?: string
  service_org?: string
  connection_point_number?: string
  installation_point?: string
  heat_load?: string
  hot_water_load?: string
  ventilation_load?: string
  contract_flow?: string
  distance?: string
  diameter?: string
  losses_before_uute?: string
  losses_after_uute?: string
}

export type MeteringImportResult = {
  added: number
  updated: number
  unchanged?: number
  skipped: number
  total: number
  updated_examples?: Array<{
    id: number
    source_row: number
    name: string | null
    address: string | null
    identifier: string | null
    changed_fields: string[]
    changes?: Record<string, { before: string; after: string }>
  }>
}

export type WaterRegistryRecord = {
  id: number
  object_id: number | null
  source_row: number | null
  point_number: string | null
  identifier: string | null
  actual_connection_point: string | null
  connected: string | null
  point_filter: string | null
  gspo_count_in_point: string | null
  gspo_name: string | null
  standalone_address: string | null
  leader_name: string | null
  phone: string | null
  metering_presence: string | null
  application: string | null
  application_date: string | null
  no_debt: string | null
  power_of_attorney: string | null
  contract: string | null
  uute: string | null
  uute_verified: string | null
  third_party_disconnection: string | null
  third_party_disconnection_note: string | null
  payment: string | null
  payment_date: string | null
  water_supplied: string | null
  verdict: string | null
  note: string | null
  all_except_payment: string | null
  tf_in_ts: string | null
  tf_in_ts_date: string | null
  connection_act: string | null
  illegal_connection_2025: string | null
  illegal_connection_2026: string | null
  contact_id: number | null
  uute_id: number | null
  uute_verification_until: string | null
  uute_match_note: string | null
  raw?: Record<string, string>
}

export type WaterRegistryListResponse = {
  page: number
  page_size: number
  total: number
  query: string
  point: string
  payment_from: string | null
  payment_to: string | null
  application_from: string | null
  application_to: string | null
  sort: string
  dir: 'asc' | 'desc'
  records: WaterRegistryRecord[]
  last_import: {
    filename: string
    imported_at: number
    added_count: number
    updated_count: number
    skipped_count: number
    total_rows: number
  } | null
}

export type WaterDisconnectionImportResult = {
  filename: string
  sheet: string
  total_gspo_rows: number
  disconnected_rows: number
  matched: number
  unmatched: number
  skipped: number
  unmatched_examples: Array<{ name: string; note: string; source_row: number }>
}

export type MeteringLink = {
  id: number
  uute_id: number
  contact_id: number
  status: string
  match_score: number | null
  match_reason: string | null
}

export type MeteringLinkCandidate = {
  score: number
  reason: string
  uute?: MeteringRecord
  contact?: {
    id: number
    name: string | null
    address: string | null
    consumer: string | null
    phone: string | null
  }
}

export type ContactMeteringLinks = {
  links: Array<{ link: MeteringLink; uute: MeteringRecord }>
  candidates: MeteringLinkCandidate[]
}

export type UuteContactLinks = {
  links: Array<{ link: MeteringLink; contact: NonNullable<MeteringLinkCandidate['contact']> }>
  candidates: MeteringLinkCandidate[]
}

export type MeteringFieldAuditLog = {
  created_at: number
  actor_name: string
  actor_login: string
  field: string
  old_value: string
  new_value: string
}

export type SubmitActPayload = Partial<MeteringRecord> & {
  act_primary_mode?: 'auto' | 'manual' | 'start_from'
  act_periodic_mode?: 'auto' | 'manual' | 'start_from'
  act_primary_start_from?: number
  act_periodic_start_from?: number
  extra_seals?: { flowmeter: Record<string, string>; temp_sensor: Record<string, string> }
  extra_flowmeter_indices?: number[]
  extra_temp_indices?: number[]
}

export const meteringApi = {
  list: (category: string, page = 0, query = '') => {
    const params = new URLSearchParams({ page: String(page) })
    if (query.trim()) params.set('q', query.trim())
    return api.get<MeteringListResponse>(`/metering/${category}?${params.toString()}`)
  },
  listGspo: (page = 0, query = '') => meteringApi.list('gspo', page, query),
  exportUrl: (category: string) => `/api/metering/${category}/export`,
  gspoExportUrl: () => '/api/metering/gspo/export',
  detail: (category: string, id: number) => api.get<MeteringRecord>(`/metering/${category}/${id}`),
  gspoDetail: (id: number) => meteringApi.detail('gspo', id),
  create: (category: string, payload: CreateMeteringPayload) =>
    api.post<MeteringRecord>(`/metering/${category}`, payload),
  admissionActUrl: (category: string, id: number) => `/api/metering/${category}/${id}/admission-act`,
  update: (category: string, id: number, payload: Partial<MeteringRecord>) =>
    api.patch<MeteringRecord>(`/metering/${category}/${id}`, payload),
  submitAct: (category: string, id: number, payload: SubmitActPayload) =>
    api.post<MeteringRecord>(`/metering/${category}/${id}/submit-act`, payload),
  revertLastAct: (category: string, id: number) =>
    api.post<MeteringRecord>(`/metering/${category}/${id}/revert-last-act`, {}),
  fieldHistory: (category: string, id: number, field: string, limit = 20) =>
    api.get<{ logs: MeteringFieldAuditLog[] }>(
      `/metering/${category}/${id}/field-history?field=${encodeURIComponent(field)}&limit=${limit}`,
    ),
  blockHistory: (category: string, id: number, fields: string[], limit = 50) =>
    api.get<{ logs: MeteringFieldAuditLog[] }>(
      `/metering/${category}/${id}/block-history?fields=${fields.map(encodeURIComponent).join(',')}&limit=${limit}`,
    ),
  people: () => api.get<{ people: string[] }>('/metering/people'),
  gspoUpdate: (id: number, payload: Partial<MeteringRecord>) => meteringApi.update('gspo', id, payload),
  applyArshin: (category: string, id: number, payload: { serial_key: string; item: Record<string, unknown> }) =>
    api.post<{ record: MeteringRecord; applicability: boolean }>(
      `/metering/${category}/${id}/arshin-apply`,
      payload,
    ),
  linksForContact: (contactId: number) =>
    api.get<ContactMeteringLinks>(`/contacts/${contactId}/metering-links`),
  waterForContact: (contactId: number) =>
    api.get<{ records: WaterRegistryRecord[] }>(`/contacts/${contactId}/water-registry`),
  linksForUute: (category: string, uuteId: number) =>
    api.get<UuteContactLinks>(`/metering/${category}/${uuteId}/links`),
  gspoLinksForUute: (uuteId: number) => meteringApi.linksForUute('gspo', uuteId),
  createLink: (contactId: number, uuteId: number) =>
    api.post<{ link: MeteringLink }>('/metering/links', { contact_id: contactId, uute_id: uuteId, status: 'manual' }),
  deleteLink: (contactId: number, uuteId: number) =>
    api.deleteData<{ ok: true }>('/metering/links', { contact_id: contactId, uute_id: uuteId }),
  importMetering: (category: string, file: File) => {
    const formData = new FormData()
    formData.append('file', file)
    return api.upload<MeteringImportResult>(`/metering/${category}/import`, formData)
  },
  importGspo: (file: File) => meteringApi.importMetering('gspo', file),
  listWater: (
    page = 0,
    query = '',
    point = '',
    sort = '',
    dir: 'asc' | 'desc' = 'asc',
    paymentFrom = '',
    paymentTo = '',
    applicationFrom = '',
    applicationTo = '',
  ) => {
    const params = new URLSearchParams({ page: String(page) })
    if (query.trim()) params.set('q', query.trim())
    if (point.trim()) params.set('point', point.trim())
    if (paymentFrom.trim()) params.set('payment_from', paymentFrom.trim())
    if (paymentTo.trim()) params.set('payment_to', paymentTo.trim())
    if (applicationFrom.trim()) params.set('application_from', applicationFrom.trim())
    if (applicationTo.trim()) params.set('application_to', applicationTo.trim())
    if (sort.trim()) {
      params.set('sort', sort.trim())
      params.set('dir', dir)
    }
    return api.get<WaterRegistryListResponse>(`/metering/water?${params.toString()}`)
  },
  waterPhoneogramUrl: (paymentFrom = '', paymentTo = '', signer = '') => {
    const params = new URLSearchParams()
    if (paymentFrom.trim()) params.set('payment_from', paymentFrom.trim())
    if (paymentTo.trim()) params.set('payment_to', paymentTo.trim())
    if (signer.trim()) params.set('signer', signer.trim())
    return `/api/metering/water/phoneogram?${params.toString()}`
  },
  waterDetail: (id: number) => api.get<WaterRegistryRecord>(`/metering/water/${id}`),
  createWater: (payload: Partial<WaterRegistryRecord>) =>
    api.post<WaterRegistryRecord>('/metering/water', payload),
  updateWater: (id: number, payload: Partial<WaterRegistryRecord>) =>
    api.patch<WaterRegistryRecord>(`/metering/water/${id}`, payload),
  importWater: (file: File) => {
    const formData = new FormData()
    formData.append('file', file)
    return api.upload<MeteringImportResult>('/metering/water/import', formData)
  },
  importWaterDisconnections: (file: File) => {
    const formData = new FormData()
    formData.append('file', file)
    return api.upload<WaterDisconnectionImportResult>('/metering/water/import-disconnections', formData)
  },
  waterDisconnectedExportUrl: () => '/api/metering/water/disconnected-export',
}
