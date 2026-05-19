import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState, type CSSProperties, type FormEvent, type KeyboardEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { contactsApi, type Contact, type ContactCategory } from '../../api/contacts'
import { meteringApi, type WaterRegistryRecord } from '../../api/metering'
import { useAuth } from '../../contexts/AuthContext'
import { categoryLabel } from '../contacts/contactDisplay'

const EDITABLE_COLUMNS: Array<[keyof WaterRegistryRecord, string, number]> = [
  ['application', 'Заявление', 92],
  ['no_debt', 'Задолженности нет', 72],
  ['power_of_attorney', 'Доверенность', 72],
  ['contract', 'Договор', 72],
  ['uute', 'УУТЭ', 90],
  ['uute_verified', 'УУТЭ поверено', 90],
  ['third_party_disconnection', 'Отключение сторонних', 104],
  ['payment', 'Оплата', 84],
  ['water_supplied', 'Подана вода на точку', 110],
  ['verdict', 'Вердикт', 84],
  ['note', 'Примечание', 80],
  ['all_except_payment', 'Все кроме оплаты', 80],
  ['tf_in_ts', 'ТФ в ТС', 110],
  ['connection_act', 'Акт подключения', 120],
  ['illegal_connection_2025', 'Самовольное подключение 2025', 110],
  ['illegal_connection_2026', 'Самовольное подключение 2026', 110],
]

const DISPLAY_COLUMNS = (() => {
  const columns = EDITABLE_COLUMNS.filter(([key]) => key !== 'water_supplied')
  const waterSupplied = EDITABLE_COLUMNS.find(([key]) => key === 'water_supplied')
  const connectionActIndex = columns.findIndex(([key]) => key === 'connection_act')
  if (waterSupplied && connectionActIndex >= 0) columns.splice(connectionActIndex + 1, 0, waterSupplied)
  return columns
})()

const BASE_COLUMN_WIDTHS = [60, 132, 110, 96]
const TABLE_WIDTH = BASE_COLUMN_WIDTHS.reduce((sum, width) => sum + width, 0)
  + DISPLAY_COLUMNS.reduce((sum, [, , width]) => sum + width, 0)

const fixedColumnStyle = (width: number): CSSProperties => ({
  width,
  minWidth: width,
  maxWidth: width,
})

const YES_NO_FIELDS = new Set<keyof WaterRegistryRecord>([
  'no_debt',
  'power_of_attorney',
  'contract',
  'uute_verified',
  'payment',
  'water_supplied',
  'verdict',
  'all_except_payment',
  'tf_in_ts',
  'connection_act',
])

const CREATE_FIELDS: Array<[keyof WaterRegistryRecord, string, string]> = [
  ['actual_connection_point', 'Фактическая точка', 'Например 184'],
  ['gspo_name', 'Название', 'ГСПО ...'],
  ['standalone_address', 'Адрес', 'Адрес объекта'],
  ['leader_name', 'Председатель', 'ФИО'],
  ['phone', 'Телефон', 'Телефон'],
]

const PHONEOGRAM_SIGNERS = [
  { value: 'fadeev', label: 'Фадеев Д.А.' },
  { value: 'ivanov', label: 'Иванов А.Н.' },
  { value: 'golomansky', label: 'Голоманский В.В.' },
  { value: 'barybin', label: 'Барыбин В.А.' },
] as const

const PAYMENT_DATE_MARKER_PREFIX = '[оплата:'
const APPLICATION_DATE_MARKER_PREFIX = '[заявление:'
const LEGACY_DATE_MARKER_PREFIX = '[дата:'

type DateFilterKind = 'payment' | 'application'

function buildDateMarker(prefix: string, from: string, to: string) {
  const a = from.trim()
  const b = to.trim()
  if (!a && !b) return ''
  if (a && b && a !== b) return `${prefix}${a}..${b}]`
  return `${prefix}${a || b}]`
}

function stripDateMarkers(text: string) {
  return text
    .replace(/\s*\[оплата:[^\]]*\]\s*/gi, ' ')
    .replace(/\s*\[заявление:[^\]]*\]\s*/gi, ' ')
    .replace(/\s*\[дата:[^\]]*\]\s*/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

function hasDateMarker(text: string) {
  const lower = text.toLowerCase()
  return lower.includes(PAYMENT_DATE_MARKER_PREFIX)
    || lower.includes(APPLICATION_DATE_MARKER_PREFIX)
    || lower.includes(LEGACY_DATE_MARKER_PREFIX)
}

function parseDateMarker(text: string, prefix: string) {
  const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const match = text.match(new RegExp(`${escaped}([^\\]]+)\\]`, 'i'))
  if (!match) return { from: '', to: '' }
  const body = match[1].trim()
  if (body.includes('..')) {
    const [from, to] = body.split('..', 2)
    return { from: from.trim(), to: to.trim() }
  }
  return { from: body, to: body }
}

function resolveDateFilters(
  text: string,
  paymentFrom: string,
  paymentTo: string,
  applicationFrom: string,
  applicationTo: string,
) {
  const parsedPayment = parseDateMarker(text, PAYMENT_DATE_MARKER_PREFIX)
  const parsedLegacy = parseDateMarker(text, LEGACY_DATE_MARKER_PREFIX)
  const parsedApplication = parseDateMarker(text, APPLICATION_DATE_MARKER_PREFIX)

  const payment = {
    from: parsedPayment.from || parsedLegacy.from || paymentFrom.trim(),
    to: parsedPayment.to || parsedLegacy.to || paymentTo.trim(),
  }
  const application = {
    from: parsedApplication.from || applicationFrom.trim(),
    to: parsedApplication.to || applicationTo.trim(),
  }

  if (payment.from && !payment.to) payment.to = payment.from
  if (application.from && !application.to) application.to = application.from

  return {
    paymentFrom: payment.from,
    paymentTo: payment.to,
    applicationFrom: application.from,
    applicationTo: application.to,
  }
}

