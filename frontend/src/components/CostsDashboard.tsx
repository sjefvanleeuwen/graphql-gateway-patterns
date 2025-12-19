import { useState, useEffect } from 'react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import { Line, Bar, Doughnut } from 'react-chartjs-2';
import { TrendingUp, Users, DollarSign, Activity, Calendar, RefreshCw } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import toast from 'react-hot-toast';

// Register Chart.js components
ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

// Mock data for the dashboard
const generateMockData = () => {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  
  return {
    monthlyCosts: months.map(() => Math.floor(Math.random() * 5000) + 1000),
    monthlyRequests: months.map(() => Math.floor(Math.random() * 100000) + 10000),
    usersByTier: {
      Free: 1250,
      Normal: 450,
      Premium: 180,
      Enterprise: 25
    },
    revenueByTier: {
      Free: 0,
      Normal: 13495.50,
      Premium: 17998.20,
      Enterprise: 12499.75
    },
    dailyCosts: Array.from({ length: 30 }, () => Math.floor(Math.random() * 200) + 50),
  };
};

type TimeRange = '7d' | '30d' | '90d' | '1y';

interface UserCostData {
  userId: string;
  userName: string;
  accountTier: string;
  currentWindow: {
    totalCost: number;
    requestCount: number;
    costInEuros: number;
    remainingCost: number;
    maxCost: number;
    isOverBudget: boolean;
  };
  pricing: {
    monthlyFee: number;
    costMultiplier: number;
    costPerRequest: number;
  };
  dailyCosts: Array<{
    date: string;
    totalCost: number;
    requestCount: number;
    costInEuros: number;
  }>;
  recentRequests: Array<{
    timestamp: string;
    operationName: string;
    cost: number;
    costInEuros: number;
    wasAllowed: boolean;
  }>;
}

