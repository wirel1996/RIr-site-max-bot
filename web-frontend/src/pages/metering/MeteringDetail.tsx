import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState, type FormEvent } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import AdmissionActModal from '../../components/AdmissionActModal'
import ArshinMeterCheckModal, { type ArshinMeterDevice } from '../../components/ArshinMeterCheckModal'
import MeteringBlockHistory, { collectBlockAuditFields } from '../../components/MeteringBlockHistory'
import { ARSHIN_METER_DEVICES, hasFailedArshinCheck } from '../../components/arshinMeterDevices'
import { arshinApi, type ArshinItem } from '../../api/arshin'
import { meteringApi, type MeteringRecord } from '../../api/metering'
import { getPreferredMitNotation } from '../../utils/arshinTypePrefs'
import { meteringRu as t } from '../../locales/ru/metering'
import RegistryObjectCard from '../../components/RegistryObjectCard'
import { exploitationPeriodLabel } from '../../utils/meteringDates'
import {
  SEAL_CUT_KEYS,
  buildFlowmeterSealSlots,
  buildTempSealSlots,
} from '../../utils/meteringSeals'

const GROUPS: Array<[string, Array<[keyof MeteringRecord, string]>]> = t.detail.groups
const OBJECT_FIELDS = new Set<keyof MeteringRecord>(['name', 'address', 'identifier'])
const ACT_MODAL_SECTIONS = new Set(['Акты и допуск', 'Пломбы', 'Показания'])

const CATEGORY_LABELS: Record<string, string> = {
  gspo: 'ГСПО',
  phys: 'Прочие ФЛ',
  legal: 'Прочие ЮЛ',
  budget: 'Бюджет',
  iglakovo: 'Иглаково (коттеджи)',
  embedded: 'Встроенные помещения',
  bu2: 'БУ-2',
  uk_tsj: 'УК и ТСЖ',
}

type DisplayFieldRow = [string, string]

function fieldValue(data: MeteringRecord, key: string): string | null | undefined {
  if (key.startsWith('extra_seal_flowmeter_')) {
    return data.extra_seals?.flowmeter[key.replace('extra_seal_flowmeter_', '')] ?? null
  }
  if (key.startsWith('extra_seal_temp_')) {
    return data.extra_seals?.temp_sensor[key.replace('extra_seal_temp_', '')] ?? null
  }
  return data[key as keyof MeteringRecord] as string | null | undefined
}

function buildDisplayFields(
  title: string,
  fields: Array<[keyof MeteringRecord, string]>,
  data: MeteringRecord,
): DisplayFieldRow[] {
  if (title !== 'Пломбы') return fields

  const base = fields.filter(([key]) => {
    if (key.startsWith('seal_flowmeter_') || key.startsWith('seal_temp_sensor_')) return false
    return true
  })

  const flowSlots = buildFlowmeterSealSlots(data, Object.keys(data.extra_seals?.flowmeter ?? {}).map(Number))
  const tempSlots = buildTempSealSlots(data, Object.keys(data.extra_seals?.temp_sensor ?? {}).map(Number))

  const dynamic: DisplayFieldRow[] = []
  const calcIdx = base.findIndex(([k]) => k === 'seal_calculator')
  const insertAt = calcIdx >= 0 ? calcIdx + 1 : 0

  flowSlots.forEach((slot) => {
    if (slot.fromExtra) {
      dynamic.push([`extra_seal_flowmeter_${slot.index}`, slot.label])
    } else if (slot.fieldKey) {
      const existing = fields.find(([k]) => k === slot.fieldKey)
      if (existing) dynamic.push(existing)
    }
  })
  tempSlots.forEach((slot) => {
    if (slot.fromExtra) {
      dynamic.push([`extra_seal_temp_${slot.index}`, slot.label])
    } else if (slot.fieldKey) {
      const existing = fields.find(([k]) => k === slot.fieldKey)
      if (existing) dynamic.push(existing)
    }
  })

  const before = base.slice(0, insertAt)
  const after = base.slice(insertAt)
  return [...before, ...dynamic, ...after]
}

