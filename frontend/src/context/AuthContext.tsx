import { createContext, useContext, useState, useEffect, type ReactNode } from 'react';
import type { User } from '../api/types';

interface AuthContextType {
  user: User | null;
  token: string | null;
  login: (user: User, token: string) => void;
  logout: () => void;
  isAuthenticated: boolean;
  isAdmin: boolean;
  isInitializing: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(() => {
    const saved = localStorage.getItem('user');
    if (saved) {
      try { return JSON.parse(saved); } catch { return null; }
    }
    return null;
  });
  const [token, setToken] = useState<string | null>(() => localStorage.getItem('token'));
  const [isInitializing, setIsInitializing] = useState(true);

  useEffect(() => {
    // Initial check is now done in useState, but we still need to listen for events
    const syncAuth = () => {
      const savedToken = localStorage.getItem('token');
      const savedUser = localStorage.getItem('user');
      setToken(savedToken);
      if (savedUser) {
        try { setUser(JSON.parse(savedUser)); } catch { setUser(null); }
      } else {
        setUser(null);
      }
      setIsInitializing(false);
    };

    syncAuth();

    // Listen for storage changes (e.g. from interceptor or other tabs)

    // Listen for storage changes (e.g. from interceptor or other tabs)
    window.addEventListener('storage', () => {
      console.log('[AuthContext] Storage event detected');
      syncAuth();
    });
    // Custom event for same-tab changes
    window.addEventListener('auth-change', () => {
      console.log('[AuthContext] auth-change event detected');
      syncAuth();
    });


    return () => {
      window.removeEventListener('storage', syncAuth);
      window.removeEventListener('auth-change', syncAuth);
    };
  }, []);

  const login = (newUser: User, newToken: string) => {
    setUser(newUser);
    setToken(newToken);
    localStorage.setItem('token', newToken);
    localStorage.setItem('user', JSON.stringify(newUser));
    window.dispatchEvent(new Event('auth-change'));
  };

  const logout = () => {
    setUser(null);
    setToken(null);
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    window.dispatchEvent(new Event('auth-change'));
  };


  return (
    <AuthContext.Provider value={{
      user,
      token,
      login,
      logout,
      isAuthenticated: !!token,
      isAdmin: user?.role?.toUpperCase() === 'ADMIN',
      isInitializing
    }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
