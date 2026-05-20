import { Link } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { homeRu as t } from '../locales/ru/home'

type Tile = {
  to: string
  title: string
  desc: string
  waterAllowed?: boolean
  billingOnly?: boolean
  adminOnly?: boolean
}

function TileLink({ tile }: { tile: Tile }) {
  return (
    <Link to={tile.to} className="block rounded-lg border border-transparent bg-white p-4 shadow transition hover:border-blue-300 hover:shadow-md">
      <div className="font-semibold text-base">{tile.title}</div>
      <div className="mt-1 text-sm text-gray-500">{tile.desc}</div>
    </Link>
  )
}

export default function Home() {
  const { user } = useAuth()
  const waterOnly = user?.role === 'water_payment'

  const visiblePrimaryTiles = waterOnly ? [] : (t.primaryTiles as readonly Tile[])
  const visibleServiceTiles = (t.serviceTiles as readonly Tile[]).filter((tile) => {
    if (waterOnly) return tile.waterAllowed === true
    if (tile.adminOnly && user?.role !== 'admin') return false
    if (tile.billingOnly && user?.role === 'limited') return false
    return true
  })

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">{t.title}</h1>
        <p className="mt-1 text-sm text-gray-600">{t.subtitle}</p>
      </div>

      {visiblePrimaryTiles.length > 0 && (
        <section>
          <h2 className="mb-3 text-lg font-semibold">{t.sectionsTitle}</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {visiblePrimaryTiles.map((tile) => <TileLink key={tile.to} tile={tile} />)}
          </div>
        </section>
      )}

      {visibleServiceTiles.length > 0 && (
        <section>
          <h2 className="mb-3 text-lg font-semibold">{t.servicesTitle}</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {visibleServiceTiles.map((tile) => <TileLink key={tile.to} tile={tile} />)}
          </div>
        </section>
      )}
    </div>
  )
}
