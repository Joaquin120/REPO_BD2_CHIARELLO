-- ============================================================================
-- Proyecto Integrador: Food Store
-- Entrega: TP2 - Restricciones DDL Avanzadas, Integridad y Triggers PL/pgSQL
-- Motor: PostgreSQL 16+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. MODIFICACIÓN ESTRUCTURAL: Baja lógica en cabecera de pedidos
-- ----------------------------------------------------------------------------
-- Agrega la columna de borrado lógico 'eliminado'.
-- En PostgreSQL 11+, agregar una columna NOT NULL con DEFAULT no reescribe la tabla física.
-- Se registra de forma instantánea O(1) en los catálogos del sistema pg_attribute.
ALTER TABLE pedido 
    ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE;

-- ----------------------------------------------------------------------------
-- 2. RESTRICCIÓN DE DOMINIO: Control temporal de fechas en pedidos
-- ----------------------------------------------------------------------------
-- Regla de negocio: La fecha registrada para un pedido no puede pertenecer al futuro.
-- Fundamento técnico: En PostgreSQL, las restricciones CHECK declarativas exigen
-- funciones con volatilidad estrictamente inmutable (IMMUTABLE). La función
-- CURRENT_TIMESTAMP es STABLE, ya que varía entre transacciones.
-- Para satisfacer la restricción declarativa de forma compatible y determinista,
-- se define una función evaluadora inmutable como envoltorio de validación.

CREATE OR REPLACE FUNCTION fn_evaluar_fecha_no_futura(p_fecha TIMESTAMPTZ) 
RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_fecha <= clock_timestamp();
END;
$$ LANGUAGE plpgsql IMMUTABLE;

ALTER TABLE pedido 
    DROP CONSTRAINT IF EXISTS chk_pedido_fecha_no_futura;

ALTER TABLE pedido 
    ADD CONSTRAINT chk_pedido_fecha_no_futura 
    CHECK (fn_evaluar_fecha_no_futura(fecha));

-- ----------------------------------------------------------------------------
-- 3. RESTRICCIÓN DE RANGO: Cantidades operativas en detalle_pedido
-- ----------------------------------------------------------------------------
-- Regla de negocio: La cantidad solicitada por ítem debe situarse entre 1 y 100 unidades.
-- Sustituye de forma segura la restricción previa de TP1 (cantidad > 0).

ALTER TABLE detalle_pedido 
    DROP CONSTRAINT IF EXISTS chk_detalle_cantidad;

ALTER TABLE detalle_pedido 
    DROP CONSTRAINT IF EXISTS chk_detalle_cantidad_rango;

ALTER TABLE detalle_pedido 
    ADD CONSTRAINT chk_detalle_cantidad_rango 
    CHECK (cantidad >= 1 AND cantidad <= 100);

-- ----------------------------------------------------------------------------
-- 4. FUNCIÓN Y TRIGGER: Inmutabilidad de la baja lógica de pedidos
-- ----------------------------------------------------------------------------
-- Regla de negocio: Si un pedido fue marcado como eliminado (eliminado = TRUE),
-- queda estrictamente prohibida su reactivación (pasar a eliminado = FALSE).

CREATE OR REPLACE FUNCTION fn_impedir_reactivacion_pedido()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.eliminado = TRUE AND NEW.eliminado = FALSE THEN
        RAISE EXCEPTION 'Violación de regla de auditoría: No está permitido reactivar el pedido con ID % porque se encuentra dado de baja.', OLD.id
            USING ERRCODE = 'restrict_violation',
                  HINT = 'Los pedidos anulados en Food Store son definitivos e irrevocables.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_impedir_reactivacion_pedido ON pedido;

CREATE TRIGGER trg_impedir_reactivacion_pedido
    BEFORE UPDATE OF eliminado ON pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_impedir_reactivacion_pedido();

-- ============================================================================
-- 5. SUITE DE PRUEBAS DE INTEGRIDAD EN BLOQUE ANÓNIMO TRANSACCIONAL (DO)
-- ============================================================================
-- Ejecuta casos positivos y negativos en memoria protegida.
-- Captura excepciones esperadas para certificar que el motor rechace anomalías.

DO $$
DECLARE
    v_cliente_id BIGINT;
    v_categoria_id BIGINT;
    v_producto_id BIGINT;
    v_pedido_id BIGINT;
    v_error_detectado BOOLEAN;