function composeSearchQuery(
  base: string,
  paymentFrom: string,
  paymentTo: string,
  applicationFrom: string,
  applicationTo: string,
) {
  const parts = [stripDateMarkers(base)]
  const paymentMarker = buildDateMarker(PAYMENT_DATE_MARKER_PREFIX, paymentFrom, paymentTo)
  const applicationMarker = buildDateMarker(APPLICATION_DATE_MARKER_PREFIX, applicationFrom, applicationTo)
  if (paymentMarker) parts.push(paymentMarker)
  if (applicationMarker) parts.push(applicationMarker)
  return parts.filter(Boolean).join(' ').trim()
}

function isMainFileName(name: string) {
  return name.toLowerCase().includes('основной файл')
}

const emptyCreateForm = (): Partial<Record<keyof WaterRegistryRecord, string>> => ({
  actual_connection_point: '',
  gspo_name: '',
  standalone_address: '',
  leader_name: '',
  phone: '',
  metering_presence: '',
})

const contactLabel = (contact: Contact) => [
  categoryLabel(contact.category),
  contact.name,
  contact.consumer,
  contact.manager,
  contact.address,
].map((value) => value?.trim()).filter(Boolean).join(' · ')

function cellText(record: WaterRegistryRecord, key: keyof WaterRegistryRecord) {
  const value = record[key]
  return value === null || value === undefined ? '' : String(value)
}

function isYes(value: string) {
  const normalized = value.trim().toLowerCase()
  return normalized === 'да' || normalized === 'рґр°'
}

function EditableCell({
  record,
  field,
  onSave,
  disabled,
  emptyText = '—',
}: {
  record: WaterRegistryRecord
  field: keyof WaterRegistryRecord
  onSave: (id: number, field: keyof WaterRegistryRecord, value: string) => void
  disabled?: boolean
  emptyText?: string
}) {
  const [editing, setEditing] = useState(false)
  const [value, setValue] = useState(cellText(record, field))
  const display = cellText(record, field)

  const save = () => {
    setEditing(false)
    if (value !== display) onSave(record.id, field, value)
  }

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'Enter') save()
    if (event.key === 'Escape') {
      setValue(display)
      setEditing(false)
    }
  }

  if (editing) {
    return (
      <input
        autoFocus
        value={value}
        onChange={(event) => setValue(event.target.value)}
        onBlur={save}
        onKeyDown={onKeyDown}
        className="w-full rounded border border-blue-300 bg-white px-2 py-1 text-sm outline-none ring-1 ring-blue-100"
      />
    )
  }

  return (
    <button
      type="button"
      disabled={disabled}
      onClick={() => {
        setValue(display)
        setEditing(true)
      }}
      className="block min-h-8 w-full rounded px-2 py-1 text-left hover:bg-blue-50 disabled:cursor-not-allowed disabled:hover:bg-transparent"
    >
      <span className={display ? 'whitespace-pre-line' : 'text-gray-400'}>
        {display || emptyText}
      </span>
    </button>
  )
}

function UuteCell({
  record,
  onSave,
  disabled,
}: {
  record: WaterRegistryRecord
  onSave: (id: number, field: keyof WaterRegistryRecord, value: string) => void
  disabled?: boolean
}) {
  const isAbsent = (record.uute || '').trim().toLowerCase() === 'нет'

  return (
    <div className="space-y-1">
      <div className="min-h-8 rounded px-2 py-1 text-sm">{(record.uute || '').trim() || '—'}</div>
      {!isAbsent && (
        <div className="border-t border-gray-100 pt-1 text-xs">
          <EditableCell
            record={record}
            field="uute_verification_until"
            onSave={onSave}
            disabled={disabled}
            emptyText="Добавить дату"
          />
        </div>
      )}
    </div>
  )
}

function YesNoCell({
  record,
  field,
  onSave,
  disabled,
}: {
  record: WaterRegistryRecord
  field: keyof WaterRegistryRecord
  onSave: (id: number, field: keyof WaterRegistryRecord, value: string) => void
  disabled?: boolean
}) {
  const value = cellText(record, field).trim().toLowerCase()

  return (
    <select
      value={value === 'да' || value === 'нет' ? value : ''}
      disabled={disabled}
      onChange={(event) => onSave(record.id, field, event.target.value)}
      className="w-full rounded border border-gray-200 bg-white px-2 py-1 text-sm outline-none hover:border-blue-300 focus:border-blue-400 focus:ring-1 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-gray-50"
    >
      <option value="">—</option>
      <option value="да">да</option>
      <option value="нет">нет</option>
    </select>
  )
}

function DateCell({
  record,
  field,
  onSave,
  disabled,
}: {
  record: WaterRegistryRecord
  field: keyof WaterRegistryRecord
  onSave: (id: number, field: keyof WaterRegistryRecord, value: string) => void
  disabled?: boolean
}) {
  const value = cellText(record, field)

  return (
    <input
      type="date"
      value={value}
      disabled={disabled}
      onChange={(event) => onSave(record.id, field, event.target.value)}
      className="w-full rounded border border-gray-200 bg-white px-2 py-1 text-sm outline-none hover:border-blue-300 focus:border-blue-400 focus:ring-1 focus:ring-blue-100 disabled:cursor-not-allowed disabled:bg-gray-50"
    />
  )
}

function ApplicationCell({
  record,
  onSave,
  disabled,
}: {
  record: WaterRegistryRecord
  onSave: (id: number, field: keyof WaterRegistryRecord, value: string) => void
  disabled?: boolean
}) {
  return (
    <div className="space-y-1">
      <YesNoCell
        record={record}
        field="application"
        onSave={onSave}
        disabled={disabled}
      />
      <div className="border-t border-gray-100 pt-1 text-xs">
        <DateCell
          record={record}
          field="application_date"
          onSave={onSave}
          disabled={disabled}
        />
      </div>
    </div>
  )
}

