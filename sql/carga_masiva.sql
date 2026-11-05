-- ============================================================================
-- Proyecto Integrador: Food Store
-- Entrega: TP3 - Script de Carga Masiva y Poblado Sintético a Escala
-- Motor: PostgreSQL 16+
-- Cátedra: Base de Datos II - Tecnicatura Universitaria en Programación (UTN)
-- ============================================================================
-- Este script puebla la base de datos con un volumen representativo de producción:
--   * 5 Categorías base esenciales
--   * 50.000 Productos con distribución de precios y stock realista
--   * 20.000 Clientes con datos y correos únicos sintéticos
--   * 200.000 Pedidos distribuidos en los últimos 60 días
--   * 1 a 3 líneas de detalle por pedido (~400.000 tuplas en detalle_pedido)
--   * Refresco final de estadísticas del optimizador (ANALYZE)
-- ============================================================================

-- Ajustes de sesión para maximizar rendimiento de I/O en carga batch
SET client_min_messages = NOTICE;
SET work_mem = '64MB';
SET maintenance_work_mem = '512MB';
SET synchronous_commit = OFF;

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. CATEGORÍAS BASE
-- ----------------------------------------------------------------------------
-- Inserción idempotente de las 5 categorías esenciales del menú gastronómico.
INSERT INTO categoria (nombre, descripcion, activo)
VALUES 
    ('Pizzas', 'Pizzas tradicionales y gourmet al horno de barro', TRUE),
    ('Bebidas', 'Gaseosas, aguas minerales y cervezas artesanales', TRUE),
    ('Empanadas', 'Empanadas tradicionales salteñas, tucumanas y al horno', TRUE),
    ('Hamburguesas', 'Hamburguesas gourmet caseras con medallón vacuno', TRUE),
    ('Postres', 'Postres artesanales, helados y cafetería', TRUE)
ON CONFLICT (nombre) DO UPDATE 
SET descripcion = EXCLUDED.descripcion,
    activo = TRUE;

-- ----------------------------------------------------------------------------
-- 2. CLIENTES SINTÉTICOS (20.000 tuplas)
-- ----------------------------------------------------------------------------
-- Clientes con nombres, apellidos, emails corporativos de prueba y teléfonos.
\echo 'Generando 20.000 clientes sintéticos...'

INSERT INTO cliente (nombre, apellido, email, telefono, activo, created_at)
SELECT 
    'Cliente_' || s AS nombre,
    'Usuario_' || s AS apellido,
    'cliente_' || s || '@foodstore-qa.com' AS email,
    '11' || lpad((10000000 + s)::text, 8, '0') AS telefono,
    TRUE AS activo,
    clock_timestamp() - (random() * interval '90 days') AS created_at
FROM generate_series(1, 20000) AS s
ON CONFLICT (email) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 3. PRODUCTOS SINTÉTICOS (50.000 tuplas)
-- ----------------------------------------------------------------------------
-- Catálogo de 50.000 ítems distribuidos entre las categorías existentes.
-- Precios entre 500 y 5.000; Stock entre 0 y 200; activo = TRUE.
\echo 'Generando 50.000 productos sintéticos en catálogo...'

DO $$
DECLARE
    v_cat_ids BIGINT[];
    v_num_cats INT;
BEGIN
    SELECT array_agg(id) INTO v_cat_ids FROM categoria WHERE activo = TRUE;
    v_num_cats := array_length(v_cat_ids, 1);

    INSERT INTO producto (nombre, descripcion, precio, stock, categoria_id, activo, created_at)
    SELECT 
        CASE (s % 5)
            WHEN 0 THEN 'Pizza Especial Artesanal N.º ' || s
            WHEN 1 THEN 'Bebida Refrescante Premium N.º ' || s
            WHEN 2 THEN 'Empanada Tradicional Gourmet N.º ' || s
            WHEN 3 THEN 'Hamburguesa Doble Cheddar N.º ' || s
            ELSE 'Postre Dulce Casero N.º ' || s
        END AS nombre,
        'Descripción técnica del producto sintético para pruebas de carga N.º ' || s AS descripcion,
        round((500.00 + (random() * 4500.00))::numeric, 2) AS precio,
        floor(random() * 201)::int AS stock,
        v_cat_ids[1 + (s % v_num_cats)] AS categoria_id,
        TRUE AS activo,
        clock_timestamp() - (random() * interval '90 days') AS created_at
    FROM generate_series(1, 50000) AS s;
