import { Link } from 'react-router-dom'

export default function MeteringHome() {
  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold">Приборы учета</h1>
        <p className="text-sm text-gray-600">УУТЭ, акты, поверки, пломбы и показания.</p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Link
          to="/metering/gspo"
          className="rounded-lg border border-transparent bg-white p-5 shadow transition hover:border-blue-300"
        >
          <h2 className="font-semibold">ГСПО</h2>
          <p className="mt-2 text-sm text-gray-600">Гаражи, УУТЭ, приборы и последние данные из Excel.</p>
        </Link>
      </div>
    </div>
  )
}
