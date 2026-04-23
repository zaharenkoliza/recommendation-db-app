import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { useNavigate } from 'react-router-dom';
import { BookOpen, Loader2, AlertCircle, ChevronRight, GraduationCap } from 'lucide-react';
import { motion } from 'framer-motion';

export const CurriculaList = () => {
  const [curricula, setCurricula] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const navigate = useNavigate();

  useEffect(() => {
    api.getCurricula()
      .then(data => {
        setCurricula(data);
        setLoading(false);
      })
      .catch(err => {
        setError('Не удалось загрузить учебные планы');
        setLoading(false);
        console.error(err);
      });
  }, []);

  const filtered = curricula.filter(c =>
    c.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.year?.toString().includes(searchTerm)
  );

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
        <Loader2 className="animate-spin text-[#1846C7]" size={40} />
        <p>Загрузка учебных планов...</p>
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
      <h1>Учебные планы</h1>
      <p className="text-[#5C5C5C] mb-6">Управление образовательными программами</p>

      {/* Search */}
      <div className="mb-8 max-w-md">
        <input
          type="text"
          placeholder="Поиск по названию или году..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:border-[#1846C7] transition-colors"
        />
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <div className="light-card flex flex-col">
          <p className="text-sm text-[#5C5C5C] mb-1">Всего планов</p>
          <p className="text-3xl font-bold text-[#1846C7]">{curricula.length}</p>
        </div>
        <div className="light-card flex flex-col">
          <p className="text-sm text-[#5C5C5C] mb-1">Бакалавриат</p>
          <p className="text-3xl font-bold">{curricula.filter(c => c.degree === 'bachelor').length}</p>
        </div>
        <div className="light-card flex flex-col">
          <p className="text-sm text-[#5C5C5C] mb-1">Магистратура</p>
          <p className="text-3xl font-bold">{curricula.filter(c => c.degree === 'master').length}</p>
        </div>
      </div>

      {/* Table */}
      <div className="light-card overflow-hidden" style={{ padding: 0 }}>
        <table className="w-full">
          <thead>
            <tr className="border-b border-gray-100 bg-gray-50">
              <th className="text-left px-6 py-3 text-xs font-semibold text-[#5C5C5C] uppercase tracking-wider">ID ИСУ</th>
              <th className="text-left px-6 py-3 text-xs font-semibold text-[#5C5C5C] uppercase tracking-wider">Название</th>
              <th className="text-left px-6 py-3 text-xs font-semibold text-[#5C5C5C] uppercase tracking-wider">Год</th>
              <th className="text-left px-6 py-3 text-xs font-semibold text-[#5C5C5C] uppercase tracking-wider">Степень</th>
              <th className="text-left px-6 py-3 text-xs font-semibold text-[#5C5C5C] uppercase tracking-wider">Руководитель</th>
              <th className="px-6 py-3"></th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((c, i) => (
              <motion.tr
                key={c.id_isu}
                initial={{ opacity: 0, y: 5 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.03 }}
                onClick={() => navigate(`/admin/curricula/${c.id_isu}`)}
                className="border-b border-gray-50 hover:bg-blue-50 cursor-pointer transition-colors"
              >
                <td className="px-6 py-4 text-sm font-mono text-[#5C5C5C]">{c.id_isu}</td>
                <td className="px-6 py-4">
                  <div className="flex items-center gap-2">
                    <BookOpen size={16} className="text-[#1846C7]" />
                    <span className="font-medium text-[#333]">{c.name}</span>
                  </div>
                </td>
                <td className="px-6 py-4 text-sm">{c.year}</td>
                <td className="px-6 py-4">
                  <span className={`text-xs px-2 py-1 rounded font-semibold ${
                    c.degree === 'bachelor'
                      ? 'bg-blue-100 text-blue-700'
                      : 'bg-purple-100 text-purple-700'
                  }`}>
                    {c.degree === 'bachelor' ? 'Бакалавриат' : 'Магистратура'}
                  </span>
                </td>
                <td className="px-6 py-4 text-sm text-[#5C5C5C]">{c.head}</td>
                <td className="px-6 py-4">
                  <ChevronRight size={16} className="text-[#5C5C5C]" />
                </td>
              </motion.tr>
            ))}
          </tbody>
        </table>
        {filtered.length === 0 && (
          <div className="py-12 text-center text-[#5C5C5C]">
            <GraduationCap size={36} className="mx-auto mb-3 opacity-40" />
            <p>Ничего не найдено</p>
          </div>
        )}
      </div>
    </div>
  );
};
