-- ============================================================================
-- Proyecto Integrador: Food Store (Gestión de Pedidos de Comida)
-- Entrega: TP1 - Del Dominio al Esquema: Modelo ER, Normalización y DDL
-- Cátedra: Base de Datos II - Tecnicatura Universitaria en Programación (UTN)
-- Compatibilidad: PostgreSQL 16+
-- Estándar: SQL:2003 (Identity columns, tipos temporales con zona horaria)
-- ============================================================================

-- Limpieza idempotente en orden inverso a las dependencias referenciales
DROP TABLE IF EXISTS detalle_pedido CASCADE;
DROP TABLE IF EXISTS pedido CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;
DROP TYPE IF EXISTS forma_pago_enum CASCADE;

-- ----------------------------------------------------------------------------
-- 1. TIPOS ENUMERADOS
-- ----------------------------------------------------------------------------
-- Define el dominio cerrado e inmutable de medios de pago soportados por la tienda.
CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA');

-- ----------------------------------------------------------------------------
-- 2. TABLA: categoria
-- ----------------------------------------------------------------------------
-- Clasificación de los productos del menú (ej. Pizzas, Bebidas, Empanadas).
-- R1: Una categoría puede tener muchos productos o ninguno (participación parcial).
-- R7: Baja lógica mediante 'activo' para no eliminar registros físicos referenciados.
CREATE TABLE categoria (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    descripcion VARCHAR(255),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- ----------------------------------------------------------------------------
-- 3. TABLA: cliente
-- ----------------------------------------------------------------------------
-- Clientes registrados del sistema de comida.
-- R2: Puede no tener pedidos aún o tener varios (participación parcial en pedidos).
-- R6: Email único que identifica inequívocamente al cliente.
-- 1FN: Desacoplamiento atómico de nombre y apellido.
CREATE TABLE cliente (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    telefono VARCHAR(30),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- ----------------------------------------------------------------------------
-- 4. TABLA: producto
-- ----------------------------------------------------------------------------
-- Catálogo de comidas y bebidas comercializadas por Food Store.
-- R1: Todo producto pertenece obligatoriamente a una categoría (participación total).
-- R5: Stock y precio estrictamente no negativos.
-- R7: Baja lógica con 'activo' para conservar historial de ventas sin romper FKs.
-- FK ON DELETE RESTRICT: Impide borrar una categoría que tenga productos asociados.
CREATE TABLE producto (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    descripcion TEXT,
    precio NUMERIC(12,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    categoria_id BIGINT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_producto_precio CHECK (precio >= 0),
    CONSTRAINT chk_producto_stock CHECK (stock >= 0),
    CONSTRAINT fk_producto_categoria FOREIGN KEY (categoria_id) 
        REFERENCES categoria(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 5. TABLA: pedido
-- ----------------------------------------------------------------------------
-- Cabecera de la transacción de compra realizada por un cliente.
-- R2: Todo pedido pertenece exactamente a un cliente registrado (participación total).
-- FK ON DELETE RESTRICT: Prohíbe eliminar un cliente si registra pedidos históricos.
CREATE TABLE pedido (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id BIGINT NOT NULL,
    fecha TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    forma_pago forma_pago_enum NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (cliente_id) 
        REFERENCES cliente(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 6. TABLA: detalle_pedido
-- ----------------------------------------------------------------------------
-- Entidad asociativa que resuelve la relación N:M entre pedido y producto.
--
-- Decisiones de diseño e integridad:
-- 1. Clave Primaria compuesta (pedido_id, producto_id): garantiza que un producto
--    no se duplique en líneas separadas dentro del mismo pedido.
-- 2. Congelamiento de precios (R4): 'precio_unitario' almacena el precio de lista
--    vigente al momento exacto de la compra. Si el precio en 'producto' varía en
--    el futuro, las órdenes históricas permanecen inalteradas contablemente.
-- 3. ON DELETE CASCADE hacia pedido: El detalle carece de existencia independiente;
--    si una orden se descarta/anula en cascada operacional, sus líneas se borran con ella.
-- 4. ON DELETE RESTRICT hacia producto: Un producto que haya sido vendido jamás puede
--    ser eliminado físicamente de la base de datos (debe darse de baja lógica).
-- 5. 3FN / BCNF: Se omite 'subtotal' persistido para evitar redundancia y anomalías;
--    se computa al vuelo mediante (precio_unitario * cantidad).
CREATE TABLE detalle_pedido (
    pedido_id BIGINT NOT NULL,
    producto_id BIGINT NOT NULL,
    precio_unitario NUMERIC(12,2) NOT NULL,
    cantidad INT NOT NULL,
    CONSTRAINT pk_detalle_pedido PRIMARY KEY (pedido_id, producto_id),
    CONSTRAINT fk_detalle_pedido_pedido FOREIGN KEY (pedido_id) 
        REFERENCES pedido(id) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_pedido_producto FOREIGN KEY (producto_id) 
        REFERENCES producto(id) ON DELETE RESTRICT,
    CONSTRAINT chk_detalle_precio CHECK (precio_unitario >= 0),
    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0)
);

-- ----------------------------------------------------------------------------
-- 7. ÍNDICES Y ESTRATEGIAS DE OPTIMIZACIÓN
-- ----------------------------------------------------------------------------

-- Índice 1: Navegación de productos por categoría y aceleración de JOINs.
-- PostgreSQL no indexa automáticamente las claves foráneas.
-- Justificación: Acelera consultas del tipo 'SELECT * FROM producto WHERE categoria_id = ?'
-- y optimiza los JOINs entre categoria y producto, evitando escaneos secuenciales.
CREATE INDEX idx_producto_categoria ON producto(categoria_id);

-- Índice 2: Historial de pedidos por cliente y optimización de integridad referencial.
-- Justificación: Acelera consultas frecuentes de compras por cliente
-- (ej. 'SELECT * FROM pedido WHERE cliente_id = ? ORDER BY fecha DESC') y optimiza la
-- verificación de restricciones FK ante operaciones sobre la tabla cliente.
CREATE INDEX idx_pedido_cliente ON pedido(cliente_id);

-- Índice 3: Índice parcial para catálogo activo y navegable de comida.
-- Justificación: En Food Store, la gran mayoría de las consultas del menú público consultan
-- únicamente productos vigentes ('WHERE categoria_id = ? AND activo = TRUE'). Al indexar
-- exclusivamente las filas donde activo = TRUE, el tamaño del árbol B-Tree en memoria buffer
-- es significativamente menor y se omiten ítems discontinuados o dados de baja lógica.
CREATE INDEX idx_producto_activo ON producto(categoria_id) WHERE activo = TRUE;
