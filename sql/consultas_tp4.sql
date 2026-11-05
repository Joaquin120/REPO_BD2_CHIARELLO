-- ============================================================================
-- Proyecto Integrador: Food Store
-- Entrega: TP4 - Reportes Analíticos: Joins, Subconsultas, Agregación y Ventanas
-- Motor: PostgreSQL 16+
-- Cátedra: Base de Datos II - Tecnicatura Universitaria en Programación (UTN)
-- Rama Git: tp4-joins
-- Autor: Joaquin Chiarello
-- ============================================================================
-- Este script implementa:
--   1. Índices estratégicos de cobertura y parciales para optimizar nodos de Join.
--   2. Consulta 1: Facturación mensual acumulada por categoría con bajas lógicas.
--   3. Consulta 2: Ranking de clientes por gasto acumulado total con pedidos vigentes.
--   4. Parte 3 (Spec A y Spec B): Ranking analítico con función de ventana DENSE_RANK()
--      resuelto por dos métodos algebraicamente distintos (JOIN directo vs CTE derivada).
--   5. Verificación formal de equivalencia matemática mediante bloques EXCEPT bidireccionales.
-- ============================================================================

-- ============================================================================
-- PARTE 1: ÍNDICES PROPUESTOS Y PROBADOS PARA OPTIMIZAR NODOS DE JOIN
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ÍNDICE 1: idx_detalle_pedido_producto_subtotal
-- ----------------------------------------------------------------------------
-- Tipo: Índice B-Tree de cobertura multi-columna (Covering Composite Index).
-- Tabla: detalle_pedido
-- Columnas: (producto_id, precio_unitario, cantidad)
--
-- Fundamento Técnico y Mecánica de Optimización:
-- 1. En los joins naturales entre 'producto' y 'detalle_pedido', la clave foránea
--    'producto_id' es el predicado de cruce equijoin (dp.producto_id = pr.id).
-- 2. La clave primaria de 'detalle_pedido' es compuesta: (pedido_id, producto_id).
--    Por la regla del prefijo líder (Left-Prefix Matching), el índice de PK no sirve
--    para buscar eficientemente por 'producto_id' sin escanear la tabla completa.
-- 3. Al colocar 'producto_id' como columna líder y adicionar 'precio_unitario' y 'cantidad',
--    el motor puede:
--      a) Ejecutar un 'Index Scan' o 'Index Only Scan' para resolver el join.
--      b) Calcular el subtotal SUM(dp.precio_unitario * dp.cantidad) directamente
--         desde las páginas del índice sin tocar los bloques del heap (tabla física),
--         eliminando miles de lecturas de I/O de disco.
CREATE INDEX IF NOT EXISTS idx_detalle_pedido_producto_subtotal 
ON detalle_pedido(producto_id, precio_unitario, cantidad);

COMMENT ON INDEX idx_detalle_pedido_producto_subtotal IS 
'Índice compuesto de cobertura en detalle_pedido para acelerar joins con producto y agregación de subtotales sin acceso al heap.';

-- ----------------------------------------------------------------------------
-- ÍNDICE 2: idx_pedido_fecha_cliente
-- ----------------------------------------------------------------------------
-- Tipo: Índice B-Tree parcial compuesto (Partial Composite Index).
-- Tabla: pedido
-- Columnas: (fecha, cliente_id)
-- Predicado (Filtro): WHERE eliminado = FALSE
--
-- Fundamento Técnico y Mecánica de Optimización:
-- 1. Resuelve de forma simultánea el agrupamiento cronológico DATE_TRUNC('month', fecha)
--    y el cruce por clave foránea hacia 'cliente'.
-- 2. Predicado Parcial (WHERE eliminado = FALSE):
--    Excluye del árbol B-Tree todas las órdenes canceladas o dadas de baja lógica.
--    Esto reduce la profundidad del índice, minimiza la ocupación en shared_buffers
--    y suprime por completo los costos de 'Filter: (NOT eliminado)' con 'Rows Removed by Filter'.
CREATE INDEX IF NOT EXISTS idx_pedido_fecha_cliente 
ON pedido(fecha, cliente_id) 
WHERE eliminado = FALSE;

