import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { Loader2, AlertCircle, Search, BookOpen, Pencil, GitBranch } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { DisciplineForm } from './DisciplineForm';
import { useNavigate } from 'react-router-dom';

export const DisciplinesList = () => {
  const navigate = useNavigate();
  const [disciplines, setDisciplines] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [editingItem, setEditingItem] = useState<any>(null);

  const loadData = () => {
    api.getDisciplines()
      .then(data => {
        setDisciplines(data);
        setLoading(false);
      })
      .catch(err => {
        setError('Не удалось загрузить дисциплины');
        setLoading(false);
        console.error(err);
      });
  };

  useEffect(() => { loadData(); }, []);

  const filtered = disciplines.filter(d =>
    d.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
        <Loader2 className="animate-spin text-[#1846C7]" size={40} />
        <p>Загрузка дисциплин...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="light-card border-red-500 bg-red-50 flex items-center gap-4 p-6">
        <AlertCircle className="text-red-500" size={32} />
        <div>
          <h4 className="font-bold text-red-700">Ошибка</h4>
          <p className="text-sm text-red-600">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div>
      <h1>Справочник дисциплин</h1>
      <p className="text-[#5C5C5C] mb-6">Все дисциплины, зарегистрированные в системе</p>

      {/* Search and stats */}
      <div className="flex flex-col md:flex-row gap-6 mb-8">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-[#5C5C5C]" size={16} />
          <input
            type="text"
            placeholder="Поиск дисциплины..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-gray-200 rounded-lg outline-none focus:border-[#1846C7] transition-colors"
          />
        </div>
        <div className="light-card flex items-center gap-3 px-4 py-2" style={{ padding: '8px 16px' }}>
          <BookOpen size={18} className="text-[#1846C7]" />
          <span className="text-sm text-[#5C5C5C]">Всего: <b className="text-[#333]">{disciplines.length}</b></span>
          <span className="text-sm text-[#5C5C5C] ml-2">Найдено: <b className="text-[#333]">{filtered.length}</b></span>
        </div>
      </div>

      {/* Disciplines grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filtered.map((d, i) => (
          <motion.div
            key={d.id}
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: Math.min(i * 0.01, 0.3) }}
            className="light-card hover:border-[#1846C7] transition-colors cursor-default group relative"
          >
            <div className="absolute top-3 right-3 flex items-center gap-1 opacity-40 group-hover:opacity-100 transition-all">
              <button
                onClick={() => navigate(`/admin/disciplines/${d.id}/graph`)}
                className="p-1.5 rounded-lg bg-gray-50 text-gray-400 hover:text-[#1846C7] hover:bg-blue-50 transition-all"
                title="Посмотреть связи (пререквизиты)"
              >
                <GitBranch size={14} />
              </button>
              <button
                onClick={() => setEditingItem(d)}
                className="p-1.5 rounded-lg bg-gray-50 text-gray-400 hover:text-[#1846C7] hover:bg-blue-50 transition-all"
                title="Редактировать"
              >
                <Pencil size={14} />
              </button>
            </div>

            <div className="flex items-start gap-3">
              <div className="w-8 h-8 rounded bg-blue-50 flex-shrink-0 flex items-center justify-center text-[#1846C7] font-mono text-xs font-bold mt-0.5">
                {d.id}
              </div>
              <div className="flex-1 min-w-0 pr-6">
                <p className="font-medium text-[#333] leading-snug">{d.name}</p>
                {d.comment && (
                  <p className="text-xs text-[#5C5C5C] mt-1 line-clamp-2">{d.comment}</p>
                )}
              </div>
            </div>
          </motion.div>
        ))}
      </div>

      {filtered.length === 0 && (
        <div className="py-16 text-center text-[#5C5C5C]">
          <Search size={36} className="mx-auto mb-3 opacity-40" />
          <p>Дисциплины не найдены</p>
        </div>
      )}

      {/* Modal */}
      <AnimatePresence>
        {editingItem && (
          <DisciplineForm
            discipline={editingItem}
            onClose={() => setEditingItem(null)}
            onSaved={() => { setEditingItem(null); loadData(); }}
          />
        )}
      </AnimatePresence>
    </div>
  );
};
