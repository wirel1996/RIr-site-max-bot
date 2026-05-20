import { useEffect, useState, type FormEvent } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { contactsApi, type RegistryObject } from '../api/contacts'

type Props = {
  objectId: number | null | undefined
  title?: string
  invalidateKeys?: unknown[][]
}

export default function RegistryObjectCard({ objectId, title = 'Карточка объекта', invalidateKeys = [] }: Props) {
  const queryClient = useQueryClient()
  const [isEditing, setIsEditing] = useState(false)
  const [form, setForm] = useState({ name: '', address: '', identifier: '' })

  const query = useQuery({
    queryKey: ['registry-objects', objectId],
    queryFn: () => contactsApi.registryObject(Number(objectId)),
    enabled: !!objectId,
  })

  useEffect(() => {
    const object = query.data
    if (!object) return
    setForm({
      name: object.name ?? '',
      address: object.address ?? '',
      identifier: object.identifier ?? '',
    })
  }, [query.data])

  const mutation = useMutation({
    mutationFn: () => contactsApi.updateRegistryObject(Number(objectId), form),
    onSuccess: (record: RegistryObject) => {
      queryClient.setQueryData(['registry-objects', objectId], record)
      invalidateKeys.forEach((queryKey) => queryClient.invalidateQueries({ queryKey }))
      setIsEditing(false)
    },
  })

  if (!objectId) return null

  const reset = () => {
    if (!query.data) return
    setForm({
      name: query.data.name ?? '',
      address: query.data.address ?? '',
      identifier: query.data.identifier ?? '',
    })
  }

  const onSubmit = (event: FormEvent) => {
    event.preventDefault()
    mutation.mutate()
  }

  return (
    <section className="rounded border border-blue-100 bg-blue-50 p-4 shadow-sm">
      <div className="mb-3 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-base font-semibold text-blue-950">{title}</h2>
          <p className="text-sm text-blue-800">Название, адрес и UID редактируются только здесь.</p>
        </div>
        <button type="button" onClick={() => setIsEditing((value) => !value)} className="w-fit rounded border border-blue-200 bg-white px-3 py-1.5 text-sm text-blue-700 hover:bg-blue-100">
          {isEditing ? 'Закрыть' : 'Редактировать объект'}
        </button>
      </div>

      {query.isLoading && <div className="text-sm text-blue-800">Загрузка объекта...</div>}
      {query.error && <div className="text-sm text-red-700">Не удалось загрузить объект</div>}

      {query.data && !isEditing && (
        <dl className="grid gap-2 text-sm sm:grid-cols-[160px_1fr]">
          <dt className="font-medium text-blue-900">Наименование</dt><dd>{query.data.name || '—'}</dd>
          <dt className="font-medium text-blue-900">Адрес</dt><dd>{query.data.address || '—'}</dd>
          <dt className="font-medium text-blue-900">UID</dt><dd className="break-all">{query.data.identifier || '—'}</dd>
        </dl>
      )}

      {query.data && isEditing && (
        <form onSubmit={onSubmit} className="space-y-3">
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-blue-900">Наименование</span>
            <input value={form.name} onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))} className="w-full rounded border px-3 py-2" />
          </label>
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-blue-900">Адрес</span>
            <input value={form.address} onChange={(event) => setForm((current) => ({ ...current, address: event.target.value }))} className="w-full rounded border px-3 py-2" />
          </label>
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-blue-900">UID</span>
            <input value={form.identifier} onChange={(event) => setForm((current) => ({ ...current, identifier: event.target.value }))} className="w-full rounded border px-3 py-2" />
          </label>
          {mutation.error && <div className="rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">{mutation.error.message}</div>}
          <div className="flex gap-2">
            <button type="submit" disabled={mutation.isPending} className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50">
              {mutation.isPending ? 'Сохраняю...' : 'Сохранить объект'}
            </button>
            <button type="button" onClick={() => { reset(); setIsEditing(false) }} className="rounded border bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">Отмена</button>
          </div>
        </form>
      )}
    </section>
  )
}
