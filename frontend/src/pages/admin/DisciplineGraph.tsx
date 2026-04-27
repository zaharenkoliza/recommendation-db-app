import { useState, useEffect, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { api } from '../../api/client';
import { ArrowLeft, Loader2, AlertCircle, Info } from 'lucide-react';

/**
 * Lightweight discipline dependency graph.
 * Uses plain HTML + inline SVG arrows instead of ReactFlow.
 * Renders instantly on any browser without heavy canvas/WebGL.
 */

interface GraphNode {
  id: string;
  label: string;
  type: 'target' | 'pre' | 'post';
}

interface GraphEdge {
  id: string;
  source: string;
  target: string;
  label?: string;
}


/* ─── Arrow connector drawn as SVG ─── */
const Arrow = ({ x1, y1, x2, y2, label }: { x1: number; y1: number; x2: number; y2: number; label?: string }) => {
  const midY = (y1 + y2) / 2;
  const d = `M ${x1} ${y1} C ${x1} ${midY}, ${x2} ${midY}, ${x2} ${y2}`;
  
  const midX = (x1 + x2) / 2;
  const midYLabel = (y1 + y2) / 2;

  return (
    <g>
      <path d={d} fill="none" stroke={label === 'Вручную' ? '#10B981' : '#1846C7'} strokeWidth="2" opacity="0.35" />
      <polygon
        points={`${x2},${y2} ${x2 - 5},${y2 - 8} ${x2 + 5},${y2 - 8}`}
        fill={label === 'Вручную' ? '#10B981' : '#1846C7'}
        opacity="0.5"
      />
      {label && (
        <g transform={`translate(${midX}, ${midYLabel})`}>
          <rect x="-25" y="-8" width="50" height="16" rx="4" fill="white" stroke="#eee" strokeWidth="1" />
          <text textAnchor="middle" dy="3" fontSize="8" fontWeight="bold" fill="#666">{label}</text>
        </g>
      )}
    </g>
  );
};

export const DisciplineGraph = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [disciplineName, setDisciplineName] = useState('');
  const [preNodes, setPreNodes] = useState<GraphNode[]>([]);
  const [postNodes, setPostNodes] = useState<GraphNode[]>([]);
  const [edges, setEdges] = useState<GraphEdge[]>([]);
  const [arrows, setArrows] = useState<{ x1: number; y1: number; x2: number; y2: number; label?: string }[]>([]);
  
  const [allDisciplines, setAllDisciplines] = useState<any[]>([]);
  const [selectedPrereq, setSelectedPrereq] = useState<string>('');
  const [submitting, setSubmitting] = useState(false);

  const containerRef = useRef<HTMLDivElement>(null);
  const targetRef = useRef<HTMLDivElement>(null);
  const preRefs = useRef<(HTMLDivElement | null)[]>([]);
  const postRefs = useRef<(HTMLDivElement | null)[]>([]);

  const fetchGraph = () => {
    if (!id) return;
    setLoading(true);
    api.getDisciplineGraph(Number(id))
      .then(data => {
        const target = data.nodes.find((n: GraphNode) => n.type === 'target');
        if (target) setDisciplineName(target.label);
        setPreNodes(data.nodes.filter((n: GraphNode) => n.type === 'pre'));
        setPostNodes(data.nodes.filter((n: GraphNode) => n.type === 'post'));
        setEdges(data.edges);
      })
      .catch(err => {
        console.error(err);
        setError('Не удалось загрузить граф зависимостей');
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchGraph();
    api.getDisciplines().then(setAllDisciplines).catch(err => console.error('Get disciplines error:', err));
  }, [id]);

  // Compute arrow positions after DOM paint
  useEffect(() => {
    if (loading) return;
    const timer = setTimeout(() => {
      try {
        computeArrows();
      } catch (err) {
        console.error('computeArrows crash:', err);
      }
    }, 100);
    window.addEventListener('resize', computeArrows);
    return () => {
      clearTimeout(timer);
      window.removeEventListener('resize', computeArrows);
    };
  }, [preNodes, postNodes, loading, edges]);

  const computeArrows = () => {
    if (!containerRef.current || !targetRef.current) {
      console.log('Missing refs for computeArrows');
      return;
    }
    
    const containerRect = containerRef.current.getBoundingClientRect();
    const targetRect = targetRef.current.getBoundingClientRect();

    const newArrows: typeof arrows = [];

    // Arrows from each pre-node → target
    preNodes.forEach((node, i) => {
      const el = preRefs.current[i];
      if (!el) return;
      const edge = edges.find(e => String(e.source) === String(node.id) && String(e.target) === String(id));
      const r = el.getBoundingClientRect();
      
      newArrows.push({
        x1: r.left + r.width / 2 - containerRect.left,
        y1: r.top + r.height - containerRect.top,
        x2: targetRect.left + targetRect.width / 2 - containerRect.left,
        y2: targetRect.top - containerRect.top,
        label: edge?.label
      });
    });

    // Arrows from target → each post-node
    postNodes.forEach((node, i) => {
      const el = postRefs.current[i];
      if (!el) return;
      const edge = edges.find(e => String(e.source) === String(id) && String(e.target) === String(node.id));
      const r = el.getBoundingClientRect();
      
      newArrows.push({
        x1: targetRect.left + targetRect.width / 2 - containerRect.left,
        y1: targetRect.top + targetRect.height - containerRect.top,
        x2: r.left + r.width / 2 - containerRect.left,
        y2: r.top - containerRect.top,
        label: edge?.label
      });
    });

    setArrows(newArrows);
  };

  const handleAddPrereq = async () => {
    if (!selectedPrereq || !id) return;
    setSubmitting(true);
    try {
      await api.addPrerequisite(Number(id), Number(selectedPrereq));
      setSelectedPrereq('');
      fetchGraph();
    } catch (err) {
      alert('Ошибка при добавлении связи');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeletePrereq = async (prereqId: string) => {
    if (!id || !confirm('Удалить эту связь?')) return;
    try {
      await api.deletePrerequisite(Number(id), Number(prereqId));
      fetchGraph();
    } catch (err) {
      alert('Ошибка при удалении связи');
    }
  };

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-4 text-[#5C5C5C]">
        <Loader2 className="animate-spin text-[#1846C7]" size={40} />
        <p>Строим граф зависимостей...</p>
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-8">
        <div className="flex items-center gap-4">
          <button
            onClick={() => navigate(-1)}
            className="p-2 rounded-xl bg-white border border-gray-100 text-[#5C5C5C] hover:text-[#1846C7] transition-all"
          >
            <ArrowLeft size={20} />
          </button>
          <div>
            <div className="text-[10px] font-black uppercase tracking-[0.2em] text-[#1846C7] mb-1">Визуализатор связей</div>
            <h1 className="text-2xl font-black text-[#1F1F1F] tracking-tight">{disciplineName}</h1>
          </div>
        </div>
        {/* Legend */}
        <div className="hidden md:flex items-center gap-4 px-4 py-2 bg-white border border-gray-100 rounded-xl text-[11px] font-bold">
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-blue-300" />
            <span className="text-gray-400">Пререквизиты</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-[#1846C7]" />
            <span className="text-[#1F1F1F]">Текущая</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-emerald-400" />
            <span className="text-gray-400">Последствия</span>
          </div>
        </div>
      </div>

      {error ? (
        <div className="light-card border-red-500 bg-red-50 flex items-center gap-4 p-6">
          <AlertCircle className="text-red-500" size={32} />
          <div>
            <h4 className="font-bold text-red-700">Ошибка</h4>
            <p className="text-sm text-red-600">{error}</p>
          </div>
        </div>
      ) : (
        <div
          ref={containerRef}
          className="relative bg-gray-50/50 rounded-3xl border border-gray-100 p-8 md:p-12 overflow-hidden"
          style={{ minHeight: 400 }}
        >
          {/* SVG layer for arrows */}
          <svg
            className="absolute inset-0 w-full h-full pointer-events-none"
            style={{ zIndex: 0 }}
          >
            {arrows.map((a, i) => (
              <Arrow key={i} {...a} />
            ))}
          </svg>

          {/* Pre-requisites row */}
          {preNodes.length > 0 && (
            <div className="relative z-10 mb-16">
              <p className="text-[10px] font-black uppercase tracking-[0.15em] text-gray-300 text-center mb-4">Пререквизиты</p>
              <div className="flex flex-wrap justify-center gap-4">
                {preNodes.map((node, i) => (
                  <div
                    key={node.id}
                    ref={el => { preRefs.current[i] = el; }}
                    onClick={() => navigate(`/admin/disciplines/${node.id}/graph`)}
                    className="px-5 py-3 bg-white border-2 border-blue-200 rounded-xl shadow-sm hover:shadow-lg hover:border-blue-400 cursor-pointer transition-all max-w-[220px] group"
                  >
                    <span className="text-[9px] font-black uppercase tracking-wider text-blue-400 block mb-1">Пререквизит</span>
                    <span className="text-xs font-bold text-[#333] leading-tight block group-hover:text-[#1846C7] transition-colors">{node.label}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Target discipline — center */}
          <div className="relative z-10 flex justify-center mb-16">
            <div
              ref={targetRef}
              className="px-8 py-5 bg-white border-2 border-[#1846C7] rounded-2xl shadow-xl ring-4 ring-blue-50 max-w-xs text-center"
            >
              <span className="text-[9px] font-black uppercase tracking-wider text-[#1846C7] block mb-1">Целевая дисциплина</span>
              <span className="text-sm font-black text-[#1F1F1F] leading-tight block">{disciplineName}</span>
            </div>
          </div>

          {/* Post-requisites row */}
          {postNodes.length > 0 && (
            <div className="relative z-10">
              <p className="text-[10px] font-black uppercase tracking-[0.15em] text-gray-300 text-center mb-4">Последующие курсы</p>
              <div className="flex flex-wrap justify-center gap-4">
                {postNodes.map((node, i) => (
                  <div
                    key={node.id}
                    ref={el => { postRefs.current[i] = el; }}
                    onClick={() => navigate(`/admin/disciplines/${node.id}/graph`)}
                    className="px-5 py-3 bg-white border-2 border-emerald-200 rounded-xl shadow-sm hover:shadow-lg hover:border-emerald-400 cursor-pointer transition-all max-w-[220px] group"
                  >
                    <span className="text-[9px] font-black uppercase tracking-wider text-emerald-500 block mb-1">Последующий</span>
                    <span className="text-xs font-bold text-[#333] leading-tight block group-hover:text-emerald-600 transition-colors">{node.label}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Empty state */}
          {preNodes.length === 0 && postNodes.length === 0 && (
            <div className="text-center py-8 text-[#5C5C5C]">
              <p className="text-sm font-bold">У этой дисциплины нет зависимостей.</p>
              <p className="text-xs opacity-60 mt-1">Она не имеет ни пререквизитов, ни последующих курсов.</p>
            </div>
          )}

          {/* Info hint */}
          <div className="relative z-10 mt-10 p-4 bg-white/70 backdrop-blur border border-white rounded-2xl shadow-lg max-w-sm mx-auto">
            <div className="flex items-start gap-3">
              <Info className="text-[#1846C7] flex-shrink-0 mt-0.5" size={14} />
              <p className="text-[11px] text-[#5C5C5C] leading-relaxed">
                Нажмите на любую дисциплину, чтобы перейти к её графу зависимостей. Зеленые стрелки — связи, заданные вручную.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Admin Management Panel */}
      {!loading && !error && (
        <div className="mt-8 light-card p-6">
          <h3 className="text-lg font-black text-[#1F1F1F] mb-4 flex items-center gap-2">
            <div className="w-1.5 h-6 bg-[#1846C7] rounded-full" />
            Управление связями
          </h3>
          
          <div className="grid md:grid-cols-2 gap-8">
            {/* List of current prerequisites */}
            <div>
              <p className="text-[10px] font-black uppercase tracking-wider text-gray-400 mb-3">Текущие пререквизиты</p>
              <div className="space-y-2">
                {preNodes.length === 0 ? (
                  <p className="text-xs text-gray-400 italic">Нет пререквизитов</p>
                ) : (
                  preNodes.map(node => (
                    <div key={node.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-xl border border-gray-100 group">
                      <span className="text-sm font-bold text-[#333]">{node.label}</span>
                      <button 
                        onClick={(e) => { e.stopPropagation(); handleDeletePrereq(node.id); }}
                        className="p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors"
                        title="Удалить связь"
                      >
                        <AlertCircle size={16} />
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>

            {/* Add new prerequisite */}
            <div>
              <p className="text-[10px] font-black uppercase tracking-wider text-gray-400 mb-3">Добавить новый пререквизит</p>
              <div className="flex gap-2">
                <select 
                  value={selectedPrereq}
                  onChange={(e) => setSelectedPrereq(e.target.value)}
                  className="flex-1 bg-gray-50 border border-gray-200 rounded-xl px-4 py-2.5 text-sm font-bold focus:ring-2 focus:ring-blue-100 outline-none transition-all"
                >
                  <option value="">Выберите дисциплину...</option>
                  {allDisciplines
                    .filter(d => d.id !== Number(id) && !preNodes.find(pn => pn.id === String(d.id)))
                    .map(d => (
                      <option key={d.id} value={d.id}>{d.name}</option>
                    ))
                  }
                </select>
                <button 
                  disabled={!selectedPrereq || submitting}
                  onClick={handleAddPrereq}
                  className="px-6 py-2.5 bg-[#1846C7] text-white rounded-xl text-sm font-black hover:bg-[#153eb1] disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg shadow-blue-100 flex items-center gap-2"
                >
                  {submitting ? <Loader2 size={16} className="animate-spin" /> : 'Добавить'}
                </button>
              </div>
              <p className="mt-3 text-[10px] text-gray-400 leading-relaxed italic">
                Внимание: ручные пререквизиты имеют приоритет и не удаляются при автоматическом перестроении графа.
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