COMMENT ON INDEX idx_pedido_fecha_cliente IS 
'Índice parcial sobre pedidos no eliminados optimizado para agregaciones temporales mensuales y joins por cliente_id.';

-- ----------------------------------------------------------------------------
-- ÍNDICE 3: idx_pedido_cliente_eliminado (Complementario para Joins Directos)
-- ----------------------------------------------------------------------------
-- Tipo: Índice B-Tree parcial mono-columna.
-- Tabla: pedido
-- Columna: (cliente_id)
-- Predicado: WHERE eliminado = FALSE
--
-- Fundamento Técnico:
-- Acelera el equijoin c.id = p.cliente_id en la Consulta 2 y en la Spec A/B,
-- aislando inmediatamente las órdenes válidas por cliente en O(log N).
CREATE INDEX IF NOT EXISTS idx_pedido_cliente_eliminado 
ON pedido(cliente_id) 
WHERE eliminado = FALSE;

COMMENT ON INDEX idx_pedido_cliente_eliminado IS 
'Índice parcial en pedido(cliente_id) WHERE eliminado = FALSE para equijoins con cliente en consultas analíticas.';


-- ============================================================================
-- PARTE 2: CONSULTAS ANALÍTICAS PRINCIPALES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CONSULTA 1: Facturación mensual acumulada por categoría
-- ----------------------------------------------------------------------------
-- Cruzando: pedido (p), detalle_pedido (dp), producto (pr) y categoria (c).
-- Filtros de negocio (Bajas Lógicas):
--   * categoria.activo = TRUE
--   * producto.activo = TRUE
--   * pedido.eliminado = FALSE
-- Métricas calculadas:
--   * Año y mes de corte: DATE_TRUNC('month', p.fecha)
--   * Nombre de la categoría
--   * Total facturado: SUM(dp.precio_unitario * dp.cantidad)
--   * Pedidos únicos: COUNT(DISTINCT p.id)
--   * Unidades totales vendidas: SUM(dp.cantidad)
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE, TIMING)
SELECT 
    DATE_TRUNC('month', p.fecha)::date AS mes_corte,
    c.nombre AS categoria,
    ROUND(SUM(dp.precio_unitario * dp.cantidad)::numeric, 2) AS total_facturado,
    COUNT(DISTINCT p.id) AS cantidad_pedidos_unicos,
    SUM(dp.cantidad) AS unidades_totales_vendidas
FROM pedido p
JOIN detalle_pedido dp ON p.id = dp.pedido_id
JOIN producto pr ON dp.producto_id = pr.id
JOIN categoria c ON pr.categoria_id = c.id
WHERE p.eliminado = FALSE
  AND pr.activo = TRUE
  AND c.activo = TRUE
GROUP BY DATE_TRUNC('month', p.fecha), c.id, c.nombre
ORDER BY mes_corte DESC, total_facturado DESC;


-- ----------------------------------------------------------------------------
-- CONSULTA 2: Ranking de clientes por gasto acumulado total con pedidos vigentes
-- ----------------------------------------------------------------------------
-- Cruzando: cliente (c), pedido (p) y detalle_pedido (dp).
-- Filtros de negocio (Bajas Lógicas):
--   * cliente.activo = TRUE
--   * pedido.eliminado = FALSE
-- Métricas calculadas:
--   * cliente_id
--   * Nombre completo (concatenación nombre y apellido)
--   * Total gastado: SUM(dp.precio_unitario * dp.cantidad)
--   * Cantidad de órdenes: COUNT(DISTINCT p.id)
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE, TIMING)
SELECT 
    c.id AS cliente_id,
    c.nombre || ' ' || c.apellido AS nombre_completo,
    ROUND(SUM(dp.precio_unitario * dp.cantidad)::numeric, 2) AS total_gastado,
    COUNT(DISTINCT p.id) AS total_ordenes
