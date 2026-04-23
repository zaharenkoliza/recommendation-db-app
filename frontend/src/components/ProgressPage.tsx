import React, { useEffect, useState } from 'react';
import { api } from '../api/client';
import type { Student, ProgressResponse, ProgressEntry } from '../api/types';
import { CheckCircle2, XCircle, Clock, BookOpen, Loader2, ChevronDown, ChevronUp } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

interface Props {
  student: Student;
}

const gradeColor = (grade: number | null) => {
  if (!grade) return 'text-gray-400';
  if (grade >= 4) return 'text-green-600';
  if (grade === 3) return 'text-yellow-600';
  return 'text-red-600';
};

const gradeLabel = (grade: number | null) => {
  if (!grade) return '—';
  const labels: Record<number, string> = { 5: 'Отлично', 4: 'Хорошо', 3: 'Удовл.', 2: 'Неудовл.' };
  return labels[grade] ?? String(grade);
};

interface SectionProps {
  title: string;
  count: number;
  icon: React.ReactNode;
  color: string;
  bgColor: string;
  entries: ProgressEntry[];
  defaultOpen?: boolean;
}

const Section: React.FC<SectionProps> = ({ title, count, icon, color, bgColor, entries, defaultOpen = false }) => {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <div className={`rounded-xl border ${bgColor} overflow-hidden`}>
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-center justify-between px-6 py-4 hover:opacity-90 transition-opacity"
      >
        <div className="flex items-center gap-3">
          <span className={color}>{icon}</span>
          <span className="font-semibold text-[#1F1F1F]">{title}</span>
          <span className={`text-sm font-bold px-2 py-0.5 rounded-full ${color} bg-white/60`}>
            {count}
          </span>
        </div>
        {open ? <ChevronUp size={18} className="text-gray-500" /> : <ChevronDown size={18} className="text-gray-500" />}
      </button>

      <AnimatePresence initial={false}>
        {open && entries.length > 0 && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.25 }}
            className="overflow-hidden"
          >
            <div className="px-6 pb-4 grid grid-cols-1 md:grid-cols-2 gap-3">
              {entries.map(entry => (
                <div key={entry.id} className="bg-white rounded-lg p-4 border border-[#E7E7E7] flex items-start justify-between gap-4">
                  <div className="flex items-start gap-3 min-w-0">
                    <BookOpen size={16} className="text-[#1846C7] mt-0.5 shrink-0" />
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-[#1F1F1F] leading-snug line-clamp-2">
                        {entry.discipline_name}
                      </p>
                      {entry.attempt_number > 1 && (
                        <p className="text-xs text-gray-400 mt-0.5">Попытка №{entry.attempt_number}</p>
                      )}
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    <p className={`text-lg font-bold ${gradeColor(entry.grade)}`}>
                      {entry.grade ?? '—'}
                    </p>
                    <p className={`text-[10px] font-semibold uppercase tracking-wide ${gradeColor(entry.grade)}`}>
                      {gradeLabel(entry.grade)}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </motion.div>
        )}
        {open && entries.length === 0 && (
          <div className="px-6 pb-4 text-sm text-gray-400 italic">Нет записей</div>
        )}
      </AnimatePresence>
    </div>
  );
};

export const ProgressPage: React.FC<Props> = ({ student }) => {
  const [progress, setProgress] = useState<ProgressResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    setError(null);
    api.getStudentProgress(student.id)
      .then(data => {
        setProgress(data);
        setLoading(false);
      })
      .catch(() => {
        setError('Не удалось загрузить данные прогресса.');
        setLoading(false);
      });
  }, [student.id]);

  const passRate = progress
    ? progress.summary.total > 0
      ? Math.round((progress.summary.passed / progress.summary.total) * 100)
      : 0
    : 0;

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="space-y-8"
    >
      {/* Header */}
      <div>
        <h2 className="text-2xl font-bold text-[#1F1F1F]">Прогресс студента</h2>
        <p className="text-[#5C5C5C] mt-1">
          {student.name} · ИСУ {student.id} · {student.group_id || 'Нет группы'}
        </p>
      </div>

      {loading ? (
        <div className="flex flex-col items-center justify-center py-24 gap-4 text-[#5C5C5C]">
          <Loader2 className="animate-spin text-[#1846C7]" size={40} />
          <p>Загрузка прогресса...</p>
        </div>
      ) : error ? (
        <div className="light-card border-red-300 bg-red-50 p-6 text-red-700">{error}</div>
      ) : progress ? (
        <>
          {/* Summary Cards */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="light-card flex flex-col items-center py-6">
              <p className="text-4xl font-bold text-[#1846C7]">{progress.summary.total}</p>
              <p className="text-xs text-[#5C5C5C] mt-1 uppercase tracking-wide font-medium">Всего предметов</p>
            </div>
            <div className="light-card flex flex-col items-center py-6">
              <p className="text-4xl font-bold text-green-600">{progress.summary.passed}</p>
              <p className="text-xs text-[#5C5C5C] mt-1 uppercase tracking-wide font-medium">Сдано</p>
            </div>
            <div className="light-card flex flex-col items-center py-6">
              <p className="text-4xl font-bold text-red-500">{progress.summary.failed}</p>
              <p className="text-xs text-[#5C5C5C] mt-1 uppercase tracking-wide font-medium">Задолженностей</p>
            </div>
            <div className="light-card flex flex-col items-center py-6">
              <p className="text-4xl font-bold text-[#1F1F1F]">{passRate}%</p>
              <p className="text-xs text-[#5C5C5C] mt-1 uppercase tracking-wide font-medium">Успеваемость</p>
            </div>
          </div>

          {/* Progress Bar */}
          <div className="light-card py-4 px-6">
            <div className="flex justify-between text-xs text-[#5C5C5C] mb-2">
              <span>Прогресс обучения</span>
              <span>{passRate}%</span>
            </div>
            <div className="h-3 bg-[#E7E7E7] rounded-full overflow-hidden">
              <motion.div
                className={`h-full rounded-full ${passRate >= 80 ? 'bg-green-500' : passRate >= 50 ? 'bg-[#1846C7]' : 'bg-red-400'}`}
                initial={{ width: 0 }}
                animate={{ width: `${passRate}%` }}
                transition={{ duration: 0.8, ease: 'easeOut' }}
              />
            </div>
          </div>

          {/* Sections */}
          <div className="space-y-4">
            {progress.summary.failed > 0 && (
              <Section
                title="Задолженности"
                count={progress.summary.failed}
                icon={<XCircle size={20} />}
                color="text-red-600"
                bgColor="border-red-200 bg-red-50/40"
                entries={progress.failed}
                defaultOpen={true}
              />
            )}
            <Section
              title="Сдано успешно"
              count={progress.summary.passed}
              icon={<CheckCircle2 size={20} />}
              color="text-green-600"
              bgColor="border-green-200 bg-green-50/30"
              entries={progress.passed}
              defaultOpen={progress.summary.failed === 0}
            />
            {progress.summary.enrolled > 0 && (
              <Section
                title="Записан на курс"
                count={progress.summary.enrolled}
                icon={<Clock size={20} />}
                color="text-blue-500"
                bgColor="border-blue-200 bg-blue-50/30"
                entries={progress.enrolled}
                defaultOpen={false}
              />
            )}
          </div>
        </>
      ) : null}
    </motion.div>
  );
};
