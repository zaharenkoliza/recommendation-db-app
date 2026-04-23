import { useState, useEffect } from 'react';
import { Routes, Route, Navigate, useNavigate, useLocation } from 'react-router-dom';
import { api } from './api/client';
import type { Student, RecommendedDiscipline } from './api/types';
import { useAuth } from './context/AuthContext';
import { Login } from './pages/Login';
import { StudentSelector } from './components/StudentSelector';
import { RecommendationCard } from './components/RecommendationCard';
import { ProgressPage } from './components/ProgressPage';
import { LayoutDashboard, TrendingUp, AlertCircle, Loader2, LogOut, Settings, BookOpen, Library } from 'lucide-react';
import { AnimatePresence, motion } from 'framer-motion';
import { CurriculaList } from './pages/admin/CurriculaList';
import { CurriculumDetail } from './pages/admin/CurriculumDetail';
import { DisciplinesList } from './pages/admin/DisciplinesList';
import { TracksList } from './pages/admin/TracksList';
import { TrackVisualization } from './pages/admin/TrackVisualization';

/* ─── Dashboard (Student/Admin main view) ──────────────── */
function Dashboard() {
  const { user, isAdmin } = useAuth();
  const [selectedStudent, setSelectedStudent] = useState<Student | null>(null);
  const [recommendations, setRecommendations] = useState<RecommendedDiscipline[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activePage, setActivePage] = useState<'recommendations' | 'progress'>('recommendations');

  // For students, auto-load their own data
  useEffect(() => {
    if (!isAdmin && user?.student_id) {
      api.getStudentDetails(user.student_id)
        .then(setSelectedStudent)
        .catch(console.error);
    }
  }, [user, isAdmin]);

  useEffect(() => {
    if (selectedStudent) {
      setLoading(true);
      setError(null);
      api.getRecommendations(selectedStudent.id)
        .then(res => {
          setRecommendations(res.recommended_disciplines);
          setLoading(false);
        })
        .catch(err => {
          console.error(err);
          setError('Не удалось загрузить рекомендации. Сервер доступен?');
          setLoading(false);
        });
    }
  }, [selectedStudent]);

  const navItems: { id: 'recommendations' | 'progress'; label: string; icon: React.ReactNode }[] = [
    { id: 'recommendations', label: 'Рекомендации', icon: <LayoutDashboard size={20} /> },
    { id: 'progress', label: 'Прогресс', icon: <TrendingUp size={20} /> },
  ];

  return (
    <>
      <h1>Умные Рекомендации</h1>

      {/* Admin can pick any student, student auto-loads their own */}
      {isAdmin && (
        <div className="mb-10 max-w-md">
          <StudentSelector onSelect={setSelectedStudent} />
        </div>
      )}

      <AnimatePresence mode="wait">
        {!selectedStudent ? (
          <motion.div
            key="empty"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="py-20 text-center text-[#5C5C5C]"
          >
            <LayoutDashboard size={48} className="mx-auto mb-4 opacity-50" />
            <h2 className="text-xl mb-2 text-[#333]">
              {isAdmin ? 'Выберите студента' : 'Загрузка данных...'}
            </h2>
            <p>{isAdmin ? 'Для отображения персональных рекомендаций необходимо выбрать студента из списка.' : 'Пожалуйста, подождите.'}</p>
          </motion.div>
        ) : activePage === 'progress' ? (
          <motion.div key="progress" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
            <ProgressPage student={selectedStudent} />
          </motion.div>
        ) : (
          <motion.div
            key="content"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="space-y-8"
          >
            {/* Stats */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
              <div className="light-card flex flex-col">
                <p className="text-sm text-[#5C5C5C] mb-1">Доступно курсов</p>
                <p className="text-3xl font-bold text-[#1846C7]">{recommendations.length}</p>
              </div>
              <div className="light-card flex flex-col">
                <p className="text-sm text-[#5C5C5C] mb-1">Группа</p>
                <p className="text-3xl font-bold">{selectedStudent.group_id || 'Нет данных'}</p>
              </div>
              <div className="light-card flex flex-col">
                <p className="text-sm text-[#5C5C5C] mb-1">Статус</p>
                <p className={`text-xl font-bold ${selectedStudent.status === 'Кандидат на отчисление' ? 'text-red-500' : 'text-green-600'}`}>
                  {selectedStudent.status || 'Активен'}
                </p>
              </div>
              <div className="light-card flex flex-col border-l-4 border-l-[#1846C7]">
                <p className="text-sm text-[#5C5C5C] mb-1">Трек обучения</p>
                <p className="text-xl font-bold mt-auto">{selectedStudent.track || 'Общий профиль'}</p>
              </div>
            </div>

            {/* Recommendations */}
            <div>
              <h2 className="text-2xl mb-6">Рекомендуемые дисциплины</h2>

              {loading ? (
                <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
                  <Loader2 className="animate-spin text-[#1846C7]" size={40} />
                  <p>Анализ графа...</p>
                </div>
              ) : error ? (
                <div className="light-card border-red-500 bg-red-50 flex items-center gap-4 p-6">
                  <AlertCircle className="text-red-500" size={32} />
                  <div>
                    <h4 className="font-bold text-red-700">Ошибка сервера</h4>
                    <p className="text-sm text-red-600">{error}</p>
                  </div>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                  {recommendations.length > 0 ? (
                    recommendations.map((rec, index) => (
                      <RecommendationCard key={rec.id} discipline={rec} index={index} />
                    ))
                  ) : (
                    <div className="col-span-full py-16 text-center light-card border-dashed">
                      <p className="text-[#5C5C5C]">Нет доступных рекомендаций для данного студента.</p>
                    </div>
                  )}
                </div>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Page switcher (bottom nav for sub-pages) */}
      {selectedStudent && (
        <div className="fixed bottom-0 left-[250px] right-0 bg-white border-t border-[#E7E7E7] flex justify-center gap-4 py-2 z-10">
          {navItems.map(item => (
            <button
              key={item.id}
              onClick={() => setActivePage(item.id)}
              className={`flex gap-2 items-center px-4 py-2 rounded-lg text-sm transition-colors ${
                activePage === item.id
                  ? 'text-[#1846C7] font-semibold bg-blue-50'
                  : 'text-[#5C5C5C] font-normal hover:bg-gray-50'
              }`}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
        </div>
      )}
    </>
  );
}

/* ─── Main App Shell ───────────────────────────────────── */
function App() {
  const { isAuthenticated, isAdmin, user, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  if (!isAuthenticated) {
    return (
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    );
  }

  const sidebarItems: { path: string; label: string; icon: React.ReactNode; adminOnly?: boolean }[] = [
    { path: '/', label: 'Рекомендации', icon: <LayoutDashboard size={20} /> },
    ...(isAdmin ? [
      { path: '/admin/curricula', label: 'Учебные планы', icon: <BookOpen size={20} />, adminOnly: true },
      { path: '/admin/disciplines', label: 'Дисциплины', icon: <Library size={20} />, adminOnly: true },
    ] : []),
  ];

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  return (
    <div className="flex min-h-screen">
      {/* Sidebar */}
      <aside className="fixed w-[250px] h-full p-4 border-r border-[#E7E7E7] bg-white z-20 flex flex-col">
        <div className="mb-8 font-bold text-2xl text-[#333] px-2 mt-4">
          ITMO Portal
        </div>

        {/* Role badge */}
        <div className="mb-4 px-2">
          <span className={`text-[10px] uppercase tracking-wider font-bold px-2 py-1 rounded ${
            isAdmin ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
          }`}>
            {isAdmin ? 'Администратор' : 'Студент'}
          </span>
        </div>

        <nav className="flex-1">
          <ul className="grid gap-1">
            {sidebarItems.map(item => (
              <li key={item.path}>
                <button
                  onClick={() => navigate(item.path)}
                  className={`w-full flex gap-2 items-center px-3 py-2 rounded-lg text-[16px] leading-[24px] transition-colors ${
                    location.pathname.startsWith(item.path) && (item.path !== '/' || location.pathname === '/')
                      ? 'text-[#1846C7] font-semibold bg-blue-50'
                      : 'text-[#5C5C5C] font-normal hover:bg-gray-50'
                  }`}
                >
                  {item.icon}
                  {item.label}
                </button>
              </li>
            ))}
          </ul>
        </nav>

        {/* User info & logout */}
        <div className="mt-4 pt-4 border-t border-[#E7E7E7]">
          <div className="px-2 py-2 rounded-lg bg-gray-50 border border-gray-100 mb-2">
            <p className="text-sm font-semibold text-[#1F1F1F] leading-tight">{user?.login}</p>
            <p className="text-xs text-[#5C5C5C]">{user?.role}</p>
          </div>
          <button
            onClick={handleLogout}
            className="w-full flex gap-2 items-center px-3 py-2 rounded-lg text-[14px] text-red-500 hover:bg-red-50 transition-colors"
          >
            <LogOut size={18} />
            Выйти
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 ml-[280px] mt-[40px] mr-[40px] mb-[40px]">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          {isAdmin && (
            <>
              <Route path="/admin/curricula" element={<CurriculaList />} />
              <Route path="/admin/curricula/:id" element={<CurriculumDetail />} />
              <Route path="/admin/tracks/:id" element={<TracksList />} />
              <Route path="/admin/tracks/:trackId/visualize" element={<TrackVisualization />} />
              <Route path="/admin/disciplines" element={<DisciplinesList />} />
            </>
          )}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}

export default App;
