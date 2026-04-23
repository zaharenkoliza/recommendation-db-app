import React, { useState, useEffect } from 'react';
import { api } from '../api/client';
import type { Student } from '../api/types';
import { Users, ChevronDown, Search } from 'lucide-react';

interface Props {
  onSelect: (student: Student) => void;
}

export const StudentSelector: React.FC<Props> = ({ onSelect }) => {
  const [students, setStudents] = useState<Student[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedStudent, setSelectedStudent] = useState<Student | null>(null);

  useEffect(() => {
    api.getStudents().then(setStudents).catch(console.error);
  }, []);

  const filteredStudents = students.filter(s => 
    s.name.toLowerCase().includes(searchTerm.toLowerCase()) || 
    s.id.toString().includes(searchTerm)
  );

  return (
    <div className="relative w-full max-w-md">
      <div 
        onClick={() => setIsOpen(!isOpen)}
        className="light-card flex items-center justify-between cursor-pointer py-3 px-4"
        style={{ padding: '12px 16px' }}
      >
        <div className="flex items-center gap-3">
          <div className="p-2 bg-[#f0f4ff] rounded text-[#1846C7]">
            <Users size={20} />
          </div>
          <div>
            <p className="text-[12px] text-[#5C5C5C] uppercase font-semibold mb-0.5">Выберите студента</p>
            <p className="font-semibold text-[#333] leading-none">{selectedStudent ? selectedStudent.name : 'Нажмите для выбора...'}</p>
          </div>
        </div>
        <ChevronDown className={`text-[#5C5C5C] transition-transform duration-300 ${isOpen ? 'rotate-180' : ''}`} size={20} strokeWidth={2} />
      </div>

      {isOpen && (
        <div className="absolute top-full left-0 right-0 mt-2 bg-white rounded-md z-50 shadow-[0_4px_20px_rgba(0,0,0,0.1)] max-h-[22rem] flex flex-col overflow-hidden border border-[#E7E7E7]">
          <div className="p-3 border-b border-[#E7E7E7] bg-[#f9f9f9]">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-[#5C5C5C]" size={16} />
              <input 
                type="text" 
                placeholder="Поиск по имени или ID..."
                className="w-full bg-white border border-[#ddd] rounded px-3 py-2 pl-9 text-[#333] outline-none focus:border-[#1846C7] transition-colors"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                autoFocus
              />
            </div>
          </div>
          <div className="overflow-y-auto flex-1 p-1">
            {filteredStudents.length > 0 ? (
              filteredStudents.map(student => (
                <div 
                  key={student.id}
                  onClick={() => {
                    setSelectedStudent(student);
                    onSelect(student);
                    setIsOpen(false);
                  }}
                  className="px-4 py-3 hover:bg-[#f0f4ff] rounded cursor-pointer transition-colors flex items-center justify-between group"
                >
                  <span className="font-medium text-[#333] group-hover:text-[#1846C7]">{student.name}</span>
                  <div className="flex flex-col items-end">
                    <span className="text-xs text-[#5C5C5C]">ИСУ: {student.id}</span>
                    {student.track && <span className="text-[10px] text-[#1846C7] opacity-70">{student.track}</span>}
                  </div>
                </div>
              ))
            ) : (
              <div className="py-6 px-4 text-center text-[#5C5C5C]">
                <p className="text-sm">Студенты не найдены.</p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
