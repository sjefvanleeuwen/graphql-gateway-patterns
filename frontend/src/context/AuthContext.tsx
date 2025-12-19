import { createContext, useContext, useState, ReactNode } from 'react';

export interface User {
  id: string;
  email: string;
  name: string;
  accountTier: 'Free' | 'Normal' | 'Premium' | 'Enterprise';
  role: 'user' | 'admin';
  token?: string;
}

interface AuthContextType {
  user: User | null;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => void;
  isAuthenticated: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

// Mock users for demo - passwords must match backend auth endpoint
const MOCK_USERS: Record<string, { password: string; user: User }> = {
  'admin@example.com': {
    password: 'admin123',
    user: {
      id: '1',
      email: 'admin@example.com',
      name: 'Admin User',
      accountTier: 'Enterprise',
      role: 'admin',
    },
  },
  'user@example.com': {
    password: 'user123',
    user: {
      id: '2',
      email: 'user@example.com',
      name: 'Regular User',
      accountTier: 'Premium',
      role: 'user',
    },
  },
  'john@example.com': {
    password: 'user123',
    user: {
      id: '3',
      email: 'john@example.com',
      name: 'John Doe',
      accountTier: 'Premium',
      role: 'user',
    },
  },
  'jane@example.com': {
    password: 'user123',
    user: {
      id: '4',
      email: 'jane@example.com',
      name: 'Jane Smith',
      accountTier: 'Normal',
      role: 'user',
    },
  },
  'viewer@example.com': {
    password: 'viewer123',
    user: {
      id: '5',
      email: 'viewer@example.com',
      name: 'Viewer User',
      accountTier: 'Free',
      role: 'user',
    },
  },
};

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);

  const login = async (email: string, password: string): Promise<boolean> => {
    try {
      // Call the backend auth endpoint
      const response = await fetch('http://localhost:5000/auth/login', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          username: email.split('@')[0], // Extract username from email (e.g., admin@example.com -> admin)
          password: password,
        }),
      });

      if (!response.ok) {
        return false;
      }

      const data = await response.json();
      
      // Find the matching mock user to get additional info
      const mockUser = MOCK_USERS[email.toLowerCase()];
      if (mockUser) {
        const userWithToken = {
          ...mockUser.user,
          token: data.token, // Store the real JWT token
        };
        setUser(userWithToken);
        
        // Store both user info and token
        localStorage.setItem('user', JSON.stringify(userWithToken));
        localStorage.setItem('jwt_token', data.token);
        localStorage.setItem('accountTier', mockUser.user.accountTier);
        
        return true;
      }
      
      return false;
    } catch (error) {
      console.error('Login error:', error);
      return false;
    }
  };

  const logout = () => {
    setUser(null);
    localStorage.removeItem('user');
    localStorage.removeItem('jwt_token');
    localStorage.removeItem('accountTier');
  };

  // Check for stored user on mount
  useState(() => {
    const storedUser = localStorage.getItem('user');
    if (storedUser) {
      try {
        setUser(JSON.parse(storedUser));
      } catch (e) {
        localStorage.removeItem('user');
      }
    }
  });

  return (
    <AuthContext.Provider
      value={{
        user,
        login,
        logout,
        isAuthenticated: !!user,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
