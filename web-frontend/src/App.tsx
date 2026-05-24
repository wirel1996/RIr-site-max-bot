import { Navigate, Route, Routes, useLocation, useParams } from 'react-router-dom'
import Layout from './components/Layout'
import Home from './pages/Home'
import Stub from './pages/Stub'
import Login from './pages/auth/Login'
import { useAuth } from './contexts/AuthContext'

import ContactsHome from './pages/contacts/ContactsHome'
import ContactsCategory from './pages/contacts/ContactsCategory'
import ContactsDetail from './pages/contacts/ContactsDetail'
import ContactsSearch from './pages/contacts/ContactsSearch'

import Journal from './pages/journal/Journal'

import AlgorithmsHome from './pages/algorithms/AlgorithmsHome'
import AlgorithmDetail from './pages/algorithms/AlgorithmDetail'
import Devices from './pages/algorithms/Devices'

import ArshinHome from './pages/arshin/ArshinHome'

import BillingHome from './pages/billing/BillingHome'
import BillingObject from './pages/billing/BillingObject'

import VolumeCalc from './pages/calc/VolumeCalc'
import AdminUsers from './pages/admin/AdminUsers'
import MeteringHome from './pages/metering/MeteringHome'
import MeteringList from './pages/metering/MeteringList'
import MeteringDetail from './pages/metering/MeteringDetail'
import WaterRegistry from './pages/metering/WaterRegistry'
import WaterRegistryDetail from './pages/metering/WaterRegistryDetail'
import Profile from './pages/profile/Profile'
import ObjectsHome from './pages/objects/ObjectsHome'
import ObjectsList from './pages/objects/ObjectsList'
import ObjectDetail from './pages/objects/ObjectDetail'

function RequireAuth({ children }: { children: React.ReactNode }) {
  const { state } = useAuth()
  const location = useLocation()

  if (state.status === 'loading') {
    return (
      <div className="min-h-screen flex items-center justify-center text-sm text-gray-500">
        Загрузка...
      </div>
    )
  }

  if (state.status !== 'authed') {
    return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />
  }

  return <>{children}</>
}

function RequireAdmin({ children }: { children: React.ReactNode }) {
  const { user } = useAuth()

  if (user?.role !== 'admin') {
    return <Stub title="403" description="Недостаточно прав." />
  }

  return <>{children}</>
}

function RequireBilling({ children }: { children: React.ReactNode }) {
  const { user } = useAuth()

  if (user?.role === 'limited' || user?.role === 'water_payment') {
    return <Stub title="403" description="Недостаточно прав." />
  }

  return <>{children}</>
}

function RequireNotWaterPaymentOnly({ children }: { children: React.ReactNode }) {
  const { user } = useAuth()

  if (user?.role === 'water_payment') {
    return <Navigate to="/summer-water" replace />
  }

  return <>{children}</>
}

function LegacyWaterDetailRedirect() {
  const { id } = useParams<{ id: string }>()
  return <Navigate to={`/summer-water/${id}`} replace />
}

function ResetTokenRedirect() {
  const { token } = useParams<{ token: string }>()
  if (!token) return <Navigate to="/login" replace />
  return <Navigate to={`/login?reset_token=${encodeURIComponent(token)}`} replace />
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/reset/:token" element={<ResetTokenRedirect />} />

      <Route
        path="/"
        element={
          <RequireAuth>
            <Layout />
          </RequireAuth>
        }
      >
        <Route
          index
          element={
            <RequireNotWaterPaymentOnly>
              <Home />
            </RequireNotWaterPaymentOnly>
          }
        />

        <Route path="contacts" element={<RequireNotWaterPaymentOnly><ContactsHome /></RequireNotWaterPaymentOnly>} />
        <Route path="objects" element={<RequireNotWaterPaymentOnly><ObjectsHome /></RequireNotWaterPaymentOnly>} />
        <Route path="objects/:category" element={<RequireNotWaterPaymentOnly><ObjectsList /></RequireNotWaterPaymentOnly>} />
        <Route path="objects/:category/:id" element={<RequireNotWaterPaymentOnly><ObjectDetail /></RequireNotWaterPaymentOnly>} />
        <Route path="contacts/search" element={<RequireNotWaterPaymentOnly><ContactsSearch /></RequireNotWaterPaymentOnly>} />
        <Route path="contacts/category/:category" element={<RequireNotWaterPaymentOnly><ContactsCategory /></RequireNotWaterPaymentOnly>} />
        <Route path="contacts/:id" element={<RequireNotWaterPaymentOnly><ContactsDetail /></RequireNotWaterPaymentOnly>} />

        <Route path="journal" element={<RequireNotWaterPaymentOnly><Journal /></RequireNotWaterPaymentOnly>} />

        <Route path="algorithms" element={<RequireNotWaterPaymentOnly><AlgorithmsHome /></RequireNotWaterPaymentOnly>} />
        <Route path="algorithms/devices" element={<RequireNotWaterPaymentOnly><Devices /></RequireNotWaterPaymentOnly>} />
        <Route path="algorithms/:key" element={<RequireNotWaterPaymentOnly><AlgorithmDetail /></RequireNotWaterPaymentOnly>} />

        <Route path="arshin" element={<RequireNotWaterPaymentOnly><ArshinHome /></RequireNotWaterPaymentOnly>} />

        <Route path="metering" element={<RequireNotWaterPaymentOnly><MeteringHome /></RequireNotWaterPaymentOnly>} />
        <Route path="metering/water" element={<Navigate to="/summer-water" replace />} />
        <Route path="metering/water/:id" element={<LegacyWaterDetailRedirect />} />
        <Route path="metering/:category" element={<RequireNotWaterPaymentOnly><MeteringList /></RequireNotWaterPaymentOnly>} />
        <Route path="metering/:category/:id" element={<RequireNotWaterPaymentOnly><MeteringDetail /></RequireNotWaterPaymentOnly>} />
        <Route path="summer-water" element={<WaterRegistry />} />
        <Route path="summer-water/:id" element={<RequireNotWaterPaymentOnly><WaterRegistryDetail /></RequireNotWaterPaymentOnly>} />

        <Route
          path="billing"
          element={
            <RequireBilling>
              <BillingHome />
            </RequireBilling>
          }
        />
        <Route
          path="billing/:row"
          element={
            <RequireBilling>
              <BillingObject />
            </RequireBilling>
          }
        />

        <Route path="calculations" element={<RequireNotWaterPaymentOnly><VolumeCalc /></RequireNotWaterPaymentOnly>} />
        <Route path="profile" element={<Profile />} />

        <Route
          path="admin"
          element={
            <RequireAdmin>
              <AdminUsers />
            </RequireAdmin>
          }
        />

        <Route path="*" element={<Stub title="404" description="Страница не найдена." />} />
      </Route>
    </Routes>
  )
}
