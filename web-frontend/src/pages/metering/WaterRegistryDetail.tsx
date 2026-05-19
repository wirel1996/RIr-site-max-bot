import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState, type FormEvent } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { contactsApi, type Contact } from '../../api/contacts'
import { meteringApi, type WaterRegistryRecord } from '../../api/metering'

const FIELDS: Array<[keyof WaterRegistryRecord, string]> = [
  ['point_number', '№ точки'],
  ['actual_connection_point', 'Фактическая точка присоединения'],
  ['connected', 'Подключено'],
  ['point_filter', 'Фильтр точки'],
  ['gspo_count_in_point', 'Количество ГСПО в точке'],
  ['gspo_name', 'Наименование ГСПО'],
  ['standalone_address', 'Адрес'],
  ['leader_name', 'Ф.И.О. руководителя'],
  ['phone', 'Телефон'],
  ['metering_presence', 'Наличие ПУ'],
  ['uute_verification_until', 'Поверка приборов учета до'],
  ['application', 'Заявление'],
  ['no_debt', 'Задолженности нет'],
  ['power_of_attorney', 'Доверенность'],
  ['contract', 'Договор'],
  ['uute', 'УУТЭ'],
  ['uute_verified', 'УУТЭ поверено'],
  ['third_party_disconnection', 'Отключение сторонних'],
  ['third_party_disconnection_note', 'Акт отключения сторонних'],
  ['payment', 'Оплата'],
  ['water_supplied', 'Подана вода на точку'],
  ['all_except_payment', 'Все кроме оплаты'],
  ['verdict', 'Вердикт'],
  ['note', 'Примечание'],
  ['tf_in_ts', 'ТФ в ТС'],
  ['tf_in_ts_date', 'Дата ТФ в ТС'],
  ['connection_act', 'Акт подключения'],
  ['illegal_connection_2025', 'Выявлены самовольные подключения 2025'],
  ['illegal_connection_2026', 'Выявлены самовольные подключения 2026'],
]

function contactLabel(contact: Contact) {
  return [contact.name, contact.consumer, contact.address, contact.identifier].filter(Boolean).join(' · ')
}

