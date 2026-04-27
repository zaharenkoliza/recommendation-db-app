import { useState } from 'react';
import { X, Save, Loader2 } from 'lucide-react';
import { api } from '../../api/client';

interface Props {
  discipline: any;
  onClose: () => void;
  onSaved: () => void;
}

export const DisciplineForm = ({ discipline, onClose, onSaved }: Props) => {
  const [form, setForm] = useState({
    name: discipline.name || '',
    comment: discipline.comment || '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);

    try {
      await api.updateDiscipline(discipline.id, form);
      onSaved();
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Произошла ошибка при сохранении');
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
            <h2 className="text-xl font-black text-[#1F1F1F]">Редактировать дисциплину</h2>
            <p className="text-xs text-[#5C5C5C] mt-0.5">ID: {discipline.id}</p>
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
              Название дисциплины *
            </label>
            <input
              type="text"
              required
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="w-full px-4 py-3 border border-gray-200 rounded-xl outline-none focus:border-[#1846C7] focus:ring-2 focus:ring-blue-50 transition-all text-[#1F1F1F] font-medium"
            />
          </div>

          <div>
            <label className="block text-xs font-bold text-[#5C5C5C] uppercase tracking-wider mb-2">
              Описание / Комментарий
            </label>
            <textarea
              rows={4}
              value={form.comment}
              onChange={(e) => setForm({ ...form, comment: e.target.value })}
              className="w-full px-4 py-3 border border-gray-200 rounded-xl outline-none focus:border-[#1846C7] focus:ring-2 focus:ring-blue-50 transition-all text-[#1F1F1F] font-medium resize-none"
              placeholder="Краткое описание дисциплины..."
            />
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
              Сохранить
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