FROM cliente c
JOIN pedido p ON c.id = p.cliente_id
JOIN detalle_pedido dp ON p.id = dp.pedido_id
WHERE c.activo = TRUE
  AND p.eliminado = FALSE
GROUP BY c.id, c.nombre, c.apellido
ORDER BY total_gastado DESC;


-- ============================================================================
-- PARTE 3: ESPECIFICACIÓN PRECISA, VENTANAS Y DEMOSTRACIÓN DE EQUIVALENCIA
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SPEC A: Enunciado Formal en Lenguaje Natural
-- "Generar el ranking analítico de clientes vigentes (cliente.activo = TRUE)
-- considerando únicamente órdenes no eliminadas (pedido.eliminado = FALSE).
-- El reporte debe proyectar: identificador del cliente (cliente_id), su nombre
-- completo (nombre_completo), el gasto acumulado histórico total (gasto_acumulado)
-- y su posición ordinal en el ranking analítico (ranking), asignada mediante la
-- función de ventana DENSE_RANK() calculada sobre el total gastado en orden descendente.
-- Clientes con idéntico monto acumulado deben compartir la misma posición ordinal
-- sin generar saltos correlativos en los puestos posteriores. El resultado debe
-- ordenarse de forma determinista por posición del ranking ascendente y por cliente_id."
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- SPEC B - FORMULACIÓN 1: JOIN Directo con GROUP BY y Ventana
-- ----------------------------------------------------------------------------
-- Esta variante realiza el cruce relacional completo de las 3 tablas, agrupa
-- en primera instancia por clave primaria y datos del cliente, y evalúa
-- DENSE_RANK() sobre el agregado en una única pasada de pipeline.
-- ----------------------------------------------------------------------------
SELECT 
    c.id AS cliente_id,
    c.nombre || ' ' || c.apellido AS nombre_completo,
    ROUND(SUM(dp.precio_unitario * dp.cantidad)::numeric, 2) AS gasto_acumulado,
    DENSE_RANK() OVER (ORDER BY SUM(dp.precio_unitario * dp.cantidad) DESC) AS ranking
FROM cliente c
JOIN pedido p ON c.id = p.cliente_id
JOIN detalle_pedido dp ON p.id = dp.pedido_id
WHERE c.activo = TRUE
  AND p.eliminado = FALSE
GROUP BY c.id, c.nombre, c.apellido
ORDER BY ranking ASC, cliente_id ASC;


-- ----------------------------------------------------------------------------
-- SPEC B - FORMULACIÓN 2: Subconsulta Derivada / CTE de Agregación Previa + Ventana
-- ----------------------------------------------------------------------------
-- Esta variante aísla primero el cálculo de facturación en una CTE ('gasto_por_cliente')
-- reduciendo la granularidad transaccional de 400.000 líneas a nivel cliente,
-- y luego efectúa el JOIN hacia la dimensión 'cliente' para proyectar el nombre
-- y aplicar la función de ventana DENSE_RANK().
-- ----------------------------------------------------------------------------
WITH gasto_por_cliente AS (
    SELECT 
        p.cliente_id,
        ROUND(SUM(dp.precio_unitario * dp.cantidad)::numeric, 2) AS gasto_acumulado
    FROM pedido p
    JOIN detalle_pedido dp ON p.id = dp.pedido_id
    WHERE p.eliminado = FALSE
    GROUP BY p.cliente_id
)
SELECT 
    c.id AS cliente_id,
    c.nombre || ' ' || c.apellido AS nombre_completo,
    g.gasto_acumulado,
    DENSE_RANK() OVER (ORDER BY g.gasto_acumulado DESC) AS ranking