function PaymentCell({
  record,
  onSave,
  disabled,
  dateDisabled,
}: {
  record: WaterRegistryRecord
  onSave: (id: number, field: keyof WaterRegistryRecord, value: string) => void
  disabled?: boolean
  dateDisabled?: boolean
}) {
  return (
    <div className="space-y-1">
      <YesNoCell
        record={record}
        field="payment"
        onSave={onSave}
        disabled={disabled}
      />
      <div className="border-t border-gray-100 pt-1 text-xs">
        <DateCell
          record={record}
          field="payment_date"
          onSave={onSave}
          disabled={dateDisabled}
        />
      </div>
    </div>
  )
}

function TfInTsCell({
  record,
  onSave,
  disabled,
}: {
  record: WaterRegistryRecord
  onSave: (id: number, field: keyof WaterRegistryRecord, value: string) => void
  disabled?: boolean
}) {
  return (
    <div className="space-y-1">
      <YesNoCell
        record={record}
        field="tf_in_ts"
        onSave={onSave}
        disabled={disabled}
      />
      <div className="border-t border-gray-100 pt-1 text-xs">
        <DateCell
          record={record}
          field="tf_in_ts_date"
          onSave={onSave}
          disabled={disabled}
        />
      </div>
    </div>
  )
}

function ThirdPartyDisconnectionCell({
  record,
  onSave,
  disabled,
}: {
  record: WaterRegistryRecord
  onSave: (id: number, field: keyof WaterRegistryRecord, value: string) => void
  disabled?: boolean
}) {
  return (
    <div className="space-y-1">
      <YesNoCell
        record={record}
        field="third_party_disconnection"
        onSave={onSave}
        disabled={disabled}
      />
      <div className="border-t border-gray-100 pt-1 text-xs">
        <EditableCell
          record={record}
          field="third_party_disconnection_note"
          onSave={onSave}
          disabled={disabled}
          emptyText="Примечание"
        />
      </div>
    </div>
  )
}