export default function MeteringDetail() {
  const { category, id } = useParams<{ category: string; id: string }>()
  const cat = category ?? 'gspo'
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [selectedContactId, setSelectedContactId] = useState('')
  const [editingGroup, setEditingGroup] = useState<string | null>(null)
  const [form, setForm] = useState<Partial<Record<keyof MeteringRecord, string>>>({})
  const [arshinDevice, setArshinDevice] = useState<ArshinMeterDevice | null>(null)
  const [arshinInitialSearch, setArshinInitialSearch] = useState<{
    serial?: string
    text: string
    items: ArshinItem[]
    used_preferred_type?: boolean
  } | null>(null)
  const [bulkResults, setBulkResults] = useState<Array<{
    serialKey: ArshinMeterDevice['serialKey']
    label: string
    serial: string
    count: number
    firstItem?: ArshinItem
    items?: ArshinItem[]
    text?: string
    usedPreferred?: boolean
    applied?: boolean
    error?: string
  }>>([])
  const [bulkMessage, setBulkMessage] = useState('')
  const [actModalOpen, setActModalOpen] = useState(false)

  const revertLastActMutation = useMutation({
    mutationFn: () => meteringApi.revertLastAct(cat, Number(id)),
    onSuccess: (record) => {
      queryClient.setQueryData(['metering', cat, 'detail', id], record)
      queryClient.invalidateQueries({ queryKey: ['metering', cat] })
      queryClient.invalidateQueries({ queryKey: ['metering', cat, 'block-history'] })
    },
  })

  const { data, isLoading, error } = useQuery({
    queryKey: ['metering', cat, 'detail', id],
    queryFn: () => meteringApi.detail(cat, Number(id)),
    enabled: !!id,
  })

  const linksQuery = useQuery({
    queryKey: ['metering', cat, 'links', id],
    queryFn: () => meteringApi.linksForUute(cat, Number(id)),
    enabled: !!id,
  })

  const updateMutation = useMutation({
    mutationFn: (payload: Partial<MeteringRecord>) => meteringApi.update(cat, Number(id), payload),
    onSuccess: (record) => {
      queryClient.setQueryData(['metering', cat, 'detail', id], record)
      queryClient.invalidateQueries({ queryKey: ['metering', cat] })
      setEditingGroup(null)
    },
  })

  const createLinkMutation = useMutation({
    mutationFn: (contactId: number) => meteringApi.createLink(contactId, Number(id)),
    onSuccess: () => {
      setSelectedContactId('')
      queryClient.invalidateQueries({ queryKey: ['metering', cat, 'links', id] })
    },
  })

  const deleteLinkMutation = useMutation({
    mutationFn: (contactId: number) => meteringApi.deleteLink(contactId, Number(id)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['metering', cat, 'links', id] })
    },
  })

  const bulkCheckMutation = useMutation({
    mutationFn: async () => {
      if (!id || !data) return []
      const checks: Array<{
        serialKey: ArshinMeterDevice['serialKey']
        label: string
        serial: string
        count: number
        firstItem?: ArshinItem
        items?: ArshinItem[]
        text?: string
        usedPreferred?: boolean
        error?: string
      }> = []
      for (const device of ARSHIN_METER_DEVICES) {
        const serial = String(data[device.serialKey] ?? '').trim()
        if (!serial) continue
        try {
          const preferred = getPreferredMitNotation(device.serialKey)
          const validUntil = String(data[device.dateKey] ?? '').trim()
          const mitNotationByDevice: Partial<Record<ArshinMeterDevice['serialKey'], keyof typeof data>> = {
            calculator_serial: 'calculator_type',
            flowmeter_serial_1: 'flowmeter_1',
            flowmeter_serial_2: 'flowmeter_2',
            temp_sensor_serial_1: 'temp_sensor_1',
            temp_sensor_serial_2: 'temp_sensor_2',
            pressure_sensor_serial_1: 'pressure_sensor_1',
            pressure_sensor_serial_2: 'pressure_sensor_2',
          }
          const mitNotationField = mitNotationByDevice[device.serialKey]
          const mitNotation = mitNotationField ? String(data[mitNotationField] ?? '').trim() : ''
          const res = await arshinApi.searchMeter({
            serial,
            valid_until: validUntil || undefined,
            serial_key: device.serialKey,
            preferred_mit_notation: preferred || undefined,
            mit_notation: mitNotation || undefined,
            meter_label: device.label,
          })
          checks.push({
            serialKey: device.serialKey,
            label: device.label,
            serial,
            count: Array.isArray(res.items) ? res.items.length : 0,
            firstItem: Array.isArray(res.items) && res.items.length === 1 ? res.items[0] : undefined,
            items: Array.isArray(res.items) ? res.items : [],
            text: res.text,
            usedPreferred: res.used_preferred_type,
          })
        } catch (e) {
          checks.push({
            serialKey: device.serialKey,
            label: device.label,
            serial,
            count: 0,
            error: (e as Error).message || t.detail.searchError,
          })
        }
      }
      return checks
    },
    onSuccess: (items) => setBulkResults(items),
  })

  const bulkApplyMutation = useMutation({
    mutationFn: async () => {
      if (!id) return { applied: 0 }
      let applied = 0
      for (const row of bulkResults) {
        if (row.count !== 1 || !row.firstItem) continue
        await meteringApi.applyArshin(cat, Number(id), {
          serial_key: row.serialKey,
          item: row.firstItem as Record<string, unknown>,
          
        })
        applied += 1
      }
      return { applied }
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['metering', cat, 'detail', id] })
      await queryClient.invalidateQueries({ queryKey: ['metering', cat] })
      setBulkResults((current) => current.map((row) => (
        row.count === 1 && row.firstItem ? { ...row, applied: true } : row
      )))
      setBulkMessage(t.detail.appliedAll)
    },
  })

  const applyOneMutation = useMutation({
    mutationFn: async (row: { serialKey: ArshinMeterDevice['serialKey']; firstItem: ArshinItem }) => {
      if (!id) return
      await meteringApi.applyArshin(cat, Number(id), {
        serial_key: row.serialKey,
        item: row.firstItem as Record<string, unknown>,
        
      })
    },
    onSuccess: async (_data, variables) => {
      await queryClient.invalidateQueries({ queryKey: ['metering', cat, 'detail', id] })
      await queryClient.invalidateQueries({ queryKey: ['metering', cat] })
      setBulkResults((current) => current.map((row) => (
        row.serialKey === variables.serialKey ? { ...row, applied: true } : row
      )))
      setBulkMessage(t.detail.appliedOne)
    },
  })

  useEffect(() => {
    if (!data) return
    const next: Partial<Record<keyof MeteringRecord, string>> = {}
    GROUPS.flatMap(([, fields]) => fields).forEach(([key]) => {
      next[key] = data[key] === null || data[key] === undefined ? '' : String(data[key])
    })
    setForm(next)
  }, [data])

  if (isLoading) return <div className="text-gray-500">{t.detail.loading}</div>
  if (error || !data) return <div className="text-red-700">{t.detail.notFoundRecord}</div>

  const editableFields = GROUPS.flatMap(([, fields]) => fields)

  const resetForm = () => {
    const next: Partial<Record<keyof MeteringRecord, string>> = {}
    editableFields.forEach(([key]) => {
      next[key] = data[key] === null || data[key] === undefined ? '' : String(data[key])
    })
    setForm(next)
  }

  const onSubmitGroup = (event: FormEvent, title: string, fields: Array<[keyof MeteringRecord, string]>) => {
    event.preventDefault()
    if (editingGroup !== title) return
    const payload = fields.reduce((acc, [key]) => {
      if (OBJECT_FIELDS.has(key)) return acc
      return { ...acc, [key]: form[key] ?? '' }
    }, {} as Partial<MeteringRecord>)
    updateMutation.mutate(payload)
  }

  return (
    <div className="space-y-4">
      <nav className="flex items-center justify-between text-sm">
        <Link to={`/metering/${cat}`} className="text-blue-600 hover:underline">
          ← {CATEGORY_LABELS[cat] || cat}
        </Link>
        <button
          type="button"
          onClick={() => navigate(-1)}
          className="rounded border bg-white px-3 py-1.5 text-gray-700 hover:bg-gray-100"
        >
          {t.detail.back}
        </button>
      </nav>

      <div className={`rounded-lg bg-white p-5 shadow ${hasFailedArshinCheck(data) ? 'ring-2 ring-red-400' : ''}`}>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-xs uppercase text-gray-500">{CATEGORY_LABELS[cat] || cat}</p>
            <h1 className="text-xl font-bold">{data.name || t.detail.noName}</h1>
            <p className="mt-1 text-sm text-gray-600">{data.address}</p>
            {hasFailedArshinCheck(data) && (
              <p className="mt-2 text-sm font-medium text-red-700">{t.detail.arshinWarn}</p>
            )}
          </div>
          {id && (
            <div className="flex shrink-0 flex-wrap items-center gap-2">
              <button
                type="button"
                onClick={() => setActModalOpen(true)}
                className="rounded border border-emerald-200 bg-emerald-50 px-3 py-1.5 text-sm text-emerald-800 hover:bg-emerald-100"
              >
                {t.detail.enterAct}
              </button>
              <a
                href={meteringApi.admissionActUrl(cat, Number(id))}
                className="rounded border border-blue-200 bg-blue-50 px-3 py-1.5 text-sm text-blue-800 hover:bg-blue-100"
              >
                {t.detail.downloadAct}
              </a>
              <button
                type="button"
                disabled={revertLastActMutation.isPending}
                onClick={() => {
                  if (!window.confirm(t.detail.revertLastActConfirm)) return
                  revertLastActMutation.mutate()
                }}
                className="rounded border border-amber-200 bg-amber-50 px-3 py-1.5 text-sm text-amber-900 hover:bg-amber-100 disabled:opacity-50"
              >
                {revertLastActMutation.isPending ? t.detail.saving : t.detail.revertLastAct}
              </button>
            </div>
          )}
          {revertLastActMutation.error && (
            <p className="mt-2 text-sm text-red-700">
              {t.detail.revertLastActFailed}: {(revertLastActMutation.error as Error).message}
            </p>
          )}
        </div>
      </div>

      <RegistryObjectCard
        objectId={data.object_id}
        invalidateKeys={[
          ['metering', cat, 'detail', id],
          ['metering', cat],
          ['metering', cat, 'links', id],
        ]}
      />

      <section className="rounded-lg bg-white p-5 shadow">
        <h2 className="mb-3 font-semibold">{t.detail.contacts}</h2>
        {linksQuery.isLoading && <p className="text-sm text-gray-500">{t.detail.linksLoading}</p>}
        {linksQuery.data?.links.length === 0 && (
          <p className="text-sm text-gray-500">{t.detail.noLinks}</p>
        )}
        <div className="space-y-2">
          {linksQuery.data?.links.map(({ link, contact }) => (
            <div key={link.id} className="flex flex-col gap-2 rounded border bg-gray-50 p-3 text-sm sm:flex-row sm:items-center sm:justify-between">
              <div>
                <Link to={`/contacts/${contact.id}`} className="font-medium text-blue-700 hover:underline">
                  {contact.name || contact.consumer || t.detail.contacts}
                </Link>
                <p className="text-gray-600">{contact.address || '-'}</p>
                <p className="text-xs text-gray-500">
                  {link.status} · {link.match_score ?? '—'} · {link.match_reason || t.detail.manualLink}
                </p>
              </div>
              <button
                type="button"
                onClick={() => deleteLinkMutation.mutate(contact.id)}
                className="w-fit rounded border border-red-200 bg-white px-3 py-1.5 text-red-700 hover:bg-red-50"
              >
                {t.detail.unlink}
              </button>
            </div>
          ))}
        </div>

        {linksQuery.data && linksQuery.data.candidates.length > 0 && (
          <div className="mt-4 flex flex-col gap-2 sm:flex-row">
            <select
              value={selectedContactId}
              onChange={(event) => setSelectedContactId(event.target.value)}
              className="min-w-0 flex-1 rounded border bg-white px-3 py-2 text-sm"
            >
              <option value="">{t.detail.selectContact}</option>
              {linksQuery.data.candidates.map((candidate) => candidate.contact && (
                <option key={candidate.contact.id} value={candidate.contact.id}>
                  {candidate.score} В· {candidate.contact.name || candidate.contact.consumer} В· {candidate.contact.address}
                </option>
              ))}
            </select>
            <button
              type="button"
              disabled={!selectedContactId || createLinkMutation.isPending}
              onClick={() => createLinkMutation.mutate(Number(selectedContactId))}
              className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
            >
              {t.detail.link}
            </button>
          </div>
        )}
      </section>

      {GROUPS.map(([title, fields]) => {
        const isGroupEditing = editingGroup === title
        const isDevicesSection = fields.some(([key]) => key === 'calculator_serial')
        const isActsSection = fields.some(([key]) => key === 'commercial_accounting')
        const isActModalSection = ACT_MODAL_SECTIONS.has(title)
        const displayFields = buildDisplayFields(title, fields, data)
        const periodLabel = isActsSection
          ? (data.exploitation_period
            ?? exploitationPeriodLabel(
              data.date_input_uute,
              data.date_output_uute,
              t.detail.exploitationUntilNow,
            ))
          : null
        const blockHistoryFields = collectBlockAuditFields(
          fields.map(([k, l]) => [String(k), l]),
          displayFields,
        )
        return (
        <section key={title} className="rounded-lg bg-white p-5 shadow">
          <form onSubmit={(event) => onSubmitGroup(event, title, fields)}>
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="font-semibold">{title}</h2>
            <div className="flex items-center gap-2">
              {!isGroupEditing && id && (
                <MeteringBlockHistory
                  category={cat}
                  recordId={Number(id)}
                  blockTitle={title}
                  fields={blockHistoryFields}
                />
              )}
              {isGroupEditing ? (
                <>
                  <button
                    type="submit"
                    disabled={updateMutation.isPending}
                    className="rounded bg-blue-600 px-2.5 py-1 text-xs text-white hover:bg-blue-700 disabled:opacity-50"
                  >
                    {updateMutation.isPending ? t.detail.saving : t.detail.save}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      resetForm()
                      setEditingGroup(null)
                    }}
                    className="rounded border bg-white px-2.5 py-1 text-xs text-gray-700 hover:bg-gray-100"
                  >
                    {t.detail.cancel}
                  </button>
                </>
              ) : !isActModalSection ? (
                <button
                  type="button"
                  onClick={() => setEditingGroup(title)}
                  className="rounded border bg-white px-2.5 py-1 text-xs text-gray-700 hover:bg-gray-100"
                >
                  {t.detail.edit}
                </button>
              ) : null}
              {isDevicesSection && !isGroupEditing && (
                <>
                  <button
                    type="button"
                    onClick={() => bulkCheckMutation.mutate()}
                    disabled={bulkCheckMutation.isPending || bulkApplyMutation.isPending}
                    className="rounded border border-blue-200 bg-blue-50 px-2.5 py-1 text-xs text-blue-800 hover:bg-blue-100 disabled:opacity-50"
                  >
                    {bulkCheckMutation.isPending ? t.detail.checking : t.detail.checkAll}
                  </button>
                  <button
                    type="button"
                    onClick={() => bulkApplyMutation.mutate()}
                    disabled={bulkApplyMutation.isPending || bulkResults.filter((r) => r.count === 1 && r.firstItem).length === 0}
                    className="rounded border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-xs text-emerald-800 hover:bg-emerald-100 disabled:opacity-50"
                  >
                    {bulkApplyMutation.isPending ? t.detail.saving : t.detail.confirmSave}
                  </button>
                </>
              )}
            </div>
          </div>
          {isDevicesSection && bulkResults.length > 0 && (
            <div className="mb-3 rounded border bg-gray-50 p-3 text-sm">
              {bulkMessage && (
                <div className="mb-2 rounded border border-emerald-200 bg-emerald-50 px-2 py-1 text-emerald-800">
                  {bulkMessage}
                </div>
              )}
              <div className="space-y-1">
                {bulkResults.map((row) => {
                  const device = ARSHIN_METER_DEVICES.find((d) => d.serialKey === row.serialKey)
                  return (
                    <div key={String(row.serialKey)} className="flex items-center justify-between gap-2">
                      <span>
                        {row.label} ({row.serial}):{' '}
                        {row.error
                          ? `error (${row.error})`
                          : row.count === 0
                            ? t.detail.notFound
                            : row.count === 1
                              ? t.detail.foundOne
                              : t.detail.foundMany(row.count)}
                      </span>
                      <div className="flex items-center gap-2">
                        {row.count === 1 && row.firstItem && (
                          <button
                            type="button"
                            onClick={() => applyOneMutation.mutate({ serialKey: row.serialKey, firstItem: row.firstItem! })}
                            disabled={applyOneMutation.isPending || row.applied}
                            className="rounded border border-emerald-200 bg-white px-2 py-0.5 text-xs text-emerald-700 hover:bg-emerald-50 disabled:opacity-50"
                          >
                            {row.applied ? t.detail.saved : t.detail.confirmSave}
                          </button>
                        )}
                        {row.count > 0 && device && (
                          <button
                            type="button"
                            onClick={() => {
                              setArshinInitialSearch({
                                serial: row.serial,
                                text: row.text || '',
                                items: row.items || [],
                                used_preferred_type: row.usedPreferred,
                              })
                              setArshinDevice(device)
                            }}
                            className="rounded border border-blue-200 bg-white px-2 py-0.5 text-xs text-blue-700 hover:bg-blue-50"
                          >
                            {t.detail.selectManual}
                          </button>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          )}
          <dl className="divide-y divide-gray-100">
            {displayFields.map(([key, label]) => {
              const value = fieldValue(data, key)
              const displayValue = value
              const recordKey = key as keyof MeteringRecord
              const arshinMeter = ARSHIN_METER_DEVICES.find((device) => device.serialKey === recordKey)
              const arshinByDate = ARSHIN_METER_DEVICES.find((device) => device.dateKey === recordKey)
              const arshinCheck = arshinByDate ? data.arshin_checks?.[arshinByDate.serialKey] : undefined
              const arshinMeterCheck = arshinMeter ? data.arshin_checks?.[arshinMeter.serialKey] : undefined
              const showWhenEmpty = key === 'commercial_accounting'
              const alwaysShow = title === 'Пломбы' && SEAL_CUT_KEYS.includes(key as typeof SEAL_CUT_KEYS[number])
              if (
                !isGroupEditing
                && !showWhenEmpty
                && !alwaysShow
                && !arshinCheck
                && (displayValue === null || displayValue === undefined || String(displayValue).trim() === '')
              ) return null
              if (isActsSection && key === 'date_input_uute' && periodLabel) {
                return (
                  <>
                    <div key={key} className="py-2 sm:flex sm:gap-4">
                      <dt className="font-medium text-gray-600 sm:w-64 shrink-0">{label}</dt>
                      <dd className="mt-1 flex flex-1 flex-col gap-1 sm:mt-0">
                        <div className="flex items-start justify-between gap-2">
                          <span className="whitespace-pre-line">{displayValue ? String(displayValue) : '-'}</span>
                        </div>
                      </dd>
                    </div>
                    <div key="exploitation-between" className="py-2 sm:flex sm:gap-4">
                      <dt className="font-medium text-gray-600 sm:w-64 shrink-0">{t.detail.exploitationPeriod}</dt>
                      <dd className="mt-1 text-sm text-gray-700 sm:mt-0">{periodLabel}</dd>
                    </div>
                  </>
                )
              }
              return (
                <div
                  key={key}
                  className={`py-2 sm:flex sm:gap-4 ${arshinCheck && arshinCheck.applicability === false ? 'rounded bg-red-50/80 px-2' : ''}`}
                >
                  <dt className="font-medium text-gray-600 sm:w-64 shrink-0">{label}</dt>
                  <dd className="mt-1 flex flex-1 flex-col gap-1 sm:mt-0">
                    <div className="flex items-start justify-between gap-2">
                      {isGroupEditing && !OBJECT_FIELDS.has(recordKey) ? (
                        recordKey === 'nearest_verification_date' ? (
                          <span className="whitespace-pre-line">{value ? String(value) : '-'}</span>
                        ) :
                        recordKey === 'commercial_accounting' ? (
                          <select
                            value={form[recordKey] ?? ''}
                            onChange={(event) => setForm((current) => ({ ...current, [recordKey]: event.target.value }))}
                            className="min-w-[170px] rounded border px-2 py-1 text-sm"
                          >
                            <option value="">-</option>
                            <option value="да">{t.detail.yes}</option>
                            <option value="нет">{t.detail.no}</option>
                          </select>
                        ) : (
                          <input
                            value={form[recordKey] ?? ''}
                            onChange={(event) => setForm((current) => ({ ...current, [recordKey]: event.target.value }))}
                            className="w-full rounded border px-2 py-1 text-sm"
                          />
                        )
                      ) : (
                        <span className="whitespace-pre-line">{displayValue ? String(displayValue) : '-'}</span>
                      )}
                      {arshinMeter && String(data[arshinMeter.serialKey] ?? '').trim() && (
                        <button
                          type="button"
                          onClick={() => setArshinDevice(arshinMeter)}
                          className="shrink-0 rounded border border-blue-200 bg-blue-50 px-2 py-1 text-xs text-blue-800 hover:bg-blue-100"
                        >
                          {t.detail.arshin}
                        </button>
                      )}
                    </div>
                    {arshinCheck && (
                      <p className="text-xs text-gray-600">
                        {t.detail.arshin}:{' '}
                        <span className="font-medium">{arshinCheck.valid_date || '-'}</span>
                        {' В· '}
                        <span className={arshinCheck.applicability ? 'text-emerald-800' : 'font-semibold text-red-800'}>
                          {t.detail.applicability}: {arshinCheck.applicability ? t.detail.yes : t.detail.no}
                        </span>
                      </p>
                    )}
                    {arshinMeterCheck?.registry_url && (
                      <a
                        href={arshinMeterCheck.registry_url}
                        target="_blank"
                        rel="noreferrer"
                        className="text-xs font-medium text-blue-700 hover:underline"
                      >
                        {t.detail.arshinRecord}
                      </a>
                    )}
                  </dd>
                </div>
              )
            })}
          </dl>
          {isGroupEditing && updateMutation.error && (
            <div className="mt-3 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
              {t.detail.failedSave}
            </div>
          )}
          </form>
        </section>
      )})}

      {actModalOpen && id && (
        <AdmissionActModal
          open
          category={cat}
          recordId={Number(id)}
          record={data}
          onClose={() => setActModalOpen(false)}
        />
      )}

      {arshinDevice && id && (
        <ArshinMeterCheckModal
          open
          uuteId={Number(id)}
          device={arshinDevice}
          record={data}
          initialSearch={arshinInitialSearch}
          onClose={() => {
            setArshinDevice(null)
            setArshinInitialSearch(null)
          }}
        />
      )}
    </div>
  )
}

