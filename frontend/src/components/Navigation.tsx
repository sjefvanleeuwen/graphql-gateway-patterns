import { ShoppingBag, Settings, BarChart3, LogOut, User, Network } from 'lucide-react';
import { useAuth } from '../context/AuthContext';

export type View = 'shop' | 'admin' | 'dashboard' | 'schema';

interface NavigationProps {
  currentView: View;
  onViewChange: (view: View) => void;
}

export default function Navigation({ currentView, onViewChange }: NavigationProps) {
  const { user, logout } = useAuth();

  return (
    <nav className="main-nav">
      <div className="nav-brand">
        <span className="brand-icon">🚀</span>
        <span className="brand-text">GraphQL Gateway</span>
      </div>
      <div className="nav-links">
        <button
          className={`nav-link ${currentView === 'shop' ? 'active' : ''}`}
          onClick={() => onViewChange('shop')}
        >
          <ShoppingBag size={20} />
          <span>Shop</span>
        </button>
        <button
          className={`nav-link ${currentView === 'admin' ? 'active' : ''}`}
          onClick={() => onViewChange('admin')}
        >
          <Settings size={20} />
          <span>Admin</span>
        </button>
        <button
          className={`nav-link ${currentView === 'dashboard' ? 'active' : ''}`}
          onClick={() => onViewChange('dashboard')}
        >
          <BarChart3 size={20} />
          <span>Dashboard</span>
        </button>
        <button
          className={`nav-link ${currentView === 'schema' ? 'active' : ''}`}
          onClick={() => onViewChange('schema')}
        >
          <Network size={20} />
          <span>Schema</span>
        </button>
      </div>
      {user && (
        <div className="nav-user">
          <div className="user-info">
            <User size={18} />
            <div className="user-details">
              <span className="user-name">{user.name}</span>
              <span className={`user-tier tier-${user.accountTier.toLowerCase()}`}>
                {user.accountTier}
              </span>
            </div>
          </div>
          <button className="btn-logout" onClick={logout} title="Logout">
            <LogOut size={18} />
          </button>
        </div>
      )}
    </nav>
  );
}