FROM cliente c
JOIN gasto_por_cliente g ON c.id = g.cliente_id
WHERE c.activo = TRUE
ORDER BY ranking ASC, cliente_id ASC;


-- ============================================================================
-- VERIFICACIÓN FORMAL DE EQUIVALENCIA MATEMÁTICA CON EXCEPT BIDIRECCIONAL
-- ============================================================================
-- Teorema de Equivalencia Relacional:
-- Sean R_1 el conjunto de tuplas resultante de Formulación 1 y R_2 el de Formulación 2.
-- R_1 \equiv R_2 \iff (R_1 \setminus R_2 = \emptyset) \land (R_2 \setminus R_1 = \emptyset).
-- Ambas consultas deben devolver exactamente CERO filas (0 rows).
-- ============================================================================

-- BLOQUE 1: Tuplas en Formulación 1 que NO estén en Formulación 2 (R_1 EXCEPT R_2)
(
    SELECT 
        c.id AS cliente_id,
        c.nombre || ' ' || c.apellido AS nombre_completo,
        ROUND(SUM(dp.precio_unitario * dp.cantidad)::numeric, 2) AS gasto_acumulado,
        DENSE_RANK() OVER (ORDER BY SUM(dp.precio_unitario * dp.cantidad) DESC) AS ranking
    FROM cliente c
    JOIN pedido p ON c.id = p.cliente_id
    JOIN detalle_pedido dp ON p.id = dp.pedido_id
    WHERE c.activo = TRUE
      AND p.eliminado = FALSE
    GROUP BY c.id, c.nombre, c.apellido
)
EXCEPT
(
    WITH gasto_por_cliente AS (
        SELECT 
            p.cliente_id,
            ROUND(SUM(dp.precio_unitario * dp.cantidad)::numeric, 2) AS gasto_acumulado
        FROM pedido p
        JOIN detalle_pedido dp ON p.id = dp.pedido_id
        WHERE p.eliminado = FALSE
        GROUP BY p.cliente_id
    )
    SELECT 
        c.id AS cliente_id,
        c.nombre || ' ' || c.apellido AS nombre_completo,
        g.gasto_acumulado,
        DENSE_RANK() OVER (ORDER BY g.gasto_acumulado DESC) AS ranking
    FROM cliente c
    JOIN gasto_por_cliente g ON c.id = g.cliente_id
    WHERE c.activo = TRUE
);

-- BLOQUE 2: Tuplas en Formulación 2 que NO estén en Formulación 1 (R_2 EXCEPT R_1)
(
    WITH gasto_por_cliente AS (
        SELECT 
            p.cliente_id,
            ROUND(SUM(dp.precio_unitario * dp.cantidad)::numeric, 2) AS gasto_acumulado
        FROM pedido p
        JOIN detalle_pedido dp ON p.id = dp.pedido_id
        WHERE p.eliminado = FALSE
        GROUP BY p.cliente_id
    )
    SELECT 
        c.id AS cliente_id,
        c.nombre || ' ' || c.apellido AS nombre_completo,
        g.gasto_acumulado,
        DENSE_RANK() OVER (ORDER BY g.gasto_acumulado DESC) AS ranking
    FROM cliente c
    JOIN gasto_por_cliente g ON c.id = g.cliente_id
    WHERE c.activo = TRUE
)
EXCEPT
(
    SELECT 
        c.id AS cliente_id,
        c.nombre || ' ' || c.apellido AS nombre_completo,
        ROUND(SUM(dp.precio_unitario * dp.cantidad)::numeric, 2) AS gasto_acumulado,
        DENSE_RANK() OVER (ORDER BY SUM(dp.precio_unitario * dp.cantidad) DESC) AS ranking
    FROM cliente c
    JOIN pedido p ON c.id = p.cliente_id
    JOIN detalle_pedido dp ON p.id = dp.pedido_id
    WHERE c.activo = TRUE
      AND p.eliminado = FALSE
    GROUP BY c.id, c.nombre, c.apellido
);
