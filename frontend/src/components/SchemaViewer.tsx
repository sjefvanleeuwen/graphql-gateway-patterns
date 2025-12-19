import { useState, useEffect, useRef } from 'react';
import { Network, RefreshCw, Search, ChevronDown, ChevronRight, ZoomIn, ZoomOut, Move, DollarSign } from 'lucide-react';
import { getIntrospectionQuery, buildClientSchema, printSchema } from 'graphql';
import toast from 'react-hot-toast';

interface FieldInfo {
  name: string;
  type: string;
  typeName: string;
  description?: string;
  args?: Array<{ name: string; type: string }>;
  cost: number;
  isList: boolean;
}

interface SchemaType {
  name: string;
  kind: string;
  description?: string;
  fields?: FieldInfo[];
  totalCost?: number;
}

interface DiagramNode {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  type: SchemaType;
}

interface DiagramEdge {
  from: string;
  to: string;
  fieldName: string;
}

export default function SchemaViewer() {
  const [sdl, setSdl] = useState<string>('');
  const [types, setTypes] = useState<SchemaType[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [expandedTypes, setExpandedTypes] = useState<Set<string>>(new Set());
  const [viewMode, setViewMode] = useState<'diagram' | 'list' | 'sdl'>('diagram');
  
  // Diagram state
  const [nodes, setNodes] = useState<DiagramNode[]>([]);
  const [edges, setEdges] = useState<DiagramEdge[]>([]);
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [dragging, setDragging] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const [selectedNode, setSelectedNode] = useState<string | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);

  const fetchSchema = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const token = localStorage.getItem('jwt_token');
      const response = await fetch('http://localhost:5000/graphql', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token && { 'Authorization': `Bearer ${token}` }),
        },
        body: JSON.stringify({ 
          query: getIntrospectionQuery() 
        }),
      });

      const result = await response.json();
      
      if (result.errors) {
        throw new Error(result.errors[0].message);
      }

      // Build schema and get SDL
      const schema = buildClientSchema(result.data);
      const schemaSDL = printSchema(schema);
      setSdl(schemaSDL);

      // Extract types for visual view
      const allRawTypes = result.data.__schema.types;
      const introspectionTypes = allRawTypes
        .filter((t: any) => !t.name.startsWith('__'))
        .map((t: any) => {
          const fields = t.fields?.map((f: any) => ({
            name: f.name,
            type: formatType(f.type),
            typeName: getBaseTypeName(f.type),
            description: f.description,
            cost: calculateFieldCost(f.type, allRawTypes),
            isList: isListType(f.type),
            args: f.args?.map((a: any) => ({
              name: a.name,
              type: formatType(a.type)
            }))
          }));
          
          const totalCost = fields?.reduce((sum: number, f: FieldInfo) => sum + f.cost, 0) || 0;
          
          return {
            name: t.name,
            kind: t.kind,
            description: t.description,
            fields,
            totalCost
          };
        });
      
      setTypes(introspectionTypes);
      buildDiagram(introspectionTypes);
      toast.success('Schema loaded successfully!');
    } catch (err) {
      console.error('Error fetching schema:', err);
      const errorMsg = err instanceof Error ? err.message : 'Failed to load schema';
      setError(errorMsg);
      toast.error(errorMsg);
    } finally {
      setLoading(false);
    }
  };

  const formatType = (type: any): string => {
    if (type.kind === 'NON_NULL') {
      return `${formatType(type.ofType)}!`;
    }
    if (type.kind === 'LIST') {
      return `[${formatType(type.ofType)}]`;
    }
    return type.name || '';
  };

  const getBaseTypeName = (type: any): string => {
    if (type.ofType) {
      return getBaseTypeName(type.ofType);
    }
    return type.name || '';
  };

  const isListType = (type: any): boolean => {
    if (type.kind === 'LIST') return true;
    if (type.ofType) return isListType(type.ofType);
    return false;
  };

  // Calculate field complexity cost based on type
  const calculateFieldCost = (type: any, allTypes: any[]): number => {
    const baseTypeName = getBaseTypeName(type);
    const isList = isListType(type);
    
    // Scalar types have low cost
    const scalars = ['String', 'Int', 'Float', 'Boolean', 'ID', 'DateTime', 'UUID', 'Decimal'];
    if (scalars.includes(baseTypeName)) {
      return 1;
    }
    
    // Enum types have low cost
    const enumType = allTypes.find((t: any) => t.name === baseTypeName && t.kind === 'ENUM');
    if (enumType) {
      return 1;
    }
    
    // Object types have higher cost
    const objectType = allTypes.find((t: any) => t.name === baseTypeName && t.kind === 'OBJECT');
    if (objectType) {
      const fieldCount = objectType.fields?.length || 0;
      const baseCost = 5 + Math.min(fieldCount, 10); // Base cost for object + field overhead
      return isList ? baseCost * 10 : baseCost; // Lists multiply cost
    }
    
    // Default cost
    return isList ? 10 : 2;
  };

  const buildDiagram = (schemaTypes: SchemaType[]) => {
    // Filter to only OBJECT types for the diagram (excluding scalars, enums for cleaner view)
    const objectTypes = schemaTypes.filter(t => 
      t.kind === 'OBJECT' && 
      !['Query', 'Mutation', 'Subscription'].includes(t.name)
    );
    
    const rootTypes = schemaTypes.filter(t => 
      ['Query', 'Mutation', 'Subscription'].includes(t.name)
    );

    const allDiagramTypes = [...rootTypes, ...objectTypes];
    const typeNames = new Set(allDiagramTypes.map(t => t.name));

    // Calculate node dimensions
    const nodeWidth = 200;
    const nodeHeaderHeight = 36;
    const fieldHeight = 24;
    
    // Position nodes in a grid with some intelligence
    const cols = Math.ceil(Math.sqrt(allDiagramTypes.length));
    const spacingX = 280;
    const spacingY = 40;
    
    let currentY = 50;
    let currentX = 50;
    let maxHeightInRow = 0;
    let colIndex = 0;

    const diagramNodes: DiagramNode[] = allDiagramTypes.map((type) => {
      const fieldsCount = type.fields?.length || 0;
      const height = nodeHeaderHeight + Math.min(fieldsCount, 8) * fieldHeight + 10;
      
      if (colIndex >= cols) {
        colIndex = 0;
        currentX = 50;
        currentY += maxHeightInRow + spacingY;
        maxHeightInRow = 0;
      }
      
      const node: DiagramNode = {
        id: type.name,
        x: currentX,
        y: currentY,
        width: nodeWidth,
        height: height,
        type: type
      };
      
      currentX += spacingX;
      maxHeightInRow = Math.max(maxHeightInRow, height);
      colIndex++;
      
      return node;
    });

    // Build edges based on field types
    const diagramEdges: DiagramEdge[] = [];
    allDiagramTypes.forEach(type => {
      type.fields?.forEach(field => {
        if (typeNames.has(field.typeName)) {
          diagramEdges.push({
            from: type.name,
            to: field.typeName,
            fieldName: field.name
          });
        }
      });
    });

    setNodes(diagramNodes);
    setEdges(diagramEdges);
  };

  const getKindColor = (kind: string) => {
    switch (kind) {
      case 'OBJECT': return '#61affe';
      case 'INPUT_OBJECT': return '#50e3c2';
      case 'ENUM': return '#f5a623';
      case 'SCALAR': return '#8b5cf6';
      case 'INTERFACE': return '#e879f9';
      case 'UNION': return '#f87171';
      default: return '#9ca3af';
    }
  };

  const getNodeColor = (name: string) => {
    if (name === 'Query') return '#10b981';
    if (name === 'Mutation') return '#f59e0b';
    if (name === 'Subscription') return '#8b5cf6';
    return '#3b82f6';
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    if (e.button === 0) {
      setDragging(true);
      setDragStart({ x: e.clientX - pan.x, y: e.clientY - pan.y });
    }
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (dragging) {
      setPan({
        x: e.clientX - dragStart.x,
        y: e.clientY - dragStart.y
      });
    }
  };

  const handleMouseUp = () => {
    setDragging(false);
  };

  const handleWheel = (e: React.WheelEvent) => {
    e.preventDefault();
    const delta = e.deltaY > 0 ? -0.1 : 0.1;
    setZoom(z => Math.min(Math.max(0.3, z + delta), 2));
  };

  const getEdgePath = (edge: DiagramEdge) => {
    const fromNode = nodes.find(n => n.id === edge.from);
    const toNode = nodes.find(n => n.id === edge.to);
    if (!fromNode || !toNode) return '';

    const fromX = fromNode.x + fromNode.width;
    const fromY = fromNode.y + fromNode.height / 2;
    const toX = toNode.x;
    const toY = toNode.y + toNode.height / 2;

    // Self-referencing edge
    if (edge.from === edge.to) {
      return `M ${fromX} ${fromY - 20} 
              C ${fromX + 60} ${fromY - 60}, 
                ${fromX + 60} ${fromY + 60}, 
                ${fromX} ${fromY + 20}`;
    }

    const midX = (fromX + toX) / 2;
    return `M ${fromX} ${fromY} C ${midX} ${fromY}, ${midX} ${toY}, ${toX} ${toY}`;
  };

  const toggleType = (typeName: string) => {
    setExpandedTypes(prev => {
      const newSet = new Set(prev);
      if (newSet.has(typeName)) {
        newSet.delete(typeName);
      } else {
        newSet.add(typeName);
      }
      return newSet;
    });
  };

  const filteredTypes = types.filter(t => 
    t.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    t.fields?.some(f => f.name.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  // Group types by kind
  const queryType = filteredTypes.find(t => t.name === 'Query');
  const mutationType = filteredTypes.find(t => t.name === 'Mutation');
  const subscriptionType = filteredTypes.find(t => t.name === 'Subscription');
  const objectTypes = filteredTypes.filter(t => t.kind === 'OBJECT' && !['Query', 'Mutation', 'Subscription'].includes(t.name));
  const inputTypes = filteredTypes.filter(t => t.kind === 'INPUT_OBJECT');
  const enumTypes = filteredTypes.filter(t => t.kind === 'ENUM');
  const scalarTypes = filteredTypes.filter(t => t.kind === 'SCALAR');

  useEffect(() => {
    fetchSchema();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const renderTypeCard = (type: SchemaType) => {
    const isExpanded = expandedTypes.has(type.name);
    
    return (
      <div key={type.name} className="type-card">
        <div 
          className="type-header" 
          onClick={() => toggleType(type.name)}
          style={{ borderLeftColor: getKindColor(type.kind) }}
        >
          <div className="type-info">
            {type.fields ? (
              isExpanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />
            ) : <span style={{ width: 16 }} />}
            <span className="type-name">{type.name}</span>
            <span className="type-kind" style={{ backgroundColor: getKindColor(type.kind) }}>
              {type.kind}
            </span>
            {type.totalCost !== undefined && type.totalCost > 0 && (
              <span className={`type-cost ${type.totalCost > 100 ? 'high' : type.totalCost > 30 ? 'medium' : 'low'}`}>
                ⚡ {type.totalCost}
              </span>
            )}
          </div>
        </div>
        {isExpanded && type.fields && (
          <div className="type-fields">
            {type.fields.map(field => (
              <div key={field.name} className="field-item">
                <span className={`field-cost-indicator ${field.cost > 50 ? 'high' : field.cost > 10 ? 'medium' : 'low'}`}>
                  {field.cost}
                </span>
                <span className="field-name">{field.name}</span>
                {field.args && field.args.length > 0 && (
                  <span className="field-args">
                    ({field.args.map(a => `${a.name}: ${a.type}`).join(', ')})
                  </span>
                )}
                <span className="field-type">{field.type}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  };

  const renderTypeSection = (title: string, types: SchemaType[]) => {
    if (types.length === 0) return null;
    return (
      <div className="type-section">
        <h3 className="section-title">{title} ({types.length})</h3>
        {types.map(renderTypeCard)}
      </div>
    );
  };

  const renderDiagram = () => (
    <div className="diagram-container">
      <div className="diagram-toolbar">
        <button onClick={() => setZoom(z => Math.min(z + 0.2, 2))} title="Zoom In">
          <ZoomIn size={18} />
        </button>
        <span className="zoom-level">{Math.round(zoom * 100)}%</span>
        <button onClick={() => setZoom(z => Math.max(z - 0.2, 0.3))} title="Zoom Out">
          <ZoomOut size={18} />
        </button>
        <button onClick={() => { setZoom(1); setPan({ x: 0, y: 0 }); }} title="Reset">
          <Move size={18} />
        </button>
      </div>
      <svg
        ref={svgRef}
        className="schema-diagram"
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        onWheel={handleWheel}
      >
        <defs>
          <marker
            id="arrowhead"
            markerWidth="10"
            markerHeight="7"
            refX="9"
            refY="3.5"
            orient="auto"
          >
            <polygon points="0 0, 10 3.5, 0 7" fill="#6b7280" />
          </marker>
        </defs>
        <g transform={`translate(${pan.x}, ${pan.y}) scale(${zoom})`}>
          {/* Edges */}
          {edges.map((edge, i) => (
            <path
              key={`${edge.from}-${edge.to}-${i}`}
              d={getEdgePath(edge)}
              fill="none"
              stroke="#4b5563"
              strokeWidth="2"
              markerEnd="url(#arrowhead)"
              opacity={selectedNode ? (selectedNode === edge.from || selectedNode === edge.to ? 1 : 0.2) : 0.6}
            />
          ))}
          
          {/* Nodes */}
          {nodes.map(node => (
            <g
              key={node.id}
              transform={`translate(${node.x}, ${node.y})`}
              onClick={() => setSelectedNode(selectedNode === node.id ? null : node.id)}
              style={{ cursor: 'pointer' }}
              opacity={selectedNode ? (selectedNode === node.id || edges.some(e => 
                (e.from === selectedNode && e.to === node.id) || 
                (e.to === selectedNode && e.from === node.id)
              ) ? 1 : 0.3) : 1}
            >
              {/* Node background */}
              <rect
                width={node.width}
                height={node.height}
                rx="8"
                fill="#1e1e2e"
                stroke={selectedNode === node.id ? '#8b5cf6' : getNodeColor(node.type.name)}
                strokeWidth={selectedNode === node.id ? 3 : 2}
              />
              
              {/* Node header */}
              <rect
                width={node.width}
                height="36"
                rx="8"
                fill={getNodeColor(node.type.name)}
              />
              <rect
                y="28"
                width={node.width}
                height="8"
                fill={getNodeColor(node.type.name)}
              />
              
              {/* Node title */}
              <text
                x={node.width / 2}
                y="24"
                textAnchor="middle"
                fill="white"
                fontSize="14"
                fontWeight="bold"
              >
                {node.type.name}
              </text>
              
              {/* Fields */}
              {node.type.fields?.slice(0, 8).map((field, idx) => (
                <g key={field.name} transform={`translate(0, ${40 + idx * 24})`}>
                  {/* Cost indicator bar */}
                  <rect
                    x="0"
                    y="4"
                    width={Math.min(field.cost * 2, 6)}
                    height="14"
                    fill={field.cost > 50 ? '#ef4444' : field.cost > 10 ? '#f59e0b' : '#10b981'}
                    opacity="0.6"
                  />
                  <text x="10" y="16" fill="#a78bfa" fontSize="12">
                    {field.name}
                  </text>
                  <text x={node.width - 10} y="16" textAnchor="end" fill="#10b981" fontSize="11">
                    {field.type.length > 15 ? field.type.substring(0, 15) + '...' : field.type}
                  </text>
                </g>
              ))}
              
              {/* More fields indicator */}
              {(node.type.fields?.length || 0) > 8 && (
                <text
                  x={node.width / 2}
                  y={node.height - 8}
                  textAnchor="middle"
                  fill="#6b7280"
                  fontSize="11"
                >
                  +{(node.type.fields?.length || 0) - 8} more fields
                </text>
              )}
            </g>
          ))}
        </g>
      </svg>
      
      {selectedNode && (() => {
        const selectedType = nodes.find(n => n.id === selectedNode)?.type;
        const connectedEdges = edges.filter(e => e.from === selectedNode || e.to === selectedNode);
        const highCostFields = selectedType?.fields?.filter(f => f.cost > 10) || [];
        const listFields = selectedType?.fields?.filter(f => f.isList) || [];
        
        return (
          <div className="node-details">
            <div className="node-details-header">
              <h4>{selectedNode}</h4>
              {selectedType?.totalCost !== undefined && (
                <div className="total-cost">
                  <DollarSign size={14} />
                  <span>Total Complexity: <strong>{selectedType.totalCost}</strong></span>
                </div>
              )}
            </div>
            
            <div className="cost-breakdown">
              <div className="cost-section">
                <span className="cost-label">Fields:</span>
                <span className="cost-value">{selectedType?.fields?.length || 0}</span>
              </div>
              <div className="cost-section">
                <span className="cost-label">Connections:</span>
                <span className="cost-value">{connectedEdges.length}</span>
              </div>
              {highCostFields.length > 0 && (
                <div className="cost-section warning">
                  <span className="cost-label">⚠️ High cost fields:</span>
                  <span className="cost-value">{highCostFields.length}</span>
                </div>
              )}
              {listFields.length > 0 && (
                <div className="cost-section">
                  <span className="cost-label">📋 List fields:</span>
                  <span className="cost-value">{listFields.length}</span>
                </div>
              )}
            </div>

            {highCostFields.length > 0 && (
              <div className="high-cost-fields">
                <span className="section-label">Expensive Fields:</span>
                <div className="field-costs">
                  {highCostFields.slice(0, 5).map(f => (
                    <div key={f.name} className="field-cost-item">
                      <span className="field-cost-name">{f.name}</span>
                      <span className="field-cost-value" style={{ 
                        color: f.cost > 50 ? '#ef4444' : '#f59e0b' 
                      }}>
                        {f.cost} {f.isList && '(list)'}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {connectedEdges.length > 0 && (
              <div className="connections">
                <span className="section-label">Relationships:</span>
                <div className="connection-tags">
                  {connectedEdges.map((e, i) => (
                    <span key={i} className="connection-tag">
                      {e.from === selectedNode ? `→ ${e.to}` : `← ${e.from}`}
                      <small>({e.fieldName})</small>
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        );
      })()}
    </div>
  );

  return (
    <div className="schema-viewer">
      <div className="schema-header">
        <div className="schema-title">
          <Network size={32} />
          <h2>GraphQL Schema Explorer</h2>
        </div>
        <div className="schema-controls">
          <div className="view-toggle">
            <button 
              className={`toggle-btn ${viewMode === 'diagram' ? 'active' : ''}`}
              onClick={() => setViewMode('diagram')}
            >
              Diagram
            </button>
            <button 
              className={`toggle-btn ${viewMode === 'list' ? 'active' : ''}`}
              onClick={() => setViewMode('list')}
            >
              List
            </button>
            <button 
              className={`toggle-btn ${viewMode === 'sdl' ? 'active' : ''}`}
              onClick={() => setViewMode('sdl')}
            >
              SDL
            </button>
          </div>
          <button 
            className="btn btn-secondary" 
            onClick={fetchSchema} 
            disabled={loading}
          >
            <RefreshCw size={16} className={loading ? 'spinning' : ''} />
            {loading ? 'Loading...' : 'Refresh'}
          </button>
        </div>
      </div>

      {error && (
        <div className="error-banner">
          <p>{error}</p>
        </div>
      )}

      {loading ? (
        <div className="schema-loading">
          <RefreshCw size={48} className="spinning" />
          <p>Fetching schema...</p>
        </div>
      ) : viewMode === 'diagram' ? (
        renderDiagram()
      ) : viewMode === 'list' ? (
        <div className="schema-visual">
          <div className="search-box">
            <Search size={18} />
            <input
              type="text"
              placeholder="Search types and fields..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
          <div className="types-container">
            {queryType && renderTypeSection('Queries', [queryType])}
            {mutationType && renderTypeSection('Mutations', [mutationType])}
            {subscriptionType && renderTypeSection('Subscriptions', [subscriptionType])}
            {renderTypeSection('Types', objectTypes)}
            {renderTypeSection('Input Types', inputTypes)}
            {renderTypeSection('Enums', enumTypes)}
            {renderTypeSection('Scalars', scalarTypes)}
          </div>
        </div>
      ) : (
        <div className="schema-sdl">
          <pre><code>{sdl}</code></pre>
        </div>
      )}
    </div>
  );
}
