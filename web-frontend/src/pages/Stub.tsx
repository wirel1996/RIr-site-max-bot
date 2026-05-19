import { Link } from 'react-router-dom'

type StubProps = {
  title: string
  description?: string
}

export default function Stub({ title, description }: StubProps) {
  return (
    <div className="bg-white rounded-lg shadow p-8 text-center">
      <h1 className="text-2xl font-bold mb-2">{title}</h1>
      <p className="text-gray-600">{description ?? 'Раздел в разработке.'}</p>
      <Link to="/" className="text-blue-600 hover:underline mt-4 inline-block">
        ← На главную
      </Link>
    </div>
  )
}