export default function CostsDashboard() {
  const { user } = useAuth();
  const [timeRange, setTimeRange] = useState<TimeRange>('30d');
  const [userCostData, setUserCostData] = useState<UserCostData | null>(null);
  const [loading, setLoading] = useState(true);
  
  // Adjust data based on user's tier
  const isAdmin = user?.role === 'admin';
  const userTier = user?.accountTier || 'Free';
  
  const data = generateMockData();

  // Fetch real user cost data
  useEffect(() => {
    fetchUserCostData();
  }, []);

  const fetchUserCostData = async () => {
    try {
      setLoading(true);
      const token = localStorage.getItem('jwt_token');
      const response = await fetch('http://localhost:5000/cost/me', {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (!response.ok) {
        throw new Error('Failed to fetch cost data');
      }

      const data = await response.json();
      setUserCostData(data);
    } catch (error) {
      console.error('Error fetching cost data:', error);
      toast.error('Failed to load cost data');
    } finally {
      setLoading(false);
    }
  };
  
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const days = Array.from({ length: 30 }, (_, i) => `Day ${i + 1}`);

  // Line chart - Monthly costs trend
  const costsTrendData = {
    labels: months,
    datasets: [
      {
        label: 'Monthly Costs ($)',
        data: data.monthlyCosts,
        borderColor: 'rgb(99, 102, 241)',
        backgroundColor: 'rgba(99, 102, 241, 0.1)',
        fill: true,
        tension: 0.4,
      },
    ],
  };

  const costsTrendOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false,
      },
      title: {
        display: true,
        text: 'Monthly API Costs Trend',
        color: '#e5e7eb',
        font: { size: 16 }
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        ticks: { color: '#9ca3af', callback: (value: number | string) => `$${value}` }
      },
      x: {
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        ticks: { color: '#9ca3af' }
      }
    },
  };

  // Bar chart - Requests by month
  const requestsData = {
    labels: months,
    datasets: [
      {
        label: 'API Requests',
        data: data.monthlyRequests,
        backgroundColor: 'rgba(34, 197, 94, 0.7)',
        borderColor: 'rgb(34, 197, 94)',
        borderWidth: 1,
      },
    ],
  };

  const requestsOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false,
      },
      title: {
        display: true,
        text: 'Monthly API Requests',
        color: '#e5e7eb',
        font: { size: 16 }
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        ticks: { color: '#9ca3af' }
      },
      x: {
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        ticks: { color: '#9ca3af' }
      }
    },
  };

  // Doughnut chart - Users by tier
  const usersByTierData = {
    labels: Object.keys(data.usersByTier),
    datasets: [
      {
        data: Object.values(data.usersByTier),
        backgroundColor: [
          'rgba(156, 163, 175, 0.8)',
          'rgba(59, 130, 246, 0.8)',
          'rgba(168, 85, 247, 0.8)',
          'rgba(234, 179, 8, 0.8)',
        ],
        borderColor: [
          'rgb(156, 163, 175)',
          'rgb(59, 130, 246)',
          'rgb(168, 85, 247)',
          'rgb(234, 179, 8)',
        ],
        borderWidth: 2,
      },
    ],
  };

  const doughnutOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'bottom' as const,
        labels: { color: '#e5e7eb' }
      },
      title: {
        display: true,
        text: 'Users by Account Tier',
        color: '#e5e7eb',
        font: { size: 16 }
      },
    },
  };

  // Bar chart - Revenue by tier
  const revenueByTierData = {
    labels: Object.keys(data.revenueByTier),
    datasets: [
      {
        label: 'Revenue ($)',
        data: Object.values(data.revenueByTier),
        backgroundColor: [
          'rgba(156, 163, 175, 0.7)',
          'rgba(59, 130, 246, 0.7)',
          'rgba(168, 85, 247, 0.7)',
          'rgba(234, 179, 8, 0.7)',
        ],
        borderColor: [
          'rgb(156, 163, 175)',
          'rgb(59, 130, 246)',
          'rgb(168, 85, 247)',
          'rgb(234, 179, 8)',
        ],
        borderWidth: 1,
      },
    ],
  };

  const revenueOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false,
      },
      title: {
        display: true,
        text: 'Revenue by Account Tier',
        color: '#e5e7eb',
        font: { size: 16 }
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        ticks: { color: '#9ca3af', callback: (value: number | string) => `$${value}` }
      },
      x: {
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        ticks: { color: '#9ca3af' }
      }
    },
  };

  // Line chart - Daily costs (detailed view)
  const dailyCostsData = {
    labels: days,
    datasets: [
      {
        label: 'Daily Costs ($)',
        data: data.dailyCosts,
        borderColor: 'rgb(244, 114, 182)',
        backgroundColor: 'rgba(244, 114, 182, 0.1)',
        fill: true,
        tension: 0.3,
      },
    ],
  };

  const dailyCostsOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false,
      },
      title: {
        display: true,
        text: 'Daily Cost Breakdown (Last 30 Days)',
        color: '#e5e7eb',
        font: { size: 16 }
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        ticks: { color: '#9ca3af', callback: (value: number | string) => `$${value}` }
      },
      x: {
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        ticks: { color: '#9ca3af', maxTicksLimit: 10 }
      }
    },
  };

  // Calculate totals
  const totalCosts = data.monthlyCosts.reduce((a, b) => a + b, 0);
  const totalRequests = data.monthlyRequests.reduce((a, b) => a + b, 0);
  const totalUsers = Object.values(data.usersByTier).reduce((a, b) => a + b, 0);
  const totalRevenue = Object.values(data.revenueByTier).reduce((a, b) => a + b, 0);

  // User-specific data adjustments
  const userCosts = isAdmin ? totalCosts : (userCostData?.currentWindow.costInEuros || 0);
  const userRequests = isAdmin ? totalRequests : (userCostData?.currentWindow.requestCount || 0);
  const costPerRequest = userCostData?.pricing.costPerRequest || 0;
  const monthlyFee = userCostData?.pricing.monthlyFee || 0;

  if (loading) {
    return (
      <div className="dashboard">
        <div className="dashboard-header">
          <div className="dashboard-title">
            <TrendingUp size={32} />
            <h2>Loading...</h2>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <div className="dashboard-title">
          <TrendingUp size={32} />
          <h2>{isAdmin ? 'Admin Costs Analysis Dashboard' : `My Usage Dashboard - ${userTier}`}</h2>
        </div>
        <div className="time-range-selector">
          <button className="btn-icon" onClick={fetchUserCostData} title="Refresh">
            <RefreshCw size={18} />
          </button>
          <Calendar size={18} />
          {(['7d', '30d', '90d', '1y'] as TimeRange[]).map((range) => (
            <button
              key={range}
              className={`time-btn ${timeRange === range ? 'active' : ''}`}
              onClick={() => setTimeRange(range)}
            >
              {range}
            </button>
          ))}
        </div>
      </div>

      {/* KPI Cards */}
      <div className="kpi-grid">
        <div className="kpi-card">
          <div className="kpi-icon costs">
            <DollarSign size={24} />
          </div>
          <div className="kpi-content">
            <span className="kpi-label">{isAdmin ? 'Total Costs (YTD)' : 'My Costs (Current Window)'}</span>
            <span className="kpi-value">
              {isAdmin ? `$${userCosts.toLocaleString()}` : `€${userCosts.toFixed(4)}`}
            </span>
            <span className="kpi-change positive">
              {isAdmin ? '+12.5% vs last year' : `Based on ${userCostData?.currentWindow.totalCost} complexity units`}
            </span>
          </div>
        </div>
        <div className="kpi-card">
          <div className="kpi-icon requests">
            <Activity size={24} />
          </div>
          <div className="kpi-content">
            <span className="kpi-label">{isAdmin ? 'Total Requests' : 'My Requests'}</span>
            <span className="kpi-value">{userRequests.toLocaleString()}</span>
            <span className="kpi-change positive">
              {userCostData?.currentWindow.remainingCost 
                ? `${userCostData.currentWindow.remainingCost} complexity remaining` 
                : 'No data'}
            </span>
          </div>
        </div>
        {isAdmin ? (
          <>
            <div className="kpi-card">
              <div className="kpi-icon users">
                <Users size={24} />
              </div>
              <div className="kpi-content">
                <span className="kpi-label">Total Users</span>
                <span className="kpi-value">{totalUsers.toLocaleString()}</span>
                <span className="kpi-change positive">+156 new this month</span>
              </div>
            </div>
            <div className="kpi-card">
              <div className="kpi-icon revenue">
                <TrendingUp size={24} />
              </div>
              <div className="kpi-content">
                <span className="kpi-label">Total Revenue</span>
                <span className="kpi-value">${totalRevenue.toLocaleString()}</span>
                <span className="kpi-change positive">+15.2% vs last month</span>
              </div>
            </div>
          </>
        ) : (
          <>
            <div className="kpi-card">
              <div className="kpi-icon users">
                <Activity size={24} />
              </div>
              <div className="kpi-content">
                <span className="kpi-label">Cost Per Request</span>
                <span className="kpi-value">€{costPerRequest.toFixed(6)}</span>
                <span className="kpi-change">Multiplier: {userCostData?.pricing.costMultiplier.toFixed(6)}</span>
              </div>
            </div>
            <div className="kpi-card">
              <div className="kpi-icon revenue">
                <TrendingUp size={24} />
              </div>
              <div className="kpi-content">
                <span className="kpi-label">Monthly Subscription</span>
                <span className="kpi-value">€{monthlyFee.toFixed(2)}</span>
                <span className="kpi-change">{userTier} tier</span>
              </div>
            </div>
          </>
        )}
      </div>

      {/* Charts Grid */}
      {isAdmin && (
        <div className="charts-grid">
          <div className="chart-card large">
            <Line data={costsTrendData} options={costsTrendOptions} />
          </div>
          <div className="chart-card">
            <Doughnut data={usersByTierData} options={doughnutOptions} />
          </div>
          <div className="chart-card large">
            <Bar data={requestsData} options={requestsOptions} />
          </div>
          <div className="chart-card">
            <Bar data={revenueByTierData} options={revenueOptions} />
          </div>
          <div className="chart-card full-width">
            <Line data={dailyCostsData} options={dailyCostsOptions} />
          </div>
        </div>
      )}
      
      {!isAdmin && userCostData && (
        <div className="charts-grid">
          <div className="chart-card full-width">
            <Line 
              data={{
                labels: userCostData.dailyCosts.map(d => new Date(d.date).toLocaleDateString()),
                datasets: [{
                  label: 'Daily Costs (€)',
                  data: userCostData.dailyCosts.map(d => d.costInEuros),
                  borderColor: 'rgb(244, 114, 182)',
                  backgroundColor: 'rgba(244, 114, 182, 0.1)',
                  fill: true,
                  tension: 0.3,
                }]
              }}
              options={{
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                  legend: { display: false },
                  title: {
                    display: true,
                    text: 'Daily Cost Breakdown (Euros)',
                    color: '#e5e7eb',
                    font: { size: 16 }
                  },
                },
                scales: {
                  y: {
                    beginAtZero: true,
                    grid: { color: 'rgba(255, 255, 255, 0.1)' },
                    ticks: { color: '#9ca3af', callback: (value: number | string) => `€${value}` }
                  },
                  x: {
                    grid: { color: 'rgba(255, 255, 255, 0.1)' },
                    ticks: { color: '#9ca3af', maxTicksLimit: 10 }
                  }
                },
              }}
            />
          </div>
          <div className="chart-card large">
            <Bar 
              data={{
                labels: userCostData.dailyCosts.map(d => new Date(d.date).toLocaleDateString()),
                datasets: [{
                  label: 'Requests',
                  data: userCostData.dailyCosts.map(d => d.requestCount),
                  backgroundColor: 'rgba(34, 197, 94, 0.7)',
                  borderColor: 'rgb(34, 197, 94)',
                  borderWidth: 1,
                }]
              }}
              options={{
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                  legend: { display: false },
                  title: {
                    display: true,
                    text: 'Daily Request Count',
                    color: '#e5e7eb',
                    font: { size: 16 }
                  },
                },
                scales: {
                  y: {
                    beginAtZero: true,
                    grid: { color: 'rgba(255, 255, 255, 0.1)' },
                    ticks: { color: '#9ca3af' }
                  },
                  x: {
                    grid: { color: 'rgba(255, 255, 255, 0.1)' },
                    ticks: { color: '#9ca3af', maxTicksLimit: 10 }
                  }
                },
              }}
            />
          </div>
          <div className="chart-card">
            <Bar 
              data={{
                labels: userCostData.dailyCosts.map(d => new Date(d.date).toLocaleDateString()),
                datasets: [{
                  label: 'Complexity Cost',
                  data: userCostData.dailyCosts.map(d => d.totalCost),
                  backgroundColor: 'rgba(99, 102, 241, 0.7)',
                  borderColor: 'rgb(99, 102, 241)',
                  borderWidth: 1,
                }]
              }}
              options={{
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                  legend: { display: false },
                  title: {
                    display: true,
                    text: 'Daily Query Complexity',
                    color: '#e5e7eb',
                    font: { size: 16 }
                  },
                },
                scales: {
                  y: {
                    beginAtZero: true,
                    grid: { color: 'rgba(255, 255, 255, 0.1)' },
                    ticks: { color: '#9ca3af' }
                  },
                  x: {
                    grid: { color: 'rgba(255, 255, 255, 0.1)' },
                    ticks: { color: '#9ca3af', maxTicksLimit: 10 }
                  }
                },
              }}
            />
          </div>
        </div>
      )}

      {/* Cost Breakdown Table - Admin Only */}
      {isAdmin && (
        <div className="cost-table-section">
        <h3>Monthly Cost Breakdown by Tier</h3>
        <table className="cost-table">
          <thead>
            <tr>
              <th>Account Tier</th>
              <th>Users</th>
              <th>Avg Requests/User</th>
              <th>Cost/User</th>
              <th>Total Revenue</th>
              <th>Profit Margin</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><span className="tier-badge free">Free</span></td>
              <td>1,250</td>
              <td>850</td>
              <td>$0.00</td>
              <td>$0.00</td>
              <td>-$425.00</td>
            </tr>
            <tr>
              <td><span className="tier-badge normal">Normal</span></td>
              <td>450</td>
              <td>7,500</td>
              <td>$29.99</td>
              <td>$13,495.50</td>
              <td className="positive">+$10,120.50</td>
            </tr>
            <tr>
              <td><span className="tier-badge premium">Premium</span></td>
              <td>180</td>
              <td>45,000</td>
              <td>$99.99</td>
              <td>$17,998.20</td>
              <td className="positive">+$13,948.20</td>
            </tr>
            <tr>
              <td><span className="tier-badge enterprise">Enterprise</span></td>
              <td>25</td>
              <td>250,000</td>
              <td>$499.99</td>
              <td>$12,499.75</td>
              <td className="positive">+$9,999.75</td>
            </tr>
          </tbody>
          <tfoot>
            <tr>
              <td><strong>Total</strong></td>
              <td><strong>1,905</strong></td>
              <td>-</td>
              <td>-</td>
              <td><strong>$43,993.45</strong></td>
              <td className="positive"><strong>+$33,643.45</strong></td>
            </tr>
          </tfoot>
        </table>
      </div>
      )}
      
      {/* User Request History */}
      {!isAdmin && userCostData && userCostData.recentRequests.length > 0 && (
        <div className="cost-table-section">
          <h3>Recent Query Costs</h3>
          <table className="cost-table">
            <thead>
              <tr>
                <th>Time</th>
                <th>Operation</th>
                <th>Complexity</th>
                <th>Cost (€)</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {userCostData.recentRequests.slice(-15).reverse().map((req, index) => (
                <tr key={index}>
                  <td>{new Date(req.timestamp).toLocaleTimeString()}</td>
                  <td>{req.operationName || 'Anonymous'}</td>
                  <td>{req.cost}</td>
                  <td>€{req.costInEuros.toFixed(6)}</td>
                  <td>
                    <span className={`status-badge ${req.wasAllowed ? 'success' : 'error'}`}>
                      {req.wasAllowed ? 'Allowed' : 'Denied'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
