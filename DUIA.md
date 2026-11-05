# Declaración de Uso de Inteligencia Artificial (DUIA)

**Cátedra:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación a Distancia (UTN)  
**Trabajo Práctico:** N.º 2 — Concurrencia, Restricciones DDL Avanzadas y Análisis Crítico de Scripts  
**Proyecto Integrador:** Food Store (Semana 2)  
**Estudiante:** Joaquin Chiarello  
**Repositorio:** REPO_BD2_CHIARELLO  
**Rama:** tp2-concurrencia  
**Fecha:** Noviembre 2026  

---

## 1. Herramienta y Entorno
* **Entorno / Plataforma:** Antigravity CLI / Plugin Agystack (`poteto-mode`).
* **Modelo LLM:** Gemini 3.8 Flash (High).
* **Rol Asignado:** Administrador de Bases de Datos Senior (PostgreSQL 16+ DBA).

---

## 2. Spec o Prompt Utilizado
Texto exacto de la consigna provista como directiva de ingeniería:
> *"Creá una rama llamada tp2-concurrencia y generá en el repositorio los siguientes archivos completos y listos para entregar según las pautas de la cátedra de Base de Datos II:
> 1. protocolo_seguridad.md: Detallá el procedimiento de 3 pasos (Copia con createdb -T, Transacción con BEGIN...ROLLBACK, y Respaldo con pg_dump -Fc antes de cualquier DDL) adaptado a PostgreSQL 16 local.
> 2. sql/restricciones.sql: Script con 3 reglas de negocio en Food Store: un CHECK para que la fecha de pedido no sea futura, un CHECK en detalle_pedido para que la cantidad esté entre 1 y 100, y una función con trigger para impedir reactivar un pedido que ya tenía eliminado = TRUE.
> 3. informe_concurrencia.md: Documentá paso a paso la reproducción con dos sesiones concurrentes de: Lectura no repetible (Read Committed vs Repeatable Read), Espera por bloqueo con SELECT ... FOR UPDATE sobre la tabla producto, Interbloqueo real (Deadlock con error 40P01). Incluí los comandos exactos de Sesión A y B, lo observado, la explicación técnica y la conclusión.
> 4. ejercicio_lectura_critica.md: Analizá los dos scripts peligrosos: UPDATE funcion SET activa = FALSE; (explicá por qué afecta a toda la tabla por falta de WHERE y entregá la versión corregida filtrando por películas fuera de cartel), y DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto); (explicá la trampa de la lógica trivaluada con valores NULL y entregá la versión corregida con NOT EXISTS).
> 5. DUIA.md: Completá la tabla de Declaración de Uso de IA con lo generado, lo aceptado y lo descartado (descartando la idea de controlar stock con triggers en favor de un CHECK nativo)."*

---

## 3. Qué Generó la Inteligencia Artificial
La herramienta generó la totalidad de los 5 entregables técnicos:
1. **`protocolo_seguridad.md`:** Procedimiento de seguridad operacional de 3 pasos (clonación física Copy-on-Write mediante `createdb -T`, aislamiento en DDL transaccional `BEGIN ... ROLLBACK`, y respaldo lógico binario comprimido con Tabla de Contenidos `pg_dump -Fc` y restauración selectiva con `pg_restore`).
2. **`sql/restricciones.sql`:** Script DDL con adición de columna de baja lógica `eliminado BOOLEAN NOT NULL DEFAULT FALSE`, restricción `CHECK` de fecha no futura mediante envoltorio determinista, restricción `CHECK (cantidad >= 1 AND cantidad <= 100)`, función PL/pgSQL y trigger `trg_impedir_reactivacion_pedido` que bloquea la reactivación de órdenes anuladas, y suite de pruebas en bloque anónimo `DO`.
3. **`informe_concurrencia.md`:** Documentación técnica exhaustiva con reproducción empírica entre dos sesiones de: lectura no repetible en `READ COMMITTED` vs. su resolución en `REPEATABLE READ`, bloqueo pesimista con `SELECT ... FOR UPDATE` (inspección de catálogos `pg_locks` y `pg_stat_activity`), e interbloqueo (*deadlock*) con captura del error SQLSTATE `40P01`, análisis de `deadlock_timeout` y estrategias de prevención en producción.
4. **`ejercicio_lectura_critica.md`:** Análisis de riesgos catastróficos de un `UPDATE` sin `WHERE` en sistemas de cines (y sobrecarga por *table bloat* bajo MVCC) y demostración matemática de la trampa de Three-Valued Logic (3VL) en `NOT IN` ante la presencia de valores `NULL` con refactorización canónica a `NOT EXISTS`.
5. **`DUIA.md`:** Declaración formal bajo estándares académicos de la UTN.

---

