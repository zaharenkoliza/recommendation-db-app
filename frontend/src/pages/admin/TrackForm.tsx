import { useState } from 'react';
import { X, Save, Loader2 } from 'lucide-react';
import { api } from '../../api/client';

interface Props {
  track?: any;
  curriculumId: number;
  sectionId?: number; // root section for binding the track
  onClose: () => void;
  onSaved: () => void;
}

export const TrackForm = ({ track, curriculumId: _curriculumId, sectionId, onClose, onSaved }: Props) => {
  const isEdit = !!track;

  const [form, setForm] = useState({
    name: track?.name || '',
    number: track?.number || 1,
    count_limit: track?.count_limit || '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);

    try {
      if (isEdit) {
        await api.updateTrack(track.id, {
          name: form.name,
          number: Number(form.number),
          count_limit: form.count_limit ? Number(form.count_limit) : undefined,
        });
      } else {
        if (!sectionId) {
          setError('Не указана секция для привязки трека');
          setSaving(false);
          return;
        }
        await api.createTrack({
          name: form.name,
          number: Number(form.number),
          id_section: sectionId,
          count_limit: form.count_limit ? Number(form.count_limit) : undefined,
        });
      }
      onSaved();
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Произошла ошибка');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div
        className="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-8 py-5 border-b border-gray-100 bg-gray-50/50">
          <div>
            <h2 className="text-xl font-black text-[#1F1F1F]">
              {isEdit ? 'Редактировать трек' : 'Новый трек'}
            </h2>
            <p className="text-xs text-[#5C5C5C] mt-0.5">
              {isEdit ? `Изменение трека #${track.id}` : 'Создание нового трека специализации'}
            </p>
          </div>
          <button
            onClick={onClose}
            className="w-8 h-8 rounded-lg hover:bg-gray-200 flex items-center justify-center transition-colors text-gray-400 hover:text-gray-600"
          >
            <X size={18} />
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="px-8 py-6 space-y-5">
          {error && (
            <div className="p-3 rounded-xl bg-red-50 border border-red-100 text-sm text-red-700 font-medium">
              {error}
            </div>
          )}

          <div>
            <label className="block text-xs font-bold text-[#5C5C5C] uppercase tracking-wider mb-2">
              Название трека *
            </label>
            <input
              type="text"
              required
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="w-full px-4 py-3 border border-gray-200 rounded-xl outline-none focus:border-[#1846C7] focus:ring-2 focus:ring-blue-50 transition-all text-[#1F1F1F] font-medium"
              placeholder="Искусственный интеллект"
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-bold text-[#5C5C5C] uppercase tracking-wider mb-2">
                Номер *
              </label>
              <input
                type="number"
                required
                min={1}
                value={form.number}
                onChange={(e) => setForm({ ...form, number: Number(e.target.value) })}
                className="w-full px-4 py-3 border border-gray-200 rounded-xl outline-none focus:border-[#1846C7] focus:ring-2 focus:ring-blue-50 transition-all text-[#1F1F1F] font-medium"
              />
            </div>
            <div>
              <label className="block text-xs font-bold text-[#5C5C5C] uppercase tracking-wider mb-2">
                Лимит выбора
              </label>
              <input
                type="number"
                min={0}
                value={form.count_limit}
                onChange={(e) => setForm({ ...form, count_limit: e.target.value })}
                className="w-full px-4 py-3 border border-gray-200 rounded-xl outline-none focus:border-[#1846C7] focus:ring-2 focus:ring-blue-50 transition-all text-[#1F1F1F] font-medium"
                placeholder="Нет"
              />
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-3">
            <button
              type="button"
              onClick={onClose}
              className="px-5 py-2.5 rounded-xl text-sm font-bold text-[#5C5C5C] hover:bg-gray-100 transition-colors"
            >
              Отмена
            </button>
            <button
              type="submit"
              disabled={saving}
              className="px-6 py-2.5 rounded-xl text-sm font-bold text-white bg-[#1846C7] hover:bg-[#1338a0] transition-all flex items-center gap-2 disabled:opacity-50 shadow-lg shadow-blue-200"
            >
              {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
              {isEdit ? 'Сохранить' : 'Создать'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
