import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link, useParams } from 'react-router-dom'
import { objectsApi } from '../../api/objects'

const LABELS: Record<string, string> = { gspo: 'ГСПО', phys: 'Прочие ФЛ' }

export default function ObjectsList() {
  const { category } = useParams<{ category: string }>()
  const [query, setQuery] = useState('')
  const label = LABELS[category ?? ''] || category
  const { data, isLoading, error } = useQuery({
    queryKey: ['objects', category, query],
    queryFn: () => objectsApi.list(category!, query),
    enabled: !!category,
  })
  const records = data?.records ?? []

  return (
    <div className="space-y-4">
      <nav className="text-sm"><Link to="/objects" className="text-blue-600 hover:underline">← Объекты</Link></nav>
      <div className="rounded-lg bg-white p-5 shadow">
        <h1 className="text-2xl font-bold">Объекты {label}</h1>
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Поиск по имени, адресу, UID" className="mt-3 w-full rounded border px-3 py-2 text-sm sm:max-w-xl" />
      </div>
      <div className="rounded-lg bg-white p-5 shadow">
        {isLoading && <div className="text-sm text-gray-500">Загрузка...</div>}
        {error && <div className="text-sm text-red-700">Не удалось загрузить объекты.</div>}
        <div className="space-y-2">
          {records.map((row) => (
            <Link key={row.id} to={`/objects/${category}/${row.id}`} className="block rounded border p-3 hover:border-blue-300">
              <div className="font-medium">{row.name || '—'}</div>
              <div className="text-sm text-gray-600">{row.address || '—'}</div>
              <div className="text-xs text-gray-500 break-all">UID: {row.identifier || '—'}</div>
            </Link>
          ))}
        </div>
      </div>
    </div>
  )
}
