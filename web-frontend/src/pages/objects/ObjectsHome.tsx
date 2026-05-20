import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { objectsApi } from '../../api/objects'

export default function ObjectsHome() {
  const { data, isLoading, error } = useQuery({ queryKey: ['objects', 'categories'], queryFn: () => objectsApi.categories() })
  const categories = data?.categories ?? []

  return (
    <div className="space-y-4">
      <div className="rounded-lg bg-white p-5 shadow">
        <p className="text-xs uppercase text-gray-500">Реестр объектов</p>
        <h1 className="text-2xl font-bold">Объекты</h1>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {isLoading && <div className="rounded-lg border bg-white p-4 text-sm text-gray-500">Загрузка...</div>}
        {error && <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">Не удалось загрузить категории.</div>}
        {categories.map((cat) => (
          <Link key={cat.key} to={`/objects/${cat.key}`} className="rounded-lg border bg-white p-5 shadow hover:border-blue-300">
            <div className="text-lg font-semibold">{cat.label}</div>
            <div className="mt-1 text-sm text-gray-600">Открыть список объектов</div>
          </Link>
        ))}
      </div>
    </div>
  )
}
