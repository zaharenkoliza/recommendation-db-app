import { useState, useEffect } from 'react';
import { api } from '../../api/client';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Loader2, AlertCircle, Layers, ChevronRight, TrendingUp, Plus, Pencil, Trash2 } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { TrackForm } from './TrackForm';

export const TracksList = () => {
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [editingItem, setEditingItem] = useState<any>(null);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const navigate = useNavigate();

  const loadData = () => {
    if (!id) return;
    setLoading(true);
    api.getTracks(Number(id))
      .then(setData)
      .catch(err => {
        setError('Не удалось загрузить треки');
        console.error(err);
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => { loadData(); }, [id]);

  const handleDelete = async (trackId: number) => {
    if (!confirm('Удалить этот трек?')) return;
    setDeletingId(trackId);
    try {
      await api.deleteTrack(trackId);
      setData((prev: any) => ({
        ...prev,
        tracks: prev.tracks.filter((t: any) => t.id !== trackId)
      }));
    } catch (err: any) {
      alert(err.response?.data?.detail || 'Ошибка удаления');
    } finally {
      setDeletingId(null);
    }
  };

  if (loading && !data) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
        <Loader2 className="animate-spin text-[#1846C7]" size={40} />
        <p>Загрузка треков...</p>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div>
        <button onClick={() => navigate(`/admin/curricula/${id}`)} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors">
          <ArrowLeft size={18} /> Назад к плану
        </button>
        <div className="light-card border-red-500 bg-red-50 flex items-center gap-4 p-6">
          <AlertCircle className="text-red-500" size={32} />
          <div>
            <h4 className="font-bold text-red-700">Ошибка</h4>
            <p className="text-sm text-red-600">{error}</p>
          </div>
        </div>
      </div>
    );
  }

  const { info, tracks } = data;

  return (
    <div>
      <button onClick={() => navigate(`/admin/curricula/${id}`)} className="flex items-center gap-2 text-[#5C5C5C] hover:text-[#1846C7] mb-6 transition-colors">
        <ArrowLeft size={18} /> Назад к плану
      </button>

      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-3">
          <Layers className="text-[#1846C7]" size={28} />
          <h1>Треки обучения</h1>
        </div>
        <button
          onClick={() => { setEditingItem(null); setShowForm(true); }}
          className="flex items-center gap-2 px-5 py-2.5 bg-[#1846C7] text-white rounded-xl text-sm font-bold hover:bg-[#1338a0] transition-all shadow-lg shadow-blue-200 active:scale-95"
        >
          <Plus size={18} /> Добавить трек
        </button>
      </div>
      <p className="text-[#5C5C5C] mb-8">
        Выбор специализаций для учебного плана: <span className="text-[#333] font-semibold">{info?.name} ({info?.year})</span>
      </p>

      {tracks.length > 0 ? (
        <div className="grid gap-4">
          {tracks.map((t: any, i: number) => (
            <motion.div
              key={t.id}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.1 }}
              className="light-card flex items-center justify-between hover:border-[#1846C7] transition-colors group cursor-default"
            >
              <div className="flex items-center gap-4">
                <div className="w-10 h-10 rounded-full bg-blue-50 flex items-center justify-center text-[#1846C7] font-bold">
                  {t.number}
                </div>
                <div>
                  <h3 className="font-bold text-[#333] group-hover:text-[#1846C7] transition-colors">{t.name}</h3>
                  <p className="text-xs text-[#5C5C5C]">ID: {t.id} • Лимит выбора: {t.count_limit || 'Без ограничений'}</p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    onClick={() => { setEditingItem(t); setShowForm(true); }}
                    className="p-2 rounded-lg hover:bg-blue-100 text-[#1846C7] transition-colors"
                    title="Редактировать"
                  >
                    <Pencil size={16} />
                  </button>
                  <button
                    onClick={() => handleDelete(t.id)}
                    disabled={deletingId === t.id}
                    className="p-2 rounded-lg hover:bg-red-100 text-red-500 transition-colors disabled:opacity-50"
                    title="Удалить"
                  >
                    {deletingId === t.id ? <Loader2 size={16} className="animate-spin" /> : <Trash2 size={16} />}
                  </button>
                </div>
                <div className="h-8 w-px bg-gray-100 mx-2" />
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    navigate(`/admin/tracks/${t.id}/visualize`);
                  }}
                  className="flex items-center gap-2 px-3 py-1.5 bg-blue-50 text-[#1846C7] rounded-lg hover:bg-blue-100 transition-colors text-xs font-bold"
                >
                  <TrendingUp size={14} /> Визуализация
                </button>
                <ChevronRight size={20} className="text-gray-300 group-hover:text-[#1846C7] transition-colors" />
              </div>
            </motion.div>
          ))}
        </div>
      ) : (
        <div className="light-card border-dashed py-20 text-center text-[#5C5C5C]">
          <Layers size={48} className="mx-auto mb-4 opacity-30" />
          <h2 className="text-xl mb-2 text-[#333]">Треки не найдены</h2>
          <p>В данном учебном плане еще не создано ни одного трека специализации.</p>
        </div>
      )}

      {/* Modal */}
      <AnimatePresence>
        {showForm && (
          <TrackForm
            track={editingItem}
            curriculumId={Number(id)}
            sectionId={data.info?.id_section || 1} // Fallback to 1 or implement selection
            onClose={() => { setShowForm(false); setEditingItem(null); }}
            onSaved={() => { setShowForm(false); setEditingItem(null); loadData(); }}
          />
        )}
      </AnimatePresence>
    </div>
  );
};
