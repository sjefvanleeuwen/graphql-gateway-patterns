import { useState } from 'react';
import { Toaster } from 'react-hot-toast';
import ProductList from './components/ProductList';
import Notifications from './components/Notifications';
import Navigation from './components/Navigation';
import AdminPanel from './components/AdminPanel';
import CostsDashboard from './components/CostsDashboard';
import SchemaViewer from './components/SchemaViewer';
import Login from './components/Login';
import { AuthProvider, useAuth } from './context/AuthContext';
import './App.css'

type View = 'shop' | 'admin' | 'dashboard' | 'schema';

function AppContent() {
  const { isAuthenticated, user } = useAuth();
  const [currentView, setCurrentView] = useState<View>('shop');
  
  if (!isAuthenticated) {
    return <Login />;
  }

  return (
    <>
      <Toaster position="top-right" />
      <Notifications />
      <Navigation currentView={currentView} onViewChange={setCurrentView} />
      
      <main className="main-content">
        {currentView === 'shop' && (
          <>
            <h1>GraphQL Gateway Shop</h1>
            <div className="card">
              <p>
                Select a product to purchase. The order will be processed asynchronously by the Back Office worker.
              </p>
            </div>
            <ProductList />
          </>
        )}
        
        {currentView === 'admin' && (
          user?.role === 'admin' ? (
            <AdminPanel />
          ) : (
            <div className="access-denied">
              <h2>Access Denied</h2>
              <p>You don't have permission to access the admin panel.</p>
            </div>
          )
        )}
        
        {currentView === 'dashboard' && <CostsDashboard />}
        
        {currentView === 'schema' && <SchemaViewer />}
      </main>
    </>
  )
}

function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
}

export default App

