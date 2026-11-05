-- ============================================================================
-- Proyecto Integrador: Food Store
-- Entrega: TP3 - Estrategia de Indexación Profesional para Optimización de Consultas
-- Motor: PostgreSQL 16+
-- Cátedra: Base de Datos II - Tecnicatura Universitaria en Programación (UTN)
-- ============================================================================
-- Este script define 3 índices profesionales para resolver cuellos de botella
-- críticos detectados en el análisis de planes de ejecución (Seq Scan masivos).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ÍNDICE 1: idx_producto_categoria_precio
-- ----------------------------------------------------------------------------
-- Tipo: Índice B-Tree compuesto (Composite Index).
-- Tabla: producto
-- Columnas: (categoria_id, precio)
--
-- Justificación y Fundamento Técnico:
-- 1. Resuelve consultas frecuentes de navegación de menú y catálogo donde el cliente
--    filtra por una categoría específica y define un rango de presupuesto:
--    'WHERE categoria_id = $1 AND precio BETWEEN $2 AND $3 ORDER BY precio ASC'.
-- 2. Mecánica interna del árbol B-Tree:
--    - Columna Líder (categoria_id): Permite al motor descender por el árbol B-Tree
--      en tiempo logarítmico O(log N) hasta aislar el subárbol de la categoría buscada.
--    - Columna Secundaria (precio): Dentro de dicho subárbol, las hojas ya están
--      ordenadas físicamente por 'precio'. Esto habilita un 'Index Scan' que resuelve
--      el rango y entrega las filas ya ordenadas sin necesidad de ejecutar un nodo
--      'Sort' en memoria de trabajo (work_mem).
-- 3. Consolidación de índices: Este índice compuesto cubre además cualquier filtro
--    mono-columna sobre 'categoria_id', haciendo obsoleto un índice simple sobre dicha columna.

CREATE INDEX IF NOT EXISTS idx_producto_categoria_precio 
ON producto(categoria_id, precio);

COMMENT ON INDEX idx_producto_categoria_precio IS 
'Índice compuesto para optimizar filtros de menú por categoría y rangos de precio con ordenamiento implícito sin Sort.';

-- ----------------------------------------------------------------------------
-- ÍNDICE 2: idx_pedido_cliente_fecha
-- ----------------------------------------------------------------------------
-- Tipo: Índice B-Tree compuesto con ordenamiento descendente (Composite B-Tree with DESC sort).
-- Tabla: pedido
-- Columnas: (cliente_id, fecha DESC)
--
-- Justificación y Fundamento Técnico:
-- 1. Resuelve la consulta transaccional más habitual en el perfil del usuario:
--    'SELECT * FROM pedido WHERE cliente_id = $1 ORDER BY fecha DESC LIMIT 10;'.
-- 2. Eliminación de Sequential Scan y Ordenamiento en Disco:
--    - En ausencia de este índice, el motor realiza un 'Seq Scan' sobre los 200.000 pedidos,
--      filtra las filas del cliente en memoria y ejecuta un nodo 'Sort' (quicksort o external merge).
--    - Con 'idx_pedido_cliente_fecha', el planificador ejecuta un 'Index Scan' dirigido:
--      localiza el 'cliente_id' en el árbol B-Tree y recorre las hojas en orden descendente.
-- 3. Parada Temprana (Early Termination / StopKey):
--    Al estar las páginas del índice ordenadas en concordancia con el 'ORDER BY fecha DESC',
--    el nodo 'Limit' detiene la lectura exactamente al recuperar las primeras 10 tuplas.
--    El costo computacional pasa de O(N log N) a O(K) donde K=10, reduciendo el tiempo de 32ms a sub-milisegundo.

CREATE INDEX IF NOT EXISTS idx_pedido_cliente_fecha 
ON pedido(cliente_id, fecha DESC);

COMMENT ON INDEX idx_pedido_cliente_fecha IS 
'Índice compuesto para historial transaccional de pedidos por cliente con parada temprana (StopKey/Limit) sin ordenamiento en memoria.';

-- ----------------------------------------------------------------------------
-- ÍNDICE 3: idx_producto_nombre_vig
-- ----------------------------------------------------------------------------
-- Tipo: Índice B-Tree parcial (Partial B-Tree Index).
-- Tabla: producto
-- Columna: (nombre)
-- Predicado (Filtro): WHERE activo = TRUE
--
-- Justificación y Fundamento Técnico:
-- 1. Resuelve búsquedas puntuales o autocompletado de productos en el catálogo público activo:
--    'SELECT * FROM producto WHERE nombre = $1 AND activo = TRUE;'.
-- 2. Reducción de Huella en Memoria y B-Tree Depth:
--    - Un índice convencional indexaría la totalidad de los productos, incluidos los archivados,
--      discontinuados o dados de baja lógica (activo = FALSE).
--    - Al restringir el índice mediante 'WHERE activo = TRUE', solo las filas vigentes ocupan
--      bloques en disco y páginas en el búfer de memoria compartida (shared_buffers).
-- 3. Eficiencia en Escritura y Mantenimiento:
--    - Las modificaciones sobre productos inactivos no actualizan este índice B-Tree,
--      reduciendo la sobrecarga de WAL y la fragmentación de páginas por split.
--    - Elimina por completo los 'Rows Removed by Filter' observados en los Seq Scans.

CREATE INDEX IF NOT EXISTS idx_producto_nombre_vig 
ON producto(nombre) 
WHERE activo = TRUE;

COMMENT ON INDEX idx_producto_nombre_vig IS 
'Índice parcial sobre nombres de productos vigentes (activo=TRUE) para búsquedas directas con mínima huella de memoria.';