export default function WaterRegistry() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [query, setQuery] = useState(searchParams.get('q') ?? '')
  const [point, setPoint] = useState(searchParams.get('point') ?? '')
  const [paymentFrom, setPaymentFrom] = useState(searchParams.get('payment_from') ?? '')
  const [paymentTo, setPaymentTo] = useState(searchParams.get('payment_to') ?? '')
  const [applicationFrom, setApplicationFrom] = useState(searchParams.get('application_from') ?? '')
  const [applicationTo, setApplicationTo] = useState(searchParams.get('application_to') ?? '')
  const [dateFilterKind, setDateFilterKind] = useState<DateFilterKind>(
    searchParams.get('application_from') || searchParams.get('application_to') ? 'application' : 'payment',
  )
  const [dateFilterOpen, setDateFilterOpen] = useState(false)
  const [phoneogramSigner, setPhoneogramSigner] = useState<string>('fadeev')
  const [phoneogramOpen, setPhoneogramOpen] = useState(false)
  const [phoneogramFrom, setPhoneogramFrom] = useState('')
  const [phoneogramTo, setPhoneogramTo] = useState('')
  const [actionsOpen, setActionsOpen] = useState(false)
  const [message, setMessage] = useState('')
  const [createOpen, setCreateOpen] = useState(false)
  const [createForm, setCreateForm] = useState<Partial<Record<keyof WaterRegistryRecord, string>>>(emptyCreateForm)
  const [createMode, setCreateMode] = useState<'existing' | 'new'>('existing')
  const [contactQuery, setContactQuery] = useState('')
  const [selectedContactId, setSelectedContactId] = useState('')
  const [createContactCategory, setCreateContactCategory] = useState<ContactCategory>('gspo')
  const page = Number(searchParams.get('page') ?? 0)
  const sort = searchParams.get('sort') ?? ''
  const dir = (searchParams.get('dir') === 'desc' ? 'desc' : 'asc') as 'asc' | 'desc'
  const queryClient = useQueryClient()
  const { user } = useAuth()
  const paymentOnly = user?.role === 'water_payment'
  const effectiveQuery = stripDateMarkers(query)
  const resolvedDates = resolveDateFilters(query, paymentFrom, paymentTo, applicationFrom, applicationTo)

  const { data, isLoading, error, isFetching } = useQuery({
    queryKey: [
      'metering', 'water', page, effectiveQuery.trim(), point.trim(), sort, dir,
      resolvedDates.paymentFrom, resolvedDates.paymentTo,
      resolvedDates.applicationFrom, resolvedDates.applicationTo,
    ],
    queryFn: () => meteringApi.listWater(
      page, effectiveQuery, point, sort, dir,
      resolvedDates.paymentFrom, resolvedDates.paymentTo,
      resolvedDates.applicationFrom, resolvedDates.applicationTo,
    ),
    placeholderData: (previousData) => previousData,
  })

  const contactSearchQuery = useQuery({
    queryKey: ['contacts', 'search', contactQuery.trim()],
    queryFn: () => contactsApi.search(contactQuery.trim()),
    enabled: createOpen && createMode === 'existing' && contactQuery.trim().length >= 2,
  })

  const contactOptions = contactSearchQuery.data?.records ?? []
  const selectedContact = contactOptions.find((contact) => String(contact.id) === selectedContactId)

  const importDisconnectionsMutation = useMutation({
    mutationFn: (file: File) => meteringApi.importWaterDisconnections(file),
    onSuccess: async (result) => {
      const extra = result.unmatched > 0 ? ` Не найдено: ${result.unmatched}.` : ''
      setMessage(`Отключения: обработано ${result.disconnected_rows}, обновлено ${result.matched}.${extra}`)
      await queryClient.invalidateQueries({ queryKey: ['metering', 'water'] })
    },
    onError: (err: { message?: string }) => setMessage(err.message || 'Не удалось импортировать отключения.'),
  })

  const createMutation = useMutation({
    mutationFn: async (payload: Partial<WaterRegistryRecord>) => {
      if (createMode === 'existing') {
        if (!selectedContactId) throw new Error('Выберите контакт')
        return meteringApi.createWater({ ...payload, contact_id: Number(selectedContactId) })
      }

      const identifier = crypto.randomUUID()
      const contact = await contactsApi.create(createContactCategory, {
        identifier,
        connection_point: payload.actual_connection_point ?? '',
        name: payload.gspo_name ?? '',
        address: payload.standalone_address ?? '',
        consumer: payload.leader_name ?? '',
        phone: payload.phone ?? '',
        metering_presence: payload.metering_presence ?? '',
      })
      return meteringApi.createWater({ ...payload, contact_id: contact.id, identifier })
    },
    onSuccess: async (record) => {
      setMessage(`Запись добавлена: ${record.gspo_name || record.standalone_address || record.actual_connection_point || record.id}`)
      setCreateOpen(false)
      setCreateForm(emptyCreateForm())
      setContactQuery('')
      setSelectedContactId('')
      await queryClient.invalidateQueries({ queryKey: ['metering', 'water'] })
      await queryClient.invalidateQueries({ queryKey: ['contacts'] })
    },
    onError: (err: { message?: string }) => setMessage(err.message || 'Не удалось добавить запись.'),
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, field, value }: { id: number; field: keyof WaterRegistryRecord; value: string }) => {
      if (paymentOnly && field !== 'payment') throw new Error('Можно редактировать только оплату.')
      return meteringApi.updateWater(id, { [field]: value })
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['metering', 'water'] })
    },
    onError: (err: { message?: string }) => setMessage(err.message || 'Не удалось сохранить ячейку.'),
  })

  const pageCount = data ? Math.max(Math.ceil(data.total / data.page_size), 1) : 1

  const updateParams = (next: {
    q?: string
    point?: string
    paymentFrom?: string
    paymentTo?: string
    applicationFrom?: string
    applicationTo?: string
    page?: number
    sort?: string
    dir?: 'asc' | 'desc'
  }) => {
    const nextQuery = next.q ?? query
    const nextPoint = next.point ?? point
    const nextPaymentFrom = next.paymentFrom ?? paymentFrom
    const nextPaymentTo = next.paymentTo ?? paymentTo
    const nextApplicationFrom = next.applicationFrom ?? applicationFrom
    const nextApplicationTo = next.applicationTo ?? applicationTo
    const nextPage = next.page ?? 0
    const nextSort = next.sort ?? sort
    const nextDir = next.dir ?? dir
    const params = new URLSearchParams()
    if (nextQuery.trim()) params.set('q', nextQuery.trim())
    if (nextPoint.trim()) params.set('point', nextPoint.trim())
    if (nextPaymentFrom.trim()) params.set('payment_from', nextPaymentFrom.trim())
    if (nextPaymentTo.trim()) params.set('payment_to', nextPaymentTo.trim())
    if (nextApplicationFrom.trim()) params.set('application_from', nextApplicationFrom.trim())
    if (nextApplicationTo.trim()) params.set('application_to', nextApplicationTo.trim())
    if (nextSort.trim()) {
      params.set('sort', nextSort.trim())
      params.set('dir', nextDir)
    }
    if (nextPage > 0) params.set('page', String(nextPage))
    setSearchParams(params)
  }

  const toggleMeteringSort = () => {
    updateParams({
      sort: 'metering_presence',
      dir: sort === 'metering_presence' && dir === 'asc' ? 'desc' : 'asc',
      page: 0,
    })
  }

  const todayIso = () => new Date().toISOString().slice(0, 10)

  const submitCreate = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    createMutation.mutate(createForm as Partial<WaterRegistryRecord>)
  }

  return (
    <div className="space-y-4">
      <nav className="text-sm">
        {!paymentOnly && (
          <Link to="/metering" className="text-blue-600 hover:underline">
            ← Приборы учета
          </Link>
        )}
      </nav>

      <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h1 className="text-2xl font-bold">Летняя вода ГСПО</h1>
          <p className="text-sm text-gray-600">
            {data ? `Всего записей: ${data.total}` : 'Реестр заявлений на подачу воды'}
            {isFetching ? ' · обновление...' : ''}
          </p>
          {data?.last_import && (
            <p className="text-xs text-gray-500">
              Последний импорт: {new Date(data.last_import.imported_at * 1000).toLocaleString('ru-RU')}
            </p>
          )}
        </div>

        <div className="flex flex-col gap-2 lg:flex-row">
          <input
            type="search"
            value={point}
            onChange={(event) => {
              setPoint(event.target.value)
              updateParams({ point: event.target.value })
            }}
            placeholder="Фактическая точка присоединения"
            className="w-full rounded border bg-white px-3 py-2 text-sm lg:w-32"
          />
          <input
            type="search"
            value={query}
            onChange={(event) => {
              const nextQuery = event.target.value
              setQuery(nextQuery)
              if (!hasDateMarker(nextQuery)) {
                setPaymentFrom('')
                setPaymentTo('')
                setApplicationFrom('')
                setApplicationTo('')
                updateParams({
                  q: nextQuery,
                  paymentFrom: '',
                  paymentTo: '',
                  applicationFrom: '',
                  applicationTo: '',
                  page: 0,
                })
                return
              }
              const dates = resolveDateFilters(nextQuery, paymentFrom, paymentTo, applicationFrom, applicationTo)
              setPaymentFrom(dates.paymentFrom)
              setPaymentTo(dates.paymentTo)
              setApplicationFrom(dates.applicationFrom)
              setApplicationTo(dates.applicationTo)
              updateParams({
                q: nextQuery,
                paymentFrom: dates.paymentFrom,
                paymentTo: dates.paymentTo,
                applicationFrom: dates.applicationFrom,
                applicationTo: dates.applicationTo,
                page: 0,
              })
            }}
            placeholder="Название, адрес, председатель, телефон..."
            className="w-full rounded border bg-white px-3 py-2 pr-10 text-sm lg:w-96"
          />
          <button
            title="Фильтр по дате оплаты или заявления"
            type="button"
            onClick={() => setDateFilterOpen(true)}
            className="-ml-8 inline-flex items-center text-gray-500 hover:text-gray-700"
          >
            📅
          </button>
          <button
            type="button"
            onClick={() => setDateFilterOpen(true)}
            className="hidden rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
          >
            Фильтр дат
          </button>
          <input
            type="date"
            value={paymentFrom}
            onChange={(event) => {
              setPaymentFrom(event.target.value)
              updateParams({ paymentFrom: event.target.value })
            }}
            title="Оплата с"
            className="hidden w-full rounded border bg-white px-3 py-2 text-sm lg:w-36"
          />
          <input
            type="date"
            value={paymentTo}
            onChange={(event) => {
              setPaymentTo(event.target.value)
              updateParams({ paymentTo: event.target.value })
            }}
            title="Оплата по"
            className="hidden w-full rounded border bg-white px-3 py-2 text-sm lg:w-36"
          />
          <button
            type="button"
            onClick={() => {
              const today = todayIso()
              setPaymentFrom(today)
              setPaymentTo(today)
              updateParams({ paymentFrom: today, paymentTo: today })
            }}
            className="hidden rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
          >
            Сегодня
          </button>
          {!paymentOnly && (
            <div className="relative">
              <button
                type="button"
                onClick={() => setActionsOpen((current) => !current)}
                className="rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
              >
                Еще
              </button>
              {actionsOpen && (
                <div className="absolute right-0 z-20 mt-1 w-64 rounded border bg-white p-2 shadow-lg">
                  <button
                    type="button"
                    onClick={() => {
                      const today = todayIso()
                      setPhoneogramFrom(paymentFrom.trim() || today)
                      setPhoneogramTo(paymentTo.trim() || paymentFrom.trim() || today)
                      setPhoneogramOpen(true)
                      setActionsOpen(false)
                    }}
                    className="block w-full rounded px-3 py-2 text-left text-sm hover:bg-gray-100"
                  >
                    Скачать телефонограмму
                  </button>
                  <a
                    href={meteringApi.waterDisconnectedExportUrl()}
                    className="block w-full rounded px-3 py-2 text-left text-sm hover:bg-gray-100"
                    onClick={() => setActionsOpen(false)}
                  >
                    Скачать реестр отключенных
                  </a>
                  <button
                    type="button"
                    onClick={() => {
                      setCreateForm(emptyCreateForm())
                      setCreateMode('existing')
                      setContactQuery('')
                      setSelectedContactId('')
                      setCreateContactCategory('gspo')
                      setCreateOpen(true)
                      setActionsOpen(false)
                    }}
                    className="block w-full rounded px-3 py-2 text-left text-sm hover:bg-gray-100"
                  >
                    Добавить запись
                  </button>
                  {(user?.role === 'admin' || user?.role === 'full') && (
                    <label className="block w-full cursor-pointer rounded px-3 py-2 text-left text-sm hover:bg-gray-100">
                      {importDisconnectionsMutation.isPending ? 'Загрузка...' : 'Загрузить реестр отключенных'}
                      <input
                        type="file"
                        accept=".xlsx"
                        className="hidden"
                        disabled={importDisconnectionsMutation.isPending}
                        onChange={(event) => {
                          const file = event.target.files?.[0]
                          if (file) {
                            if (!isMainFileName(file.name)) {
                              setMessage('Неверный файл: в названии должно быть "Основной файл".')
                            } else {
                              importDisconnectionsMutation.mutate(file)
                            }
                          }
                          event.currentTarget.value = ''
                          setActionsOpen(false)
                        }}
                      />
                    </label>
                  )}
                </div>
              )}
            </div>
          )}
          {false && !paymentOnly && (
            <select
              value={phoneogramSigner}
              onChange={(event) => setPhoneogramSigner(event.target.value)}
              className="w-full rounded border bg-white px-3 py-2 text-sm lg:w-48"
              title="Подписант"
            >
              {PHONEOGRAM_SIGNERS.map((signer) => (
                <option key={signer.value} value={signer.value}>{signer.label}</option>
              ))}
            </select>
          )}
          {false && !paymentOnly && (
            <a
              href={meteringApi.waterPhoneogramUrl(phoneogramFrom, phoneogramTo, phoneogramSigner)}
              className="inline-flex items-center justify-center rounded bg-blue-600 px-3 py-2 text-sm text-white hover:bg-blue-700"
            >
              Скачать телефонограмму
            </a>
          )}
          {false && !paymentOnly && (
            <button
              type="button"
              onClick={() => {
                setCreateForm(emptyCreateForm())
                setCreateMode('existing')
                setContactQuery('')
                setSelectedContactId('')
                setCreateContactCategory('gspo')
                setCreateOpen(true)
              }}
              className="rounded bg-emerald-600 px-3 py-2 text-sm text-white hover:bg-emerald-700"
            >
              Добавить запись
            </button>
          )}
          {false && user?.role === 'admin' && (
            <label className="inline-flex cursor-pointer items-center justify-center rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100">
              {importDisconnectionsMutation.isPending ? 'Загрузка...' : 'Загрузить реестр отключенных'}
              <input
                type="file"
                accept=".xlsx"
                className="hidden"
                disabled={importDisconnectionsMutation.isPending}
                onChange={(event) => {
                  const file = event.target.files?.[0]
                  if (file) importDisconnectionsMutation.mutate(file)
                  event.currentTarget.value = ''
                }}
              />
            </label>
          )}
        </div>
      </div>

      {message && <div className="rounded border border-blue-200 bg-blue-50 p-3 text-sm text-blue-900">{message}</div>}
      {dateFilterOpen && (
        <div className="fixed inset-0 z-30 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md rounded-lg bg-white p-4 shadow-xl">
            <h2 className="mb-3 text-base font-semibold">Фильтр по дате</h2>
            <div className="mb-3 flex rounded border bg-gray-50 p-1 text-sm">
              <button
                type="button"
                onClick={() => setDateFilterKind('payment')}
                className={`flex-1 rounded px-2 py-1.5 ${dateFilterKind === 'payment' ? 'bg-white font-medium shadow-sm' : 'text-gray-600 hover:text-gray-900'}`}
              >
                Оплата
              </button>
              <button
                type="button"
                onClick={() => setDateFilterKind('application')}
                className={`flex-1 rounded px-2 py-1.5 ${dateFilterKind === 'application' ? 'bg-white font-medium shadow-sm' : 'text-gray-600 hover:text-gray-900'}`}
              >
                Заявление
              </button>
            </div>
            <div className="space-y-3">
              <label className="block text-sm">
                <span className="mb-1 block text-gray-700">Дата с</span>
                <input
                  type="date"
                  value={dateFilterKind === 'payment' ? paymentFrom : applicationFrom}
                  onChange={(event) => {
                    if (dateFilterKind === 'payment') setPaymentFrom(event.target.value)
                    else setApplicationFrom(event.target.value)
                  }}
                  className="w-full rounded border bg-white px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-sm">
                <span className="mb-1 block text-gray-700">Дата по</span>
                <input
                  type="date"
                  value={dateFilterKind === 'payment' ? paymentTo : applicationTo}
                  onChange={(event) => {
                    if (dateFilterKind === 'payment') setPaymentTo(event.target.value)
                    else setApplicationTo(event.target.value)
                  }}
                  className="w-full rounded border bg-white px-3 py-2 text-sm"
                />
              </label>
            </div>
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => {
                  const today = todayIso()
                  if (dateFilterKind === 'payment') {
                    setPaymentFrom(today)
                    setPaymentTo(today)
                  } else {
                    setApplicationFrom(today)
                    setApplicationTo(today)
                  }
                }}
                className="rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
              >
                Сегодня
              </button>
              <button
                type="button"
                onClick={() => {
                  const clearedPaymentFrom = dateFilterKind === 'payment' ? '' : paymentFrom
                  const clearedPaymentTo = dateFilterKind === 'payment' ? '' : paymentTo
                  const clearedApplicationFrom = dateFilterKind === 'application' ? '' : applicationFrom
                  const clearedApplicationTo = dateFilterKind === 'application' ? '' : applicationTo
                  if (dateFilterKind === 'payment') {
                    setPaymentFrom('')
                    setPaymentTo('')
                  } else {
                    setApplicationFrom('')
                    setApplicationTo('')
                  }
                  const nextQuery = composeSearchQuery(
                    query,
                    clearedPaymentFrom,
                    clearedPaymentTo,
                    clearedApplicationFrom,
                    clearedApplicationTo,
                  )
                  setQuery(nextQuery)
                  updateParams({
                    q: nextQuery,
                    paymentFrom: clearedPaymentFrom,
                    paymentTo: clearedPaymentTo,
                    applicationFrom: clearedApplicationFrom,
                    applicationTo: clearedApplicationTo,
                    page: 0,
                  })
                }}
                className="rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
              >
                Сброс
              </button>
              <button
                type="button"
                onClick={() => {
                  const dates = resolveDateFilters(
                    composeSearchQuery(query, paymentFrom, paymentTo, applicationFrom, applicationTo),
                    paymentFrom,
                    paymentTo,
                    applicationFrom,
                    applicationTo,
                  )
                  const nextQuery = composeSearchQuery(
                    query,
                    dates.paymentFrom,
                    dates.paymentTo,
                    dates.applicationFrom,
                    dates.applicationTo,
                  )
                  setPaymentFrom(dates.paymentFrom)
                  setPaymentTo(dates.paymentTo)
                  setApplicationFrom(dates.applicationFrom)
                  setApplicationTo(dates.applicationTo)
                  setQuery(nextQuery)
                  updateParams({
                    q: nextQuery,
                    paymentFrom: dates.paymentFrom,
                    paymentTo: dates.paymentTo,
                    applicationFrom: dates.applicationFrom,
                    applicationTo: dates.applicationTo,
                    page: 0,
                  })
                  setDateFilterOpen(false)
                }}
                className="rounded bg-blue-600 px-3 py-2 text-sm text-white hover:bg-blue-700"
              >
                Применить
              </button>
            </div>
          </div>
        </div>
      )}
      {phoneogramOpen && (
        <div className="fixed inset-0 z-30 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md rounded-lg bg-white p-4 shadow-xl">
            <h2 className="mb-3 text-base font-semibold">Скачать телефонограмму</h2>
            <div className="space-y-3">
              <label className="block text-sm">
                <span className="mb-1 block text-gray-700">Дата с</span>
                <input
                  type="date"
                  value={phoneogramFrom}
                  onChange={(event) => setPhoneogramFrom(event.target.value)}
                  className="w-full rounded border bg-white px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-sm">
                <span className="mb-1 block text-gray-700">Дата по</span>
                <input
                  type="date"
                  value={phoneogramTo}
                  onChange={(event) => setPhoneogramTo(event.target.value)}
                  className="w-full rounded border bg-white px-3 py-2 text-sm"
                />
              </label>
              <label className="block text-sm">
                <span className="mb-1 block text-gray-700">Подписант</span>
                <select
                  value={phoneogramSigner}
                  onChange={(event) => setPhoneogramSigner(event.target.value)}
                  className="w-full rounded border bg-white px-3 py-2 text-sm"
                >
                  {PHONEOGRAM_SIGNERS.map((signer) => (
                    <option key={signer.value} value={signer.value}>{signer.label}</option>
                  ))}
                </select>
              </label>
            </div>
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setPhoneogramOpen(false)}
                className="rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
              >
                Отмена
              </button>
              <a
                href={meteringApi.waterPhoneogramUrl(phoneogramFrom, phoneogramTo, phoneogramSigner)}
                className="rounded bg-blue-600 px-3 py-2 text-sm text-white hover:bg-blue-700"
                onClick={() => setPhoneogramOpen(false)}
              >
                Скачать
              </a>
            </div>
          </div>
        </div>
      )}
      {createOpen && (
        <div className="rounded-lg border bg-white p-4 shadow">
          <form className="space-y-4" onSubmit={submitCreate}>
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-lg font-semibold">Добавить запись</h2>
              <button
                type="button"
                onClick={() => setCreateOpen(false)}
                className="rounded border px-3 py-1.5 text-sm hover:bg-gray-100"
              >
                Закрыть
              </button>
            </div>
            <div className="flex flex-wrap gap-2 text-sm">
              <button
                type="button"
                onClick={() => setCreateMode('existing')}
                className={`rounded border px-3 py-1.5 ${createMode === 'existing' ? 'border-blue-600 bg-blue-50 text-blue-700' : 'bg-white hover:bg-gray-100'}`}
              >
                Выбрать из контактов
              </button>
              <button
                type="button"
                onClick={() => setCreateMode('new')}
                className={`rounded border px-3 py-1.5 ${createMode === 'new' ? 'border-blue-600 bg-blue-50 text-blue-700' : 'bg-white hover:bg-gray-100'}`}
              >
                Создать новый контакт
              </button>
            </div>
            {createMode === 'new' && (
              <label className="block max-w-xs space-y-1 text-sm">
                <span className="font-medium text-gray-700">Категория контакта</span>
                <select
                  value={createContactCategory}
                  onChange={(event) => setCreateContactCategory(event.target.value as ContactCategory)}
                  className="w-full rounded border bg-white px-3 py-2 text-sm outline-none focus:border-blue-400 focus:ring-1 focus:ring-blue-100"
                >
                  {(['gspo', 'phys', 'legal', 'budget', 'iglakovo', 'embedded', 'uk_tsj', 'bu2'] as ContactCategory[]).map((category) => (
                    <option key={category} value={category}>{categoryLabel(category)}</option>
                  ))}
                </select>
              </label>
            )}
            {createMode === 'existing' && (
              <div className="grid gap-3 md:grid-cols-3">
                <label className="space-y-1 text-sm md:col-span-2">
                  <span className="font-medium text-gray-700">Контакт ГСПО</span>
                  <input
                    value={contactQuery}
                    onChange={(event) => {
                      setContactQuery(event.target.value)
                      setSelectedContactId('')
                    }}
                    placeholder="Название, адрес, председатель, UID"
                    className="w-full rounded border bg-white px-3 py-2 text-sm outline-none focus:border-blue-400 focus:ring-1 focus:ring-blue-100"
                  />
                  {contactQuery.trim().length >= 2 && (
                    <select
                      value={selectedContactId}
                      onChange={(event) => setSelectedContactId(event.target.value)}
                      className="mt-2 w-full rounded border bg-white px-3 py-2 text-sm outline-none focus:border-blue-400 focus:ring-1 focus:ring-blue-100"
                    >
                      <option value="">{contactSearchQuery.isFetching ? 'Поиск...' : 'Выберите контакт'}</option>
                      {contactOptions.map((contact) => (
                        <option key={contact.id} value={contact.id}>
                          {contactLabel(contact)}
                        </option>
                      ))}
                    </select>
                  )}
                </label>
                {selectedContact && (
                  <div className="rounded border bg-gray-50 p-3 text-sm">
                    <p className="font-medium">{selectedContact.name || 'Без названия'}</p>
                    <p className="text-gray-600">{selectedContact.address || 'Адрес не указан'}</p>
                    <p className="text-gray-600">{selectedContact.consumer || 'Председатель не указан'}</p>
                  </div>
                )}
              </div>
            )}
            <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
              {CREATE_FIELDS.map(([key, label, placeholder]) => (
                <label key={key} className="space-y-1 text-sm">
                  <span className="font-medium text-gray-700">{label}</span>
                  <input
                    value={createForm[key] ?? ''}
                    onChange={(event) => setCreateForm((current) => ({ ...current, [key]: event.target.value }))}
                    placeholder={placeholder}
                    className="w-full rounded border bg-white px-3 py-2 text-sm outline-none focus:border-blue-400 focus:ring-1 focus:ring-blue-100"
                  />
                </label>
              ))}
              <label className="space-y-1 text-sm">
                <span className="font-medium text-gray-700">Наличие УУТЭ</span>
                <select
                  value={createForm.metering_presence ?? ''}
                  onChange={(event) => setCreateForm((current) => ({ ...current, metering_presence: event.target.value }))}
                  className="w-full rounded border bg-white px-3 py-2 text-sm outline-none focus:border-blue-400 focus:ring-1 focus:ring-blue-100"
                >
                  <option value="">—</option>
                  <option value="да">да</option>
                  <option value="нет">нет</option>
                </select>
              </label>
            </div>
            <div className="flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setCreateForm(emptyCreateForm())}
                className="rounded border px-3 py-2 text-sm hover:bg-gray-100"
              >
                Очистить
              </button>
              <button
                type="submit"
                disabled={createMutation.isPending}
                className="rounded bg-emerald-600 px-4 py-2 text-sm text-white hover:bg-emerald-700 disabled:opacity-50"
              >
                {createMutation.isPending ? 'Добавление...' : 'Добавить'}
              </button>
            </div>
          </form>
        </div>
      )}
      {isLoading && <div className="text-gray-500">Загрузка...</div>}
      {error && <div className="rounded border border-red-200 bg-red-50 p-3 text-red-800">Ошибка загрузки.</div>}

      {data && data.records.length > 0 && (
        <div className="overflow-x-auto rounded-lg bg-white shadow">
          <table className="table-fixed text-xs" style={{ width: TABLE_WIDTH }}>
            <colgroup>
              {BASE_COLUMN_WIDTHS.map((width, index) => (
                <col key={index} style={fixedColumnStyle(width)} />
              ))}
              {DISPLAY_COLUMNS.map(([key, , width]) => (
                <col key={key} style={fixedColumnStyle(width)} />
              ))}
            </colgroup>
            <thead className="bg-gray-100 text-left">
              <tr>
                <th className="break-words px-1.5 py-1.5">Факт. точка</th>
                <th className="break-words px-2 py-1.5">Название</th>
                <th className="break-words px-1.5 py-1.5">Адрес</th>
                <th className="break-words px-1.5 py-1.5">Председатель</th>
                {DISPLAY_COLUMNS.map(([key, label]) => (
                  <th key={key} className="break-words px-1.5 py-1.5">
                    {key === 'metering_presence' ? (
                      <button
                        type="button"
                        onClick={toggleMeteringSort}
                        className="text-left font-semibold text-gray-800 hover:text-blue-700"
                      >
                        {label}
                        {sort === 'metering_presence' ? (dir === 'asc' ? ' ↑' : ' ↓') : ''}
                      </button>
                    ) : (
                      label
                    )}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {data.records.map((record) => (
                <tr key={record.id} className="border-t hover:bg-gray-50">
                  <td className="break-words px-1.5 py-1.5 font-medium">{record.actual_connection_point || record.point_number || '—'}</td>
                  <td className="break-words px-2 py-1.5">
                    {paymentOnly ? (
                      <span className="block break-words">{record.gspo_name || '—'}</span>
                    ) : (
                      <Link to={`/summer-water/${record.id}`} className="block break-words text-blue-700 hover:underline">
                        {record.gspo_name || '—'}
                      </Link>
                    )}
                  </td>
                  <td className="break-words px-1.5 py-1.5">{record.standalone_address || '—'}</td>
                  <td className="break-words px-1.5 py-1.5">{record.leader_name || '—'}</td>
                  {DISPLAY_COLUMNS.map(([key]) => (
                    <td key={key} className="px-0.5 py-0.5 align-top">
                      {key === 'all_except_payment' && isYes(cellText(record, 'payment')) ? (
                        <div className="min-h-8 rounded bg-gray-50" />
                      ) : key === 'application' ? (
                        <ApplicationCell
                          record={record}
                          disabled={updateMutation.isPending || paymentOnly}
                          onSave={(id, field, value) => updateMutation.mutate({ id, field, value })}
                        />
                      ) : key === 'uute' ? (
                        <UuteCell
                          record={record}
                          disabled={updateMutation.isPending || paymentOnly}
                          onSave={(id, field, value) => updateMutation.mutate({ id, field, value })}
                        />
                      ) : key === 'third_party_disconnection' ? (
                        <ThirdPartyDisconnectionCell
                          record={record}
                          disabled={updateMutation.isPending || paymentOnly}
                          onSave={(id, field, value) => updateMutation.mutate({ id, field, value })}
                        />
                      ) : key === 'tf_in_ts' ? (
                        <TfInTsCell
                          record={record}
                          disabled={updateMutation.isPending || paymentOnly}
                          onSave={(id, field, value) => updateMutation.mutate({ id, field, value })}
                        />
                      ) : key === 'payment' ? (
                        <PaymentCell
                          record={record}
                          disabled={updateMutation.isPending}
                          dateDisabled={updateMutation.isPending || paymentOnly}
                          onSave={(id, field, value) => updateMutation.mutate({ id, field, value })}
                        />
                      ) : YES_NO_FIELDS.has(key) ? (
                        <YesNoCell
                          record={record}
                          field={key}
                          disabled={updateMutation.isPending || paymentOnly}
                          onSave={(id, field, value) => updateMutation.mutate({ id, field, value })}
                        />
                      ) : (
                        <EditableCell
                          record={record}
                          field={key}
                          disabled={updateMutation.isPending || paymentOnly}
                          onSave={(id, field, value) => updateMutation.mutate({ id, field, value })}
                        />
                      )}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {data && data.records.length === 0 && (
        <p className="rounded bg-white p-4 shadow text-gray-500">Ничего не найдено.</p>
      )}

      {data && pageCount > 1 && (
        <div className="flex items-center justify-between">
          <button
            type="button"
            disabled={page === 0}
            onClick={() => updateParams({ page: page - 1 })}
            className="rounded border bg-white px-3 py-1.5 text-sm disabled:opacity-40 hover:bg-gray-100"
          >
            ← Пред.
          </button>
          <span className="text-sm text-gray-600">Страница {page + 1} из {pageCount}</span>
          <button
            type="button"
            disabled={page >= pageCount - 1}
            onClick={() => updateParams({ page: page + 1 })}
            className="rounded border bg-white px-3 py-1.5 text-sm disabled:opacity-40 hover:bg-gray-100"
          >
            След. →
          </button>
        </div>
      )}
    </div>
  )
}
