import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState, type FormEvent } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { contactsApi, type Contact, type ContactUpdatePayload } from '../../api/contacts'
import { meteringApi } from '../../api/metering'
import { shortLabel } from './shortLabel'
import { categoryLabel, editableFieldsForCategory } from './contactDisplay'

type FieldKind = 'text' | 'phone'
type Field = [string, string | null, FieldKind?]

function isNoValue(value: string | null | undefined) {
  return value?.trim().toLocaleLowerCase('ru-RU') === '\u043d\u0435\u0442'
}

function isMeteringAbsentRow(row: { metering_presence?: string | null; uute?: string | null }) {
  return isNoValue(row.metering_presence) || isNoValue(row.uute)
}

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
        ['Точка присоединения', record.connection_point],
        ['Наименование', record.name],
        ['Адрес', record.address],
        ['Потребитель', record.consumer],
        ['Телефон', record.phone, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Наличие ПУ', record.metering_presence],
        ['Отключено', record.disconnected],
        ['Синхронизация', record.sync_status === 'not_matched' ? 'не прошла' : null],
        ['Комментарий синка', record.sync_note],
        ['Идентификатор', record.identifier],
      ]
    case 'phys':
      return [
        ['Потребитель', record.consumer],
        ['Адрес', record.address],
        ['Ф.И.О. руководителя', record.manager],
        ['Телефон', record.phone, 'phone'],
        ['Доп. телефон', record.phone_alt, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Наличие ПУ', record.metering_presence],
        ['Идентификатор', record.identifier],
        ['Ответственные лица', record.notes],
      ]
    case 'legal':
      return [
        ['Наименование', record.name],
        ['Место нахождения', record.address],
        ['Ф.И.О. руководителя', record.manager],
        ['Телефон', record.phone, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Наличие ПУ', record.metering_presence],
        ['Идентификатор', record.identifier],
        ['Ответственные лица', record.notes],
      ]
    case 'budget':
      return [
        ['Наименование', record.name],
        ['Адрес', record.address],
        ['Руководитель', record.manager],
        ['Телефон', record.phone, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Наличие ПУ', record.metering_presence],
        ['Идентификатор', record.identifier],
        ['Ответственные лица', record.notes],
      ]
    case 'iglakovo':
      return [
        ['Название', record.name],
        ['Ф.И.О. руководителя', record.manager],
        ['Адрес', record.address],
        ['Телефон для уведомлений', record.phone, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Наличие ПУ', record.metering_presence],
        ['Идентификатор', record.identifier],
        ['Ответственные лица', record.notes],
      ]
    case 'embedded':
      return [
        ['Наименование', record.name],
        ['Ф.И.О. руководителя', record.manager],
        ['Адрес помещения', record.address],
        ['Ответственные лица', record.notes],
        ['Телефон', record.phone, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Идентификатор', record.identifier],
      ]
    case 'bu2':
      return [
        ['Наименование', record.name],
        ['Ф.И.О. руководителя', record.manager],
        ['Адрес', record.address],
        ['Ответственные лица', record.notes],
        ['Наличие ПУ', record.metering_presence],
        ['Почтовый адрес', record.postal_address],
        ['Идентификатор', record.identifier],
      ]
    default:
      return [
        ['Наименование', record.name],
        ['Потребитель', record.consumer],
        ['Руководитель', record.manager],
        ['Адрес', record.address],
        ['Телефон', record.phone, 'phone'],
        ['Доп. телефон', record.phone_alt, 'phone'],
        ['Email', record.email],
        ['Почтовый адрес', record.postal_address],
        ['Идентификатор', record.identifier],
        ['Примечание', record.notes],
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
  const [selectedUuteId, setSelectedUuteId] = useState('')

  const { data, isLoading, error } = useQuery({
    queryKey: ['contacts', 'detail', id],
    queryFn: () => contactsApi.detail(Number(id)),
    enabled: !!id,
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
    onSuccess: (_result) => {
      queryClient.invalidateQueries({ queryKey: ['contacts'] })
      navigate(backTo, { replace: true })
    },
  })

  const meteringLinksQuery = useQuery({
    queryKey: ['contacts', 'metering-links', id],
    queryFn: () => meteringApi.linksForContact(Number(id)),
    enabled: !!id && data?.category === 'gspo',
  })

  const waterRegistryQuery = useQuery({
    queryKey: ['contacts', 'water-registry', id],
    queryFn: () => meteringApi.waterForContact(Number(id)),
    enabled: !!id && data?.category === 'gspo',
  })

  const createLinkMutation = useMutation({
    mutationFn: (uuteId: number) => meteringApi.createLink(Number(id), uuteId),
    onSuccess: () => {
      setSelectedUuteId('')
      queryClient.invalidateQueries({ queryKey: ['contacts', 'metering-links', id] })
    },
  })

  const deleteLinkMutation = useMutation({
    mutationFn: (uuteId: number) => meteringApi.deleteLink(Number(id), uuteId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['contacts', 'metering-links', id] })
    },
  })

  const meteringAbsent = isNoValue(data?.metering_presence) || (waterRegistryQuery.data?.records.some(isMeteringAbsentRow) ?? false)

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

  const cancelEdit = () => {
    resetForm()
    setIsEditing(false)
  }

  const onSubmit = (e: FormEvent) => {
    e.preventDefault()
    updateMutation.mutate(form)
  }

  const onDelete = () => {
    if (!window.confirm('Удалить этот контакт?')) return
    deleteMutation.mutate()
  }

  const goBack = () => {
    if (window.history.length > 1) {
      navigate(-1)
    } else {
      navigate(backTo)
    }
  }

  return (
    <div className="space-y-4">
      <nav className="text-sm space-x-3">
        <Link to="/contacts" className="text-blue-600 hover:underline">
          ← Все категории
        </Link>
      </nav>

      <div className="bg-white rounded-lg shadow p-5 sm:p-6">
        <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-xs uppercase tracking-wide text-gray-500 mb-1">
              {categoryLabel(data.category)}
            </p>
            <h1 className="text-xl font-bold">{shortLabel(data)}</h1>
          </div>
          <button
            type="button"
            onClick={goBack}
            className="w-fit rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100"
          >
            ← Назад
          </button>
        </div>

        {data.category === 'gspo' && data.sync_status === 'not_matched' && (
          <div className="mb-4 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">
            Синхронизация не прошла
            {data.sync_note ? `: ${data.sync_note}` : ''}
          </div>
        )}

        {isEditing ? (
          <form onSubmit={onSubmit} className="space-y-4">
            {editableFields.map(([key, label, control]) => (
              <label key={key} className="block">
                <span className="mb-1 block text-sm font-medium text-gray-600">{label}</span>
                {control === 'textarea' ? (
                  <textarea
                    value={(form[key] ?? '') as string}
                    onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))}
                    rows={4}
                    className="w-full rounded border px-3 py-2"
                  />
                ) : control === 'yes_no' ? (
                  <select
                    value={(form[key] ?? '') as string}
                    onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))}
                    className="w-full rounded border px-3 py-2"
                  >
                    <option value="">Выберите...</option>
                    <option value="Да">Да</option>
                    <option value="Нет">Нет</option>
                  </select>
                ) : (
                  <input
                    value={(form[key] ?? '') as string}
                    onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))}
                    className="w-full rounded border px-3 py-2"
                  />
                )}
              </label>
            ))}

            {updateMutation.error && (
              <div className="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
                Не удалось сохранить изменения.
              </div>
            )}
            {deleteMutation.error && (
              <div className="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
                Не удалось удалить контакт.
              </div>
            )}

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
                onClick={cancelEdit}
                className="rounded border bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
              >
                Отмена
              </button>
            </div>
          </form>
        ) : (
          <>
            <dl className="divide-y divide-gray-100">
              {fields.map(([label, value, kind]) => (
                <div key={label} className="py-2 sm:flex sm:gap-4">
                  <dt className="font-medium text-gray-600 sm:w-56 shrink-0">{label}</dt>
                  <dd className="flex-1 mt-1 sm:mt-0 whitespace-pre-line">
                    {kind === 'phone' && value ? (
                      <a href={`tel:${value}`} className="text-blue-600 hover:underline">
                        {value}
                      </a>
                    ) : (
                      value
                    )}
                  </dd>
                </div>
              ))}
            </dl>

            {data.category === 'gspo' && (
              <section className="mt-6 rounded border bg-gray-50 p-4">
                <h2 className="mb-3 font-semibold">Приборы учета</h2>
                {waterRegistryQuery.data?.records.length ? (
                  <div className="mb-4 space-y-2">
                    {waterRegistryQuery.data.records.map((row) => (
                      <div key={row.id} className="rounded bg-white p-3 text-sm">
                        <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                          <div>
                            <Link to={`/summer-water/${row.id}`} className="font-medium text-blue-700 hover:underline">
                              Летняя вода: {row.actual_connection_point || row.point_number || 'точка не указана'}
                            </Link>
                            <p className="text-gray-600">{row.gspo_name || row.standalone_address || '—'}</p>
                          </div>
                          <div className="text-left sm:text-right">
                            <p>
                              Наличие ПУ: <span className="font-medium">{row.metering_presence || '—'}</span>
                            </p>
                            <p className="text-gray-600">
                              УУТЭ: {row.uute || '—'}{row.uute_verification_until ? ` · до ${row.uute_verification_until}` : ''}
                            </p>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : null}
                {!meteringAbsent && (
                  <>
                    {meteringLinksQuery.isLoading && <p className="text-sm text-gray-500">Загрузка связей...</p>}
                    {meteringLinksQuery.data?.links.length === 0 && (
                      <p className="text-sm text-gray-500">Связанных приборов пока нет.</p>
                    )}
                    <div className="space-y-2">
                      {meteringLinksQuery.data?.links.map(({ link, uute }) => (
                        <div key={link.id} className="flex flex-col gap-2 rounded bg-white p-3 text-sm sm:flex-row sm:items-center sm:justify-between">
                          <div>
                            <Link to={`/metering/gspo/${uute.id}`} className="font-medium text-blue-700 hover:underline">
                              {uute.name || 'Прибор учета'}
                            </Link>
                            <p className="text-gray-600">{uute.address || '—'}</p>
                            <p className="text-xs text-gray-500">
                              {link.status} · {link.match_score ?? '—'} · {link.match_reason || 'ручная связь'}
                            </p>
                          </div>
                          <button
                            type="button"
                            onClick={() => deleteLinkMutation.mutate(uute.id)}
                            className="w-fit rounded border border-red-200 px-3 py-1.5 text-red-700 hover:bg-red-50"
                          >
                            Убрать связь
                          </button>
                        </div>
                      ))}
                    </div>
                  </>
                )}

                {!meteringAbsent && meteringLinksQuery.data && meteringLinksQuery.data.candidates.length > 0 && (
                  <div className="mt-4 flex flex-col gap-2 sm:flex-row">
                    <select
                      value={selectedUuteId}
                      onChange={(event) => setSelectedUuteId(event.target.value)}
                      className="min-w-0 flex-1 rounded border bg-white px-3 py-2 text-sm"
                    >
                      <option value="">Выбрать прибор для связи...</option>
                      {meteringLinksQuery.data.candidates.map((candidate) => candidate.uute && (
                        <option key={candidate.uute.id} value={candidate.uute.id}>
                          {candidate.score} · {candidate.uute.name} · {candidate.uute.address}
                        </option>
                      ))}
                    </select>
                    <button
                      type="button"
                      disabled={!selectedUuteId || createLinkMutation.isPending}
                      onClick={() => createLinkMutation.mutate(Number(selectedUuteId))}
                      className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
                    >
                      Связать
                    </button>
                  </div>
                )}
              </section>
            )}

            <div className="mt-6 flex gap-2">
              <button
                type="button"
                onClick={() => setIsEditing(true)}
                className="rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100"
              >
                Редактировать
              </button>
              <button
                type="button"
                onClick={onDelete}
                disabled={deleteMutation.isPending}
                className="rounded border border-red-200 bg-white px-3 py-1.5 text-sm text-red-700 hover:bg-red-50 disabled:opacity-50"
              >
                {deleteMutation.isPending ? 'Удаление...' : 'Удалить'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