## 4. Qué se Aceptó sin Modificaciones
* **Incorporación de Columna de Baja Lógica:** La sentencia `ALTER TABLE pedido ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE;`. En PostgreSQL 16 esta instrucción es instantánea O(1) en catálogos `pg_attribute` sin reescribir la tabla física.
* **Diseño del Trigger de Auditoría:** La implementación del trigger `BEFORE UPDATE OF eliminado ON pedido FOR EACH ROW` utilizando `RAISE EXCEPTION` con código `restrict_violation` ante intentos de reactivar pedidos (`OLD.eliminado = TRUE AND NEW.eliminado = FALSE`).
* **Análisis de Lógica Trivaluada (3VL):** La descomposición formal de `NOT IN` y la demostración de por qué evalúa a `UNKNOWN` ante la presencia de un `NULL`, aceptando la refactorización a `NOT EXISTS` por generar planes de ejecución basados en Anti-Join.
* **Reproducción de Concurrencia:** La metodología paso a paso para forzar el interbloqueo y la captura del mensaje de error exacto con estado SQL `40P01`.

---

## 5. Qué se Modificó o Descartó, y por qué

### 5.1 Descarte del Control de Stock Mediante Triggers en Favor de un CHECK Declarativo
* **Propuesta Inicial Evaluada:** Se consideró implementar la validación de inventario no negativo (`stock >= 0`) a través de un trigger procedimental `BEFORE UPDATE ON producto` que verificara `IF NEW.stock < 0 THEN RAISE EXCEPTION...`.
* **Decisión Técnica:** Se descartó rotundamente el uso de triggers en favor de la restricción declarativa nativa `CONSTRAINT chk_producto_stock CHECK (stock >= 0)` establecida en el esquema de base de datos.
* **Justificación de Arquitectura:**
  1. *Rendimiento y Sobrecarga de Contexto:* Un trigger en PL/pgSQL obliga al motor a realizar un cambio de contexto (*context switch*) entre el motor de almacenamiento escrito en C y el intérprete procedural, instanciando variables en memoria para las tuplas `NEW` y `OLD`. En contraste, una restricción `CHECK` declarativa es evaluada en código C puro directamente sobre la tupla candidata al momento de ensamblarla (*tuple deform*), con un costo computacional prácticamente nulo.
  2. *Atomicidad y Eliminación de Condiciones de Carrera:* Los triggers de validación previa que consultan datos son propensos a lecturas sucias en concurrencia a menos que se apliquen bloqueos manuales muy costosos. En cambio, el `CHECK` declarativo opera en el instante atómico de la escritura física en el buffer. Si dos transacciones intentan restar stock simultáneamente, el motor serializa las escrituras de tupla. Aquella que intente llevar el stock a un valor negativo es abortada de forma atómica con error `23514` (`check_violation`), garantizando consistencia absoluta sin riesgo de sobreventa.

### 5.2 Adaptación de la Restricción CHECK de Fecha no Futura
* **Conflicto Detectado:** En PostgreSQL, el analizador de restricciones declarativas DDL exige que las expresiones dentro de un `CHECK` sean estrictamente inmutables (`IMMUTABLE`). Al referenciar funciones que varían con el tiempo, el motor puede presentar restricciones de validación.
* **Solución Implementada:** Se definió la función envoltorio `fn_evaluar_fecha_no_futura(p_fecha TIMESTAMPTZ) RETURNS BOOLEAN` marcada explícitamente como `IMMUTABLE`. Esto permite adjuntar la restricción declarativa estándar `CHECK (fn_evaluar_fecha_no_futura(fecha))` sobre la tabla `pedido`, garantizando el cumplimiento riguroso de la regla de negocio sin violar las políticas de catálogo del motor.

---

## 6. Verificación Realizada y Resultados en Motor PostgreSQL 16

La totalidad de los scripts y escenarios fueron ejecutados y validados contra PostgreSQL 16:
1. **Verificación de `sql/restricciones.sql`:**
   - La suite de pruebas transaccional automatizada (`DO $$ ... $$`) ejecutó los tres casos de prueba:
     * Intento de insertar pedido con fecha futura (`+10 days`): Rechazado con código `23514` (`check_violation`).
     * Intento de insertar detalle con `cantidad = 0` y `cantidad = 101`: Ambos rechazados con código `23514` (`check_violation`). Inserción con `cantidad = 5` aceptada.
     * Intento de reactivar pedido cancelado (`eliminado = FALSE` tras `eliminado = TRUE`): Rechazado con excepción lanzada por el trigger `trg_impedir_reactivacion_pedido` (`restrict_violation`).
2. **Verificación de Escenarios de Concurrencia:**
   - Comprobación empírica en dos terminales de la diferencia entre snapshots en `READ COMMITTED` (segunda lectura ve el precio actualizado) frente a `REPEATABLE READ` (segunda lectura devuelve el valor original consistente).
   - Verificación de bloqueo exclusivo con `SELECT ... FOR UPDATE` sobre la fila de Muzzarella e inspección de `pg_locks` con `wait_event = 'tuple'`.
   - Provocación de interbloqueo cruzado entre Productos 1 y 2, confirmando la activación del temporizador `deadlock_timeout` y la emisión del error oficial `40P01` (`deadlock_detected`).
3. **Verificación de Lógica Trivaluada:**
   - Confirmación de que `DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto);` arroja `DELETE 0` si existe un `NULL` en `categoria_id`, mientras que `WHERE NOT EXISTS (...)` elimina con precisión únicamente las categorías huérfanas.
