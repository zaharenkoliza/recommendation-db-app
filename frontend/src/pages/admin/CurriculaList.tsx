import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { useNavigate } from 'react-router-dom';
import { BookOpen, Loader2, AlertCircle, ChevronRight, GraduationCap, Plus, Pencil, Trash2 } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { CurriculumForm } from './CurriculumForm';

export const CurriculaList = () => {
  const [curricula, setCurricula] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [editingItem, setEditingItem] = useState<any>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [showImport, setShowImport] = useState(false);
  const [importJson, setImportJson] = useState('');
  const [importing, setImporting] = useState(false);
  const navigate = useNavigate();

  const loadData = () => {
    setLoading(true);
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
  };

  useEffect(() => { loadData(); }, []);

  const handleDelete = async (idIsu: number, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!confirm('Удалить учебный план? Это также удалит все связанные секции.')) return;
    setDeletingId(idIsu);
    try {
      await api.deleteCurriculum(idIsu);
      setCurricula(prev => prev.filter(c => c.id_isu !== idIsu));
    } catch (err: any) {
      alert(err.response?.data?.detail || 'Ошибка удаления');
    } finally {
      setDeletingId(null);
    }
  };

  const handleEdit = (item: any, e: React.MouseEvent) => {
    e.stopPropagation();
    setEditingItem(item);
    setShowForm(true);
  };

  const handleImport = async () => {
    try {
      const data = JSON.parse(importJson);
      setImporting(true);
      await api.importCurriculum(data);
      setShowImport(false);
      setImportJson('');
      loadData();
      alert('Учебный план успешно импортирован!');
    } catch (err: any) {
      alert('Ошибка при импорте: ' + (err.response?.data?.detail || err.message));
    } finally {
      setImporting(false);
    }
  };

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
      <div className="flex items-center justify-between mb-2">
        <h1>Учебные планы</h1>
        <div className="flex gap-2">
          <button
            onClick={() => setShowImport(true)}
            className="flex items-center gap-2 px-5 py-2.5 bg-white border border-gray-200 text-[#5C5C5C] rounded-xl text-sm font-bold hover:bg-gray-50 transition-all active:scale-95"
          >
            <BookOpen size={18} /> Импорт JSON
          </button>
          <button
            onClick={() => { setEditingItem(null); setShowForm(true); }}
            className="flex items-center gap-2 px-5 py-2.5 bg-[#1846C7] text-white rounded-xl text-sm font-bold hover:bg-[#1338a0] transition-all shadow-lg shadow-blue-200 active:scale-95"
          >
            <Plus size={18} /> Создать план
          </button>
        </div>
      </div>
      <p className="text-[#5C5C5C] mb-6">Управление образовательными программами</p>

      {/* Search */}
      <div className="mb-8 max-w-md">
        <input
          type="text"
          placeholder="Поиск по названию или году..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full px-4 py-2.5 border border-gray-200 rounded-xl outline-none focus:border-[#1846C7] focus:ring-2 focus:ring-blue-50 transition-all"
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
              <th className="px-6 py-3 text-xs font-semibold text-[#5C5C5C] uppercase tracking-wider text-right">Действия</th>
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
                className="border-b border-gray-50 hover:bg-blue-50 cursor-pointer transition-colors group"
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
                  <div className="flex items-center justify-end gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={(e) => handleEdit(c, e)}
                      className="p-2 rounded-lg hover:bg-blue-100 text-[#1846C7] transition-colors"
                      title="Редактировать"
                    >
                      <Pencil size={15} />
                    </button>
                    <button
                      onClick={(e) => handleDelete(c.id_isu, e)}
                      disabled={deletingId === c.id_isu}
                      className="p-2 rounded-lg hover:bg-red-100 text-red-500 transition-colors disabled:opacity-50"
                      title="Удалить"
                    >
                      {deletingId === c.id_isu ? <Loader2 size={15} className="animate-spin" /> : <Trash2 size={15} />}
                    </button>
                    <ChevronRight size={16} className="text-gray-300 ml-1" />
                  </div>
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

      {/* Modal for manual creation/editing */}
      <AnimatePresence>
        {showForm && (
          <CurriculumForm
            curriculum={editingItem}
            onClose={() => { setShowForm(false); setEditingItem(null); }}
            onSaved={() => { setShowForm(false); setEditingItem(null); loadData(); }}
          />
        )}
      </AnimatePresence>

      {/* Import Modal */}
      <AnimatePresence>
        {showImport && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm">
            <motion.div 
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="bg-white rounded-3xl shadow-2xl w-full max-w-2xl overflow-hidden"
            >
              <div className="p-6 border-b border-gray-100 flex items-center justify-between">
                <h3 className="text-xl font-black text-[#1F1F1F]">Импорт учебного плана</h3>
                <button onClick={() => setShowImport(false)} className="text-gray-400 hover:text-gray-600">×</button>
              </div>
              <div className="p-6">
                <p className="text-sm text-[#5C5C5C] mb-4">
                  Вставьте JSON структуру учебного плана. Она должна включать секции, модули и дисциплины с указанием семестров.
                </p>
                <textarea
                  value={importJson}
                  onChange={(e) => setImportJson(e.target.value)}
                  className="w-full h-80 p-4 bg-gray-50 border border-gray-200 rounded-2xl font-mono text-xs outline-none focus:ring-2 focus:ring-blue-100 transition-all"
                  placeholder='{ "id_isu": 999, "name": "...", "sections": [...] }'
                />
              </div>
              <div className="p-6 bg-gray-50 flex justify-end gap-3">
                <button
                  onClick={() => setShowImport(false)}
                  className="px-6 py-2.5 text-sm font-bold text-[#5C5C5C] hover:bg-gray-100 rounded-xl transition-all"
                >
                  Отмена
                </button>
                <button
                  disabled={!importJson || importing}
                  onClick={handleImport}
                  className="px-8 py-2.5 bg-[#1846C7] text-white rounded-xl text-sm font-black hover:bg-[#1338a0] disabled:opacity-50 flex items-center gap-2 transition-all shadow-lg shadow-blue-100"
                >
                  {importing ? <Loader2 size={18} className="animate-spin" /> : 'Импортировать'}
                </button>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};