END $$;

-- ----------------------------------------------------------------------------
-- 4. PEDIDOS SINTÉTICOS (200.000 tuplas)
-- ----------------------------------------------------------------------------
-- Pedidos con cliente aleatorio (1 a 20.000), fecha en los últimos 60 días
-- (estrictamente menor o igual a clock_timestamp() para satisfacer el CHECK),
-- y distribución aleatoria del ENUM forma_pago ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA').
\echo 'Generando 200.000 pedidos transaccionales...'

DO $$
DECLARE
    v_min_cliente BIGINT;
    v_max_cliente BIGINT;
BEGIN
    SELECT min(id), max(id) INTO v_min_cliente, v_max_cliente FROM cliente;

    INSERT INTO pedido (cliente_id, fecha, forma_pago, eliminado, created_at)
    SELECT 
        (v_min_cliente + floor(random() * (v_max_cliente - v_min_cliente + 1)))::bigint AS cliente_id,
        clock_timestamp() - (random() * interval '60 days') AS fecha,
        (ARRAY['EFECTIVO'::forma_pago_enum, 'TARJETA'::forma_pago_enum, 'TRANSFERENCIA'::forma_pago_enum])[1 + floor(random() * 3)] AS forma_pago,
        FALSE AS eliminado,
        clock_timestamp() - (random() * interval '60 days') AS created_at
    FROM generate_series(1, 200000) AS s;
END $$;

-- ----------------------------------------------------------------------------
-- 5. DETALLE DE PEDIDOS (1 a 3 ítems por pedido, PK compuesta garantizada)
-- ----------------------------------------------------------------------------
-- Genera entre 1 y 3 líneas por pedido. Para no violar la PK (pedido_id, producto_id),
-- se calcula una función determinista que garantiza que para un mismo pedido
-- los productos asignados sean estrictamente distintos.
\echo 'Generando líneas de detalle_pedido (1 a 3 ítems por orden)...'

DO $$
DECLARE
    v_min_prod BIGINT;
    v_total_prod BIGINT;
BEGIN
    SELECT min(id), count(*) INTO v_min_prod, v_total_prod FROM producto;

    INSERT INTO detalle_pedido (pedido_id, producto_id, precio_unitario, cantidad)
    SELECT 
        p.id AS pedido_id,
        v_min_prod + ((p.id * 7 + l.linea * 1013) % v_total_prod) AS producto_id,
        round((500.00 + (random() * 4500.00))::numeric, 2) AS precio_unitario,
        (1 + floor(random() * 10))::int AS cantidad
    FROM pedido p
    CROSS JOIN LATERAL generate_series(1, 1 + floor(random() * 3)::int) AS l(linea)
    WHERE p.id > (SELECT coalesce(max(pedido_id), 0) FROM detalle_pedido)
    ON CONFLICT (pedido_id, producto_id) DO NOTHING;
END $$;

COMMIT;

-- Restaurar configuración de sincronismo para persistencia segura
SET synchronous_commit = ON;

-- ----------------------------------------------------------------------------
-- 6. ACTUALIZACIÓN INTEGRAL DE ESTADÍSTICAS DEL OPTIMIZADOR
-- ----------------------------------------------------------------------------
-- Notifica a pg_statistic sobre el volumen, histogramas de frecuencia y cardinalidad
-- para permitir al Cost-Based Optimizer (CBO) elegir los mejores planes de ejecución.
\echo 'Refrescando estadísticas del optimizador de PostgreSQL (ANALYZE)...'
ANALYZE categoria;
ANALYZE cliente;
ANALYZE producto;
ANALYZE pedido;
ANALYZE detalle_pedido;
ANALYZE;

\echo 'Carga masiva completada exitosamente.'