export default function WaterRegistryDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [isEditing, setIsEditing] = useState(false)
  const [form, setForm] = useState<Partial<Record<keyof WaterRegistryRecord, string>>>({})
  const [contactQuery, setContactQuery] = useState('')
  const [selectedContactId, setSelectedContactId] = useState('')

  const { data, isLoading, error } = useQuery({
    queryKey: ['metering', 'water', 'detail', id],
    queryFn: () => meteringApi.waterDetail(Number(id)),
    enabled: !!id,
  })

  const updateMutation = useMutation({
    mutationFn: (payload: Partial<WaterRegistryRecord>) => meteringApi.updateWater(Number(id), payload),
    onSuccess: (record) => {
      queryClient.setQueryData(['metering', 'water', 'detail', id], record)
      queryClient.invalidateQueries({ queryKey: ['metering', 'water'] })
      setIsEditing(false)
    },
  })

  const contactSearchQuery = useQuery({
    queryKey: ['contacts', 'water-link-search', contactQuery.trim()],
    queryFn: () => contactsApi.search(contactQuery),
    enabled: contactQuery.trim().length >= 2,
  })

  const contactOptions = contactSearchQuery.data?.records ?? []

  const linkContactMutation = useMutation({
    mutationFn: (contactId: number) => meteringApi.updateWater(Number(id), { contact_id: contactId }),
    onSuccess: (record) => {
      queryClient.setQueryData(['metering', 'water', 'detail', id], record)
      queryClient.invalidateQueries({ queryKey: ['metering', 'water'] })
      setContactQuery('')
      setSelectedContactId('')
    },
  })

  useEffect(() => {
    if (!data) return
    const next: Partial<Record<keyof WaterRegistryRecord, string>> = {}
    FIELDS.forEach(([key]) => {
      const value = data[key]
      next[key] = value === null || value === undefined ? '' : String(value)
    })
    setForm(next)
  }, [data])

  if (isLoading) return <div className="text-gray-500">Загрузка...</div>
  if (error || !data) return <div className="text-red-700">Запись не найдена</div>

  const resetForm = () => {
    const next: Partial<Record<keyof WaterRegistryRecord, string>> = {}
    FIELDS.forEach(([key]) => {
      const value = data[key]
      next[key] = value === null || value === undefined ? '' : String(value)
    })
    setForm(next)
  }

  const onSubmit = (event: FormEvent) => {
    event.preventDefault()
    updateMutation.mutate(form as Partial<WaterRegistryRecord>)
  }

  return (
    <div className="space-y-4">
      <nav className="flex items-center justify-between text-sm">
        <Link to="/summer-water" className="text-blue-600 hover:underline">
          ← Летняя вода ГСПО
        </Link>
        <button
          type="button"
          onClick={() => navigate(-1)}
          className="rounded border bg-white px-3 py-1.5 text-gray-700 hover:bg-gray-100"
        >
          ← Назад
        </button>
      </nav>

      <div className="rounded-lg bg-white p-5 shadow">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-xs uppercase text-gray-500">Точка {data.point_number || '—'}</p>
            <h1 className="text-xl font-bold">{data.gspo_name || 'Без названия'}</h1>
            <p className="mt-1 text-sm text-gray-600">{data.standalone_address}</p>
          </div>
          <button
            type="button"
            onClick={() => {
              if (isEditing) {
                resetForm()
                setIsEditing(false)
              } else {
                setIsEditing(true)
              }
            }}
            className="w-fit rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100"
          >
            {isEditing ? 'Отменить' : 'Редактировать'}
          </button>
        </div>
      </div>

      {isEditing && (
        <form onSubmit={onSubmit} className="space-y-4 rounded-lg bg-white p-5 shadow">
          <h2 className="font-semibold">Редактирование заявления</h2>
          <div className="grid gap-3 md:grid-cols-2">
            {FIELDS.map(([key, label]) => (
              <label key={key} className="block">
                <span className="mb-1 block text-xs font-medium text-gray-600">{label}</span>
                <input
                  value={form[key] ?? ''}
                  onChange={(event) => setForm((current) => ({ ...current, [key]: event.target.value }))}
                  className="w-full rounded border px-3 py-2 text-sm"
                />
              </label>
            ))}
          </div>
          <div className="flex gap-2">
            <button
              type="submit"
              disabled={updateMutation.isPending}
              className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
            >
              {updateMutation.isPending ? 'Сохранение...' : 'Сохранить'}
            </button>
            <button
              type="button"
              onClick={() => {
                resetForm()
                setIsEditing(false)
              }}
              className="rounded border bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
            >
              Отмена
            </button>
          </div>
          {updateMutation.error && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
              Не удалось сохранить изменения.
            </div>
          )}
        </form>
      )}

      <section className="rounded-lg bg-white p-5 shadow">
        <h2 className="mb-3 font-semibold">Карточка</h2>
        <dl className="divide-y divide-gray-100">
          {FIELDS.map(([key, label]) => {
            const value = data[key]
            if (value === null || value === undefined || String(value).trim() === '') return null
            return (
              <div key={key} className="py-2 sm:flex sm:gap-4">
                <dt className="font-medium text-gray-600 sm:w-72 shrink-0">{label}</dt>
                <dd className="mt-1 flex-1 whitespace-pre-line sm:mt-0">{String(value)}</dd>
              </div>
            )
          })}
        </dl>
      </section>

      <section className="rounded-lg bg-white p-5 shadow">
        <h2 className="mb-3 font-semibold">Связи</h2>
        <div className="space-y-2 text-sm">
          <p>
            Контакт:{' '}
            {data.contact_id ? (
              <Link to={`/contacts/${data.contact_id}`} className="text-blue-700 hover:underline">открыть</Link>
            ) : (
              <span className="text-gray-500">не связан</span>
            )}
          </p>
          {data.uute_id && (
            <p>
              УУТЭ: <Link to={`/metering/gspo/${data.uute_id}`} className="text-blue-700 hover:underline">открыть</Link>
            </p>
          )}
          {data.uute_match_note && <p className="text-gray-600">{data.uute_match_note}</p>}
        </div>

        <div className="mt-4 grid gap-2 md:grid-cols-[1fr_1fr_auto]">
          <input
            value={contactQuery}
            onChange={(event) => {
              setContactQuery(event.target.value)
              setSelectedContactId('')
            }}
            placeholder="Найти контакт по названию, адресу или UID"
            className="rounded border px-3 py-2 text-sm"
          />
          <select
            value={selectedContactId}
            onChange={(event) => setSelectedContactId(event.target.value)}
            className="rounded border bg-white px-3 py-2 text-sm"
          >
            <option value="">Выберите контакт...</option>
            {contactOptions.map((contact) => (
              <option key={contact.id} value={contact.id}>{contactLabel(contact)}</option>
            ))}
          </select>
          <button
            type="button"
            disabled={!selectedContactId || linkContactMutation.isPending}
            onClick={() => linkContactMutation.mutate(Number(selectedContactId))}
            className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
          >
            {linkContactMutation.isPending ? 'Связываю...' : 'Связать'}
          </button>
        </div>
        {linkContactMutation.error && (
          <div className="mt-3 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            Не удалось связать контакт.
          </div>
        )}
      </section>
    </div>
  )
}
