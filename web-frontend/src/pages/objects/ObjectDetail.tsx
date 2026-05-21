import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { objectsApi } from '../../api/objects'
import { contactsApi } from '../../api/contacts'

const LABELS: Record<string, string> = { gspo: 'ГСПО', phys: 'Прочие ФЛ' }

export default function ObjectDetail() {
  const { category, id } = useParams<{ category: string; id: string }>()
  const queryClient = useQueryClient()
  const label = LABELS[category ?? ''] || category
  const { data, isLoading, error } = useQuery({
    queryKey: ['objects', category, 'detail', id],
    queryFn: () => objectsApi.detail(category!, Number(id)),
    enabled: !!category && !!id,
  })
  const [form, setForm] = useState({ name: '', address: '' })

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

  if (isLoading) return <div className="text-gray-500">Загрузка...</div>
  if (error || !data) return <div className="text-red-700">Объект не найден</div>

  return (
    <div className="space-y-4">
      <nav className="text-sm"><Link to={`/objects/${category}`} className="text-blue-600 hover:underline">← Объекты {label}</Link></nav>
      <div className="rounded-lg bg-white p-5 shadow">
        <h1 className="text-2xl font-bold">{data.object.name || 'Без названия'}</h1>
        <p className="text-sm text-gray-600">{data.object.address || '—'}</p>
        <p className="text-xs text-gray-500 break-all mt-1">UID: {data.object.identifier || '—'}</p>
      </div>
      <div className="rounded-lg bg-white p-5 shadow">
        <h2 className="font-semibold mb-3">Редактирование объекта</h2>
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
              <div className="mt-1">
                <Link to={`/summer-water/${data.water[0].id}`} className="text-blue-700 hover:underline">Открыть</Link>
              </div>
            </div>
          )}
        </section>
      </div>
    </div>
  )
}
