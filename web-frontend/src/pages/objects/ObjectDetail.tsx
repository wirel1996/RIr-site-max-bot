import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { objectsApi } from '../../api/objects'
import { contactsApi } from '../../api/contacts'
import { useAuth } from '../../contexts/AuthContext'

const LABELS: Record<string, string> = { gspo: 'ГСПО', phys: 'Прочие ФЛ' }

function todayRu() {
  return new Date().toLocaleDateString('ru-RU')
}

function defaultActorName(
  authors: Array<{ login: string; name: string }>,
  login: string | undefined,
  fallbackName: string | undefined,
) {
  if (!login) return ''
  const hit = authors.find((a) => a.login === login)
  if (hit) return hit.name
  if (fallbackName && authors.some((a) => a.name === fallbackName)) return fallbackName
  return ''
}

export default function ObjectDetail() {
  const { category, id } = useParams<{ category: string; id: string }>()
  const queryClient = useQueryClient()
  const { user } = useAuth()
  const label = LABELS[category ?? ''] || category
  const authorsQuery = useQuery({
    queryKey: ['objects', 'switch-act-authors'],
    queryFn: () => objectsApi.switchActAuthors(),
  })
  const actAuthors = authorsQuery.data?.authors ?? []
  const { data, isLoading, error } = useQuery({
    queryKey: ['objects', category, 'detail', id],
    queryFn: () => objectsApi.detail(category!, Number(id)),
    enabled: !!category && !!id,
  })
  const [form, setForm] = useState({ name: '', address: '' })
  const [switchForm, setSwitchForm] = useState({
    kind: 'disconnect' as 'disconnect' | 'connect',
    event_date: todayRu(),
    places: ['ИТП'] as string[],
    sealNumbers: ['', ''],
    actor_name: '',
  })
  const [switchModalKind, setSwitchModalKind] = useState<'disconnect' | 'connect' | null>(null)

  useEffect(() => {
    if (!data) return
    setForm({ name: data.object.name || '', address: data.object.address || '' })
  }, [data])

  const updateMutation = useMutation({
    mutationFn: () => contactsApi.updateRegistryObject(Number(id), form),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['objects'] })
      await queryClient.invalidateQueries({ queryKey: ['contacts'] })
    },
  })

  const createSwitchMutation = useMutation({
    mutationFn: () => objectsApi.createSwitchEvent(category!, Number(id), {
      kind: switchForm.kind,
      event_date: switchForm.event_date,
      place: switchForm.places.join(', '),
      seal_numbers: switchForm.sealNumbers.map((item) => item.trim()).filter(Boolean),
      actor_name: switchForm.actor_name,
    }),
    onSuccess: async () => {
      setSwitchForm((current) => ({ ...current, event_date: todayRu(), sealNumbers: ['', ''], actor_name: '' }))
      setSwitchModalKind(null)
      await queryClient.invalidateQueries({ queryKey: ['objects', category, 'detail', id] })
      await queryClient.invalidateQueries({ queryKey: ['objects'] })
      await queryClient.invalidateQueries({ queryKey: ['contacts'] })
      await queryClient.invalidateQueries({ queryKey: ['metering', 'water'] })
    },
  })

  if (isLoading) return <div className="text-gray-500">Загрузка...</div>
  if (error || !data) return <div className="text-red-700">Объект не найден</div>

  return (
    <div className="space-y-4">
      <nav className="text-sm">
        <Link to={`/objects/${category}`} className="text-blue-600 hover:underline">← Объекты {label}</Link>
      </nav>

      <div className="rounded-lg bg-white p-5 shadow">
        <h1 className="text-2xl font-bold">{data.object.name || 'Без названия'}</h1>
        <p className="text-sm text-gray-600">{data.object.address || '—'}</p>
        <p className="mt-1 break-all text-xs text-gray-500">UID: {data.object.identifier || '—'}</p>
      </div>

      <div className="rounded-lg bg-white p-5 shadow">
        <h2 className="mb-3 font-semibold">Редактирование объекта</h2>
        <div className="grid gap-3 md:grid-cols-2">
          <input value={form.name} onChange={(e) => setForm((c) => ({ ...c, name: e.target.value }))} placeholder="Имя" className="rounded border px-3 py-2" />
          <input value={form.address} onChange={(e) => setForm((c) => ({ ...c, address: e.target.value }))} placeholder="Адрес" className="rounded border px-3 py-2" />
        </div>
        <button type="button" onClick={() => updateMutation.mutate()} className="mt-3 rounded bg-blue-600 px-4 py-2 text-sm text-white">Сохранить</button>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <section className="rounded-lg bg-white p-5 shadow">
          <h3 className="mb-3 font-semibold">Контакты</h3>
          {!data.contacts[0] && <p className="text-sm text-gray-500">Нет связанного контакта.</p>}
          {data.contacts[0] && (
            <div className="rounded border p-2 text-sm">
              <div className="font-medium">{data.contacts[0].name || '—'}</div>
              <div className="text-gray-600">{data.contacts[0].address || '—'}</div>
              <div className="mt-1">
                <Link to={`/contacts/${data.contacts[0].id}`} className="text-blue-700 hover:underline">Открыть</Link>
              </div>
            </div>
          )}
        </section>

        <section className="rounded-lg bg-white p-5 shadow">
          <h3 className="mb-3 font-semibold">Приборы учета</h3>
          {!data.uute[0] && <p className="text-sm text-gray-500">Нет связанного прибора.</p>}
          {data.uute[0] && (
            <div className="rounded border p-2 text-sm">
              <div className="font-medium">{data.uute[0].name || '—'}</div>
              <div className="text-gray-600">{data.uute[0].address || '—'}</div>
              <div className="mt-1">
                <Link to={`/metering/${data.uute[0].category || 'gspo'}/${data.uute[0].id}`} className="text-blue-700 hover:underline">Открыть</Link>
              </div>
            </div>
          )}
        </section>

        <section className="rounded-lg bg-white p-5 shadow">
          <h3 className="mb-3 font-semibold">Вода на лето</h3>
          {!data.water[0] && <p className="text-sm text-gray-500">Нет связанной записи.</p>}
          {data.water[0] && (
            <div className="rounded border p-2 text-sm">
              <div className="font-medium">{data.water[0].gspo_name || '—'}</div>
              <div className="text-gray-600">{data.water[0].standalone_address || '—'}</div>
              {data.water[0].third_party_disconnection && (
                <div className="mt-2 text-xs text-gray-600">Отключение сторонних: {data.water[0].third_party_disconnection}</div>
              )}
              {data.water[0].third_party_disconnection_note && (
                <div className="mt-1 whitespace-pre-wrap text-xs text-gray-600">{data.water[0].third_party_disconnection_note}</div>
              )}
              <div className="mt-1">
                <Link to={`/summer-water/${data.water[0].id}`} className="text-blue-700 hover:underline">Открыть</Link>
              </div>
            </div>
          )}
        </section>
      </div>

      <section className="rounded-lg bg-white p-5 shadow">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-semibold">Включение/отключение</h3>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => {
                setSwitchForm({
                  kind: 'disconnect',
                  event_date: todayRu(),
                  places: ['ИТП'],
                  sealNumbers: ['', ''],
                  actor_name: defaultActorName(actAuthors, user?.login, user?.name),
                })
                setSwitchModalKind('disconnect')
              }}
              className="rounded bg-red-600 px-4 py-2 text-sm text-white hover:bg-red-700"
            >
              Отключение
            </button>
            <button
              type="button"
              onClick={() => {
                setSwitchForm({
                  kind: 'connect',
                  event_date: todayRu(),
                  places: ['ИТП'],
                  sealNumbers: ['', ''],
                  actor_name: defaultActorName(actAuthors, user?.login, user?.name),
                })
                setSwitchModalKind('connect')
              }}
              className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700"
            >
              Включение
            </button>
          </div>
        </div>
        {switchModalKind && (
          <div className="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-black/40 p-4 pt-12">
            <div className="w-full max-w-3xl rounded-lg bg-white p-5 shadow-xl">
              <div className="mb-4 flex items-center justify-between gap-3">
                <h3 className="text-lg font-semibold">{switchModalKind === 'disconnect' ? 'Акт отключения' : 'Акт включения'}</h3>
                <button
                  type="button"
                  onClick={() => setSwitchModalKind(null)}
                  className="rounded border px-3 py-1.5 text-sm hover:bg-gray-50"
                >
                  Закрыть
                </button>
              </div>
        <form
          className="grid gap-3 md:grid-cols-3"
          onSubmit={(e) => {
            e.preventDefault()
            createSwitchMutation.mutate()
          }}
        >
          <label className="text-sm">
            Дата
            <input
              value={switchForm.event_date}
              onChange={(e) => setSwitchForm((current) => ({ ...current, event_date: e.target.value }))}
              className="mt-1 w-full rounded border px-3 py-2"
              placeholder="ДД.ММ.ГГГГ"
            />
          </label>
          {switchForm.kind === 'disconnect' && (
            <label className="text-sm">
              Место отключения
              <div className="mt-1 flex min-h-[42px] flex-wrap gap-2 rounded border px-3 py-2">
                {['ИТП', 'Граница', 'Ответвление'].map((place) => (
                  <label key={place} className="flex items-center gap-1 text-sm">
                    <input
                      type="checkbox"
                      checked={switchForm.places.includes(place)}
                      onChange={(e) => setSwitchForm((current) => {
                        const places = e.target.checked
                          ? [...current.places, place]
                          : current.places.filter((item) => item !== place)
                        return { ...current, places }
                      })}
                    />
                    <span>{place}</span>
                  </label>
                ))}
              </div>
            </label>
          )}
          <label className="text-sm">
            Кто составлял акт
            <select
              value={switchForm.actor_name}
              onChange={(e) => setSwitchForm((current) => ({ ...current, actor_name: e.target.value }))}
              className="mt-1 w-full rounded border px-3 py-2"
              disabled={authorsQuery.isLoading}
            >
              <option value="">{authorsQuery.isLoading ? 'Загрузка...' : 'Выбрать...'}</option>
              {actAuthors.map((author) => (
                <option key={author.login} value={author.name}>
                  {author.name}
                </option>
              ))}
            </select>
          </label>
          <div className="flex items-end">
            <button
              type="submit"
              disabled={createSwitchMutation.isPending}
              className="w-full rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
            >
              {createSwitchMutation.isPending ? 'Сохраняю...' : 'Сохранить'}
            </button>
          </div>
          {switchForm.kind === 'disconnect' && (
            <div className="md:col-span-4">
              <div className="mb-2 text-sm font-medium">Пломбы отключения</div>
              <div className="grid gap-2 md:grid-cols-3">
                {switchForm.sealNumbers.map((seal, index) => (
                  <label key={index} className="text-sm">
                    Пломба {index + 1}
                    <div className="mt-1 flex gap-2">
                      <input
                        value={seal}
                        onChange={(e) => setSwitchForm((current) => {
                          const sealNumbers = [...current.sealNumbers]
                          sealNumbers[index] = e.target.value
                          return { ...current, sealNumbers }
                        })}
                        className="w-full rounded border px-3 py-2"
                      />
                      {index >= 2 && (
                        <button
                          type="button"
                          onClick={() => setSwitchForm((current) => ({
                            ...current,
                            sealNumbers: current.sealNumbers.filter((_, itemIndex) => itemIndex !== index),
                          }))}
                          className="rounded border px-3 py-2 text-sm text-red-700 hover:bg-red-50"
                        >
                          Убрать
                        </button>
                      )}
                    </div>
                  </label>
                ))}
              </div>
              <button
                type="button"
                onClick={() => setSwitchForm((current) => ({ ...current, sealNumbers: [...current.sealNumbers, ''] }))}
                className="mt-2 rounded border px-3 py-2 text-sm hover:bg-gray-50"
              >
                Добавить пломбу
              </button>
            </div>
          )}
        </form>
        {createSwitchMutation.error && (
          <div className="mt-3 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">
            {createSwitchMutation.error.message}
          </div>
        )}
            </div>
          </div>
        )}
        <div className="mt-4 overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-gray-100 text-left">
              <tr>
                <th className="px-3 py-2">Действие</th>
                <th className="px-3 py-2">Рег. номер акта</th>
                <th className="px-3 py-2">Дата</th>
                <th className="px-3 py-2">Место</th>
                <th className="px-3 py-2">Пломбы</th>
                <th className="px-3 py-2">Кто составлял</th>
              </tr>
            </thead>
            <tbody>
              {(data.switch_events ?? []).map((event) => (
                <tr key={event.id} className="border-t">
                  <td className="px-3 py-2">{event.kind === 'disconnect' ? 'Отключение' : 'Включение'}</td>
                  <td className="px-3 py-2">{event.act_number || '—'}</td>
                  <td className="px-3 py-2">{event.event_date || '—'}</td>
                  <td className="px-3 py-2">{event.place || '—'}</td>
                  <td className="px-3 py-2">{event.seal_numbers?.length ? event.seal_numbers.join(', ') : '—'}</td>
                  <td className="px-3 py-2">{event.actor_name || '—'}</td>
                </tr>
              ))}
              {(data.switch_events ?? []).length === 0 && (
                <tr>
                  <td className="px-3 py-3 text-gray-500" colSpan={6}>Записей пока нет.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}