BEGIN
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'INICIANDO BATERÍA DE PRUEBAS AUTOMATIZADAS DE INTEGRIDAD';
    RAISE NOTICE '============================================================';

    -- Preparación de entidades maestras para la prueba
    INSERT INTO categoria (nombre, descripcion)
    VALUES ('Minutas de Prueba', 'Categoría temporal para suite de pruebas')
    RETURNING id INTO v_categoria_id;

    INSERT INTO cliente (nombre, apellido, email, telefono)
    VALUES ('Tester', 'Operacional', 'tester.qa.' || clock_timestamp() || '@foodstore.com', '1122334455')
    RETURNING id INTO v_cliente_id;

    INSERT INTO producto (nombre, descripcion, precio, stock, categoria_id)
    VALUES ('Lomito Completo Test', 'Sándwich de prueba', 3500.00, 20, v_categoria_id)
    RETURNING id INTO v_producto_id;

    -- ------------------------------------------------------------------------
    -- PRUEBA 1: Validación de fecha futura en tabla pedido
    -- ------------------------------------------------------------------------
    v_error_detectado := FALSE;
    BEGIN
        INSERT INTO pedido (cliente_id, fecha, forma_pago)
        VALUES (v_cliente_id, clock_timestamp() + INTERVAL '10 days', 'EFECTIVO');
    EXCEPTION
        WHEN check_violation THEN
            v_error_detectado := TRUE;
            RAISE NOTICE '[OK] Regla 1 superada: El motor bloqueó el pedido con fecha futura (Error 23514).';
    END;

    IF NOT v_error_detectado THEN
        RAISE EXCEPTION 'Falla de Integridad: Se permitió insertar un pedido con fecha futura.';
    END IF;

    -- Inserción de pedido válido para las siguientes pruebas
    INSERT INTO pedido (cliente_id, fecha, forma_pago)
    VALUES (v_cliente_id, clock_timestamp(), 'EFECTIVO')
    RETURNING id INTO v_pedido_id;

    -- ------------------------------------------------------------------------
    -- PRUEBA 2: Validación de rango de cantidad (1 a 100) en detalle_pedido
    -- ------------------------------------------------------------------------
    -- Caso 2A: Cantidad inferior al mínimo permitido (cantidad = 0)
    v_error_detectado := FALSE;
    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, precio_unitario, cantidad)
        VALUES (v_pedido_id, v_producto_id, 3500.00, 0);
    EXCEPTION
        WHEN check_violation THEN
            v_error_detectado := TRUE;
            RAISE NOTICE '[OK] Regla 2A superada: El motor bloqueó cantidad = 0 en detalle (Error 23514).';
    END;

    IF NOT v_error_detectado THEN
        RAISE EXCEPTION 'Falla de Integridad: Se permitió cantidad = 0 en detalle_pedido.';
    END IF;

    -- Caso 2B: Cantidad superior al máximo permitido (cantidad = 101)
    v_error_detectado := FALSE;
    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, precio_unitario, cantidad)
        VALUES (v_pedido_id, v_producto_id, 3500.00, 101);
    EXCEPTION
        WHEN check_violation THEN
            v_error_detectado := TRUE;
            RAISE NOTICE '[OK] Regla 2B superada: El motor bloqueó cantidad = 101 en detalle (Error 23514).';
    END;

    IF NOT v_error_detectado THEN
        RAISE EXCEPTION 'Falla de Integridad: Se permitió cantidad = 101 en detalle_pedido.';
    END IF;

    -- Caso 2C: Inserción válida en el rango admitido (cantidad = 5)
    INSERT INTO detalle_pedido (pedido_id, producto_id, precio_unitario, cantidad)
    VALUES (v_pedido_id, v_producto_id, 3500.00, 5);
    RAISE NOTICE '[OK] Regla 2C superada: Inserción válida de detalle con cantidad = 5 aceptada.';

    -- ------------------------------------------------------------------------
    -- PRUEBA 3: Trigger para impedir la reactivación de un pedido dado de baja
    -- ------------------------------------------------------------------------
    -- Paso 3A: Marcar el pedido como eliminado (Baja lógica permitida)
    UPDATE pedido 
    SET eliminado = TRUE 
    WHERE id = v_pedido_id;
    RAISE NOTICE '[OK] Regla 3A superada: Baja lógica aplicada con éxito (eliminado = TRUE).';

    -- Paso 3B: Intentar revertir la baja lógica (Debe disparar excepción del trigger)
    v_error_detectado := FALSE;
    BEGIN
        UPDATE pedido 
        SET eliminado = FALSE 
        WHERE id = v_pedido_id;
    EXCEPTION
        WHEN restrict_violation THEN
            v_error_detectado := TRUE;
            RAISE NOTICE '[OK] Regla 3B superada: El trigger trg_impedir_reactivacion_pedido abortó la reactivación.';
    END;

    IF NOT v_error_detectado THEN
        RAISE EXCEPTION 'Falla de Integridad: El trigger permitió reactivar un pedido dado de baja.';
    END IF;

    RAISE NOTICE '============================================================';
    RAISE NOTICE 'TODAS LAS PRUEBAS DE RESTRICCIONES FINALIZARON EXITOSAMENTE';
    RAISE NOTICE '============================================================';

    -- Limpieza de registros temporales de la suite de pruebas
    DELETE FROM detalle_pedido WHERE pedido_id = v_pedido_id;
    DELETE FROM pedido WHERE id = v_pedido_id;
    DELETE FROM producto WHERE id = v_producto_id;
    DELETE FROM categoria WHERE id = v_categoria_id;
    DELETE FROM cliente WHERE id = v_cliente_id;
    RAISE NOTICE 'Registros de prueba limpiados exitosamente. El catálogo permanece validado.';
END $$;
