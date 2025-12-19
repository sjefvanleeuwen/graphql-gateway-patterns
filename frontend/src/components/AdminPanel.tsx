import { useState } from 'react';
import { Settings, Users, DollarSign, Save, Plus, Trash2, Edit2 } from 'lucide-react';
import toast from 'react-hot-toast';

interface AccountTier {
  id: string;
  name: string;
  monthlyFee: number;
  requestLimit: number;
  costPerRequest: number;
  features: string[];
}

const defaultTiers: AccountTier[] = [
  {
    id: '1',
    name: 'Free',
    monthlyFee: 0,
    requestLimit: 1000,
    costPerRequest: 0,
    features: ['Basic API access', '1,000 requests/month', 'Community support']
  },
  {
    id: '2',
    name: 'Normal',
    monthlyFee: 29.99,
    requestLimit: 10000,
    costPerRequest: 0.001,
    features: ['Full API access', '10,000 requests/month', 'Email support', 'Analytics dashboard']
  },
  {
    id: '3',
    name: 'Premium',
    monthlyFee: 99.99,
    requestLimit: 100000,
    costPerRequest: 0.0005,
    features: ['Full API access', '100,000 requests/month', 'Priority support', 'Advanced analytics', 'Custom integrations']
  },
  {
    id: '4',
    name: 'Enterprise',
    monthlyFee: 499.99,
    requestLimit: -1, // Unlimited
    costPerRequest: 0.0002,
    features: ['Unlimited API access', 'Dedicated support', 'Custom SLA', 'White-label options', 'On-premise deployment']
  }
];

export default function AdminPanel() {
  const [tiers, setTiers] = useState<AccountTier[]>(defaultTiers);
  const [editingTier, setEditingTier] = useState<AccountTier | null>(null);
  const [isAddingNew, setIsAddingNew] = useState(false);
  const [newFeature, setNewFeature] = useState('');

  const handleSaveTier = () => {
    if (!editingTier) return;
    
    if (isAddingNew) {
      setTiers([...tiers, { ...editingTier, id: Date.now().toString() }]);
      toast.success(`Account tier "${editingTier.name}" created!`);
    } else {
      setTiers(tiers.map(t => t.id === editingTier.id ? editingTier : t));
      toast.success(`Account tier "${editingTier.name}" updated!`);
    }
    setEditingTier(null);
    setIsAddingNew(false);
  };

  const handleDeleteTier = (id: string) => {
    const tier = tiers.find(t => t.id === id);
    setTiers(tiers.filter(t => t.id !== id));
    toast.success(`Account tier "${tier?.name}" deleted!`);
  };

  const handleAddFeature = () => {
    if (!editingTier || !newFeature.trim()) return;
    setEditingTier({
      ...editingTier,
      features: [...editingTier.features, newFeature.trim()]
    });
    setNewFeature('');
  };

  const handleRemoveFeature = (index: number) => {
    if (!editingTier) return;
    setEditingTier({
      ...editingTier,
      features: editingTier.features.filter((_, i) => i !== index)
    });
  };

  const startNewTier = () => {
    setIsAddingNew(true);
    setEditingTier({
      id: '',
      name: '',
      monthlyFee: 0,
      requestLimit: 1000,
      costPerRequest: 0,
      features: []
    });
  };

  return (
    <div className="admin-panel">
      <div className="admin-header">
        <Settings size={32} />
        <h2>Admin Panel - Cost Management</h2>
      </div>

      <div className="admin-section">
        <div className="section-header">
          <Users size={24} />
          <h3>Account Tiers</h3>
          <button className="btn btn-primary" onClick={startNewTier}>
            <Plus size={16} /> Add Tier
          </button>
        </div>

        <div className="tiers-grid">
          {tiers.map(tier => (
            <div key={tier.id} className={`tier-card ${tier.name.toLowerCase()}`}>
              <div className="tier-header">
                <h4>{tier.name}</h4>
                <div className="tier-actions">
                  <button className="btn-icon" onClick={() => setEditingTier(tier)}>
                    <Edit2 size={16} />
                  </button>
                  <button className="btn-icon danger" onClick={() => handleDeleteTier(tier.id)}>
                    <Trash2 size={16} />
                  </button>
                </div>
              </div>
              <div className="tier-price">
                <DollarSign size={20} />
                <span className="price">{tier.monthlyFee.toFixed(2)}</span>
                <span className="period">/month</span>
              </div>
              <div className="tier-stats">
                <div className="stat">
                  <span className="label">Request Limit</span>
                  <span className="value">
                    {tier.requestLimit === -1 ? 'Unlimited' : tier.requestLimit.toLocaleString()}
                  </span>
                </div>
                <div className="stat">
                  <span className="label">Cost/Request</span>
                  <span className="value">${tier.costPerRequest.toFixed(4)}</span>
                </div>
              </div>
              <ul className="tier-features">
                {tier.features.map((feature, index) => (
                  <li key={index}>{feature}</li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>

      {/* Edit/Add Modal */}
      {editingTier && (
        <div className="modal-overlay">
          <div className="modal">
            <h3>{isAddingNew ? 'Add New Tier' : `Edit ${editingTier.name}`}</h3>
            <div className="form-group">
              <label>Tier Name</label>
              <input
                type="text"
                value={editingTier.name}
                onChange={e => setEditingTier({ ...editingTier, name: e.target.value })}
                placeholder="e.g., Premium Plus"
              />
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>Monthly Fee ($)</label>
                <input
                  type="number"
                  value={editingTier.monthlyFee}
                  onChange={e => setEditingTier({ ...editingTier, monthlyFee: parseFloat(e.target.value) || 0 })}
                  step="0.01"
                  min="0"
                />
              </div>
              <div className="form-group">
                <label>Request Limit (-1 for unlimited)</label>
                <input
                  type="number"
                  value={editingTier.requestLimit}
                  onChange={e => setEditingTier({ ...editingTier, requestLimit: parseInt(e.target.value) || 0 })}
                />
              </div>
            </div>
            <div className="form-group">
              <label>Cost per Request ($)</label>
              <input
                type="number"
                value={editingTier.costPerRequest}
                onChange={e => setEditingTier({ ...editingTier, costPerRequest: parseFloat(e.target.value) || 0 })}
                step="0.0001"
                min="0"
              />
            </div>
            <div className="form-group">
              <label>Features</label>
              <div className="features-list">
                {editingTier.features.map((feature, index) => (
                  <div key={index} className="feature-item">
                    <span>{feature}</span>
                    <button className="btn-icon danger" onClick={() => handleRemoveFeature(index)}>
                      <Trash2 size={14} />
                    </button>
                  </div>
                ))}
              </div>
              <div className="add-feature">
                <input
                  type="text"
                  value={newFeature}
                  onChange={e => setNewFeature(e.target.value)}
                  placeholder="Add a feature..."
                  onKeyPress={e => e.key === 'Enter' && handleAddFeature()}
                />
                <button className="btn btn-secondary" onClick={handleAddFeature}>
                  <Plus size={16} />
                </button>
              </div>
            </div>
            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => { setEditingTier(null); setIsAddingNew(false); }}>
                Cancel
              </button>
              <button className="btn btn-primary" onClick={handleSaveTier}>
                <Save size={16} /> Save
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
