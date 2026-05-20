import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState, type FormEvent } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { contactsApi, type Contact, type ContactUpdatePayload } from '../../api/contacts'
import { meteringApi } from '../../api/metering'
import { shortLabel } from './shortLabel'
import { categoryLabel, editableFieldsForCategory } from './contactDisplay'

type FieldKind = 'text' | 'phone'
type Field = [string, string | null, FieldKind?]

function fieldsFor(record: Contact): Field[] {
  switch (record.category) {
    case 'uk_tsj':
      return [
        ['Наименование', record.name],
        ['Адрес', record.address],
        ['Руководитель', record.manager],
        ['Телефон', record.phone, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Идентификатор', record.identifier],
      ]
    case 'gspo':
      return [
        ['Точка подключения', record.connection_point],
        ['Наименование', record.name],
        ['Адрес', record.address],
        ['Потребитель', record.consumer],
        ['Телефон', record.phone, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Наличие приборов учета', record.metering_presence],
        ['Отключено', record.disconnected],
        ['Синхронизация', record.sync_status === 'not_matched' ? 'ошибка' : null],
        ['Комментарий синхронизации', record.sync_note],
        ['Идентификатор', record.identifier],
      ]
    default:
      return [
        ['Наименование', record.name],
        ['Потребитель', record.consumer],
        ['Руководитель', record.manager],
        ['Адрес', record.address],
        ['Телефон', record.phone, 'phone'],
        ['Альтернативный телефон', record.phone_alt, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Идентификатор', record.identifier],
        ['Примечания', record.notes],
      ]
  }
}

export default function ContactsDetail() {
  const { id } = useParams<{ id: string }>()
  const location = useLocation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const backTo = (location.state as { from?: string } | null)?.from ?? '/contacts'
  const [isEditing, setIsEditing] = useState(false)
  const [form, setForm] = useState<ContactUpdatePayload>({})

  const { data, isLoading, error } = useQuery({
    queryKey: ['contacts', 'detail', id],
    queryFn: () => contactsApi.detail(Number(id)),
    enabled: !!id,
  })

  const meteringLinksQuery = useQuery({
    queryKey: ['contacts', 'metering-links', id],
    queryFn: () => meteringApi.linksForContact(Number(id)),
    enabled: !!id && data?.category === 'gspo',
  })

  const updateMutation = useMutation({
    mutationFn: (payload: ContactUpdatePayload) => contactsApi.update(Number(id), payload),
    onSuccess: (record) => {
      queryClient.setQueryData(['contacts', 'detail', id], record)
      queryClient.invalidateQueries({ queryKey: ['contacts'] })
      setIsEditing(false)
    },
  })

  const deleteMutation = useMutation({
    mutationFn: () => contactsApi.delete(Number(id)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['contacts'] })
      navigate(backTo, { replace: true })
    },
  })

  useEffect(() => {
    if (!data) return
    setForm({
      name: data.name ?? '',
      connection_point: data.connection_point ?? '',
      consumer: data.consumer ?? '',
      manager: data.manager ?? '',
      address: data.address ?? '',
      phone: data.phone ?? '',
      phone_alt: data.phone_alt ?? '',
      email: data.email ?? '',
      postal_address: data.postal_address ?? '',
      notes: data.notes ?? '',
      identifier: data.identifier ?? '',
      metering_presence: data.metering_presence ?? '',
      disconnected: data.disconnected ?? '',
    })
  }, [data])

  if (isLoading) return <div className="text-gray-500">Загрузка...</div>
  if (error || !data) return <div className="text-red-700">Запись не найдена</div>

  const fields = fieldsFor(data).filter(([, v]) => (v ?? '').toString().trim().length > 0)
  const editableFields = editableFieldsForCategory(data.category)

  const resetForm = () => {
    setForm({
      name: data.name ?? '',
      connection_point: data.connection_point ?? '',
      consumer: data.consumer ?? '',
      manager: data.manager ?? '',
      address: data.address ?? '',
      phone: data.phone ?? '',
      phone_alt: data.phone_alt ?? '',
      email: data.email ?? '',
      postal_address: data.postal_address ?? '',
      notes: data.notes ?? '',
      identifier: data.identifier ?? '',
      metering_presence: data.metering_presence ?? '',
      disconnected: data.disconnected ?? '',
    })
  }

  const onSubmit = (e: FormEvent) => {
    e.preventDefault()
    updateMutation.mutate(form)
  }

  return (
    <div className="space-y-4">
      <nav className="text-sm space-x-3">
        <Link to="/contacts" className="text-blue-600 hover:underline">← Все категории</Link>
      </nav>

      <div className="bg-white rounded-lg shadow p-5 sm:p-6">
        <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-xs uppercase tracking-wide text-gray-500 mb-1">{categoryLabel(data.category)}</p>
            <h1 className="text-xl font-bold">{shortLabel(data)}</h1>
          </div>
          <button type="button" onClick={() => navigate(-1)} className="w-fit rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100">← Назад</button>
        </div>

        {data.category === 'gspo' && data.sync_status === 'not_matched' && (
          <div className="mb-4 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">
            Синхронизация не прошла{data.sync_note ? `: ${data.sync_note}` : ''}
          </div>
        )}

        {isEditing ? (
          <form onSubmit={onSubmit} className="space-y-4">
            {editableFields.map(([key, label, control]) => (
              <label key={key} className="block">
                <span className="mb-1 block text-sm font-medium text-gray-600">{label}</span>
                {control === 'textarea' ? (
                  <textarea value={(form[key] ?? '') as string} onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))} rows={4} className="w-full rounded border px-3 py-2" />
                ) : control === 'yes_no' ? (
                  <select value={(form[key] ?? '') as string} onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))} className="w-full rounded border px-3 py-2">
                    <option value="">Выбрать...</option>
                    <option value="Да">Да</option>
                    <option value="Нет">Нет</option>
                  </select>
                ) : (
                  <input value={(form[key] ?? '') as string} onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))} className="w-full rounded border px-3 py-2" />
                )}
              </label>
            ))}
            <div className="flex gap-2">
              <button type="submit" disabled={updateMutation.isPending} className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50">
                {updateMutation.isPending ? 'Сохраняю...' : 'Сохранить'}
              </button>
              <button type="button" onClick={() => { resetForm(); setIsEditing(false) }} className="rounded border bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">Отмена</button>
            </div>
          </form>
        ) : (
          <>
            <dl className="divide-y divide-gray-100">
              {fields.map(([label, value, kind]) => (
                <div key={label} className="py-2 sm:flex sm:gap-4">
                  <dt className="font-medium text-gray-600 sm:w-56 shrink-0">{label}</dt>
                  <dd className="flex-1 mt-1 sm:mt-0 whitespace-pre-line">
                    {kind === 'phone' && value ? <a href={`tel:${value}`} className="text-blue-600 hover:underline">{value}</a> : value}
                  </dd>
                </div>
              ))}
            </dl>
          </>
        )}

        <div className="mt-5 flex items-center justify-between border-t pt-4">
          <button type="button" onClick={() => setIsEditing((v) => !v)} className="rounded border px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100">
            {isEditing ? 'Закрыть редактирование' : 'Редактировать'}
          </button>
          <button type="button" onClick={() => deleteMutation.mutate()} disabled={deleteMutation.isPending} className="rounded border border-red-300 px-3 py-1.5 text-sm text-red-700 hover:bg-red-50 disabled:opacity-50">
            {deleteMutation.isPending ? 'Удаляю...' : 'Удалить'}
          </button>
        </div>

        {data.category === 'gspo' && (
          <div className="mt-6 border-t pt-4">
            <h2 className="mb-3 text-base font-semibold">Привязанные приборы учета ГСПО</h2>
            <div className="mb-2 text-sm text-gray-600">UID контакта: {data.identifier || '—'}</div>
            {meteringLinksQuery.isLoading && <div className="text-sm text-gray-500">Загрузка привязок...</div>}
            {!meteringLinksQuery.isLoading && (meteringLinksQuery.data?.links ?? []).length === 0 && (
              <div className="rounded border bg-gray-50 px-3 py-2 text-sm text-gray-600">Нет привязанных приборов учета.</div>
            )}
            {!meteringLinksQuery.isLoading && (meteringLinksQuery.data?.links ?? []).length > 0 && (
              <div className="space-y-2">
                {(meteringLinksQuery.data?.links ?? []).map((item) => {
                  const u = item.uute
                  return (
                    <div key={item.link.id} className="rounded border p-3 text-sm">
                      <div className="font-medium">{u.name || 'Без названия'} (строка #{u.id})</div>
                      <div className="text-gray-600">Адрес: {u.address || '—'}</div>
                      <div className="text-gray-600">UID прибора: {u.identifier || '—'}</div>
                      <div className="text-gray-600">Статус связи: {item.link.status || '—'}</div>
                      <div className="mt-1">
                        <Link to={`/metering/gspo/${u.id}`} className="text-blue-600 hover:underline">Открыть прибор учета</Link>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
