import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { algorithmsApi } from '../../api/algorithms'

export default function AlgorithmsHome() {
  const { data, isLoading } = useQuery({
    queryKey: ['algorithms'],
    queryFn: () => algorithmsApi.list(),
  })

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold">📚 Алгоритмы и информация</h1>

      {isLoading && <div className="text-gray-500">Загрузка...</div>}

      {data && (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {data.items.map((a) => (
            <Link
              key={a.key}
              to={`/algorithms/${a.key}`}
              className="bg-white rounded-lg shadow p-4 hover:shadow-md border border-transparent hover:border-blue-300"
            >
              <div className="font-medium">{a.title}</div>
              <div className="text-xs text-gray-500 mt-1">{a.steps_count} шагов</div>
            </Link>
          ))}
          <Link
            to="/algorithms/devices"
            className="bg-white rounded-lg shadow p-4 hover:shadow-md border border-transparent hover:border-blue-300"
          >
            <div className="font-medium">📚 Приборы учёта</div>
            <div className="text-xs text-gray-500 mt-1">Дерево настроек: ВКТ, СПТ, ТВ7…</div>
          </Link>
        </div>
      )}
    </div>
  )
}
