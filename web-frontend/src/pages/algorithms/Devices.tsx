import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { useState } from 'react'
import { algorithmsApi, type DeviceNode } from '../../api/algorithms'

function DeviceItem({ node, depth = 0 }: { node: DeviceNode; depth?: number }) {
  const [open, setOpen] = useState(depth < 1)
  const hasChildren = node.children && node.children.length > 0

  return (
    <div>
      <div
        className={`py-2 ${hasChildren ? 'cursor-pointer hover:bg-gray-50 rounded' : ''}`}
        onClick={() => hasChildren && setOpen(!open)}
        style={{ paddingLeft: depth * 16 }}
      >
        <span className="font-medium">
          {hasChildren ? (open ? '📂 ' : '📁 ') : '📄 '}
          {node.title}
        </span>
      </div>
      {!hasChildren && node.text && (
        <pre
          className="whitespace-pre-wrap text-sm text-gray-700 bg-gray-50 rounded p-3 my-1"
          style={{ marginLeft: (depth + 1) * 16 }}
        >
          {node.text}
        </pre>
      )}
      {open &&
        node.children?.map((child, i) => (
          <DeviceItem key={i} node={child} depth={depth + 1} />
        ))}
    </div>
  )
}

export default function Devices() {
  const { data, isLoading } = useQuery({
    queryKey: ['devices'],
    queryFn: () => algorithmsApi.devicesTree(),
  })

  return (
    <div className="space-y-4">
      <nav className="text-sm">
        <Link to="/algorithms" className="text-blue-600 hover:underline">
          ← К алгоритмам
        </Link>
      </nav>
      <h1 className="text-2xl font-bold">📚 Приборы учёта</h1>

      {isLoading && <div className="text-gray-500">Загрузка...</div>}

      {data && (
        <div className="bg-white rounded-lg shadow p-4">
          <DeviceItem node={data.tree} />
        </div>
      )}
    </div>
  )
}
