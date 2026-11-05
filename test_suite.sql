-- ============================================================================
-- Batería de Pruebas de Integridad: Food Store (schema.sql)
-- Motor: PostgreSQL 16+
-- ============================================================================

BEGIN;

-- 1. Inserción de datos maestros válidos (Happy Path)
INSERT INTO categoria (nombre, descripcion) 
VALUES ('Pizzas', 'Pizzas artesanales al horno de barro'),
       ('Bebidas', 'Gaseosas y aguas saborizadas');

INSERT INTO cliente (nombre, apellido, email, telefono) 
VALUES ('Ana', 'Gómez', 'ana.gomez@gmail.com', '1145678901'),
       ('Luis', 'Paz', 'luis.paz@hotmail.com', '1198765432');

INSERT INTO producto (nombre, descripcion, precio, stock, categoria_id) 
VALUES ('Muzzarella', 'Muzzarella clásica con aceitunas verdes', 1000.00, 50, 1),
       ('Napolitana', 'Muzzarella, rodajas de tomate y ajo', 1500.00, 30, 1),
       ('Coca 1.5L', 'Gaseosa cola en botella retornable', 800.00, 100, 2);

-- 2. Registro de pedidos con diferentes medios de pago
INSERT INTO pedido (cliente_id, forma_pago) 
VALUES (1, 'EFECTIVO'),
       (2, 'TARJETA');

-- 3. Detalle de pedidos con congelamiento de precios históricos
INSERT INTO detalle_pedido (pedido_id, producto_id, precio_unitario, cantidad) 
VALUES (1, 1, 1000.00, 2), -- Pedido 1: 2 Muzzarellas a $1000.00
       (1, 3, 800.00, 1),  -- Pedido 1: 1 Coca 1.5L a $800.00
       (2, 2, 1500.00, 1); -- Pedido 2: 1 Napolitana a $1500.00

-- 4. Verificación de cálculo al vuelo de subtotales y totales
SELECT 
    p.id AS pedido_nro,
    p.fecha,
    c.apellido || ', ' || c.nombre AS cliente,
    pr.nombre AS producto,
    cat.nombre AS categoria,
    dp.precio_unitario,
    dp.cantidad,
    (dp.precio_unitario * dp.cantidad) AS subtotal,
    p.forma_pago
FROM pedido p
JOIN cliente c ON p.cliente_id = c.id
JOIN detalle_pedido dp ON dp.pedido_id = p.id
JOIN producto pr ON dp.producto_id = pr.id
JOIN categoria cat ON pr.categoria_id = cat.id
ORDER BY p.id, dp.producto_id;

-- 5. Consulta sobre catálogo activo utilizando el índice parcial
EXPLAIN ANALYZE 
SELECT id, nombre, precio, stock 
FROM producto 
WHERE categoria_id = 1 AND activo = TRUE;

ROLLBACK;

-- ============================================================================
-- Casos de Prueba Negativos (Descomentar para validar el rechazo del motor)
-- ============================================================================

-- A. Violación de precio negativo:
-- INSERT INTO producto (nombre, precio, stock, categoria_id) VALUES ('Error Precio', -50.00, 10, 1);

-- B. Violación de stock negativo:
-- INSERT INTO producto (nombre, precio, stock, categoria_id) VALUES ('Error Stock', 100.00, -5, 1);

-- C. Violación de cantidad <= 0 en detalle:
-- INSERT INTO detalle_pedido (pedido_id, producto_id, precio_unitario, cantidad) VALUES (1, 1, 1000.00, 0);

-- D. Violación de unicidad en email de cliente:
-- INSERT INTO cliente (nombre, apellido, email) VALUES ('Pedro', 'Gómez', 'ana.gomez@gmail.com');

-- E. Violación de ON DELETE RESTRICT sobre producto vendido:
-- DELETE FROM producto WHERE id = 1;
