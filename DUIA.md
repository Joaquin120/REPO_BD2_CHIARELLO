# Declaración de Uso de Inteligencia Artificial (DUIA)

**Cátedra:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación a Distancia (UTN)  
**Trabajo Práctico:** N.º 1 — Del dominio al esquema: modelo ER, modelo relacional, normalización y DDL  
**Proyecto Integrador:** Food Store (Semana 1)  
**Estudiante:** Joaquin Chiarello  
**Repositorio:** REPO_BD2_CHIARELLO  
**Fecha:** Noviembre 2026  

---

## 1. Herramienta y Entorno
* **Entorno / Plataforma:** Antigravity CLI / Plugin Agystack (`poteto-mode`).
* **Modelo LLM:** Gemini 3.8 Flash (High).
* **Rol Asignado:** Administrador de Bases de Datos Senior (PostgreSQL 16+).

---

## 2. Spec o Prompt Utilizado
Texto exacto de la consigna provista como directiva de ingeniería:
> *"Actuá como Administrador de Bases de Datos senior para PostgreSQL 16+. En base al dominio de Food Store (gestión de pedidos de comida), realizá lo siguiente: 1. Analizá las reglas de negocio: Categoría (1:N) Producto, Cliente (1:N) Pedido, Pedido (N:M) Producto mediante DetallePedido. Baja lógica en tablas maestras (activo=true), precio/stock no negativos, email único en clientes, y congelamiento de precios históricos en el detalle. 2. Normalizá paso a paso hasta BCNF la planilla plana: (nro_pedido, fecha, cliente, producto, categoria, precio_unitario, cantidad, subtotal, forma_pago). Identificá la clave primaria, dependencias funcionales, descomposición de 1FN a 2FN (eliminando dependencias parciales), a 3FN (eliminando subtotal por dependencia transitiva) y verificación de BCNF. 3. Generá el script 'schema.sql' en PostgreSQL 16+: CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA'). Tablas: categoria, cliente, producto, pedido, detalle_pedido. Tipos de datos estrictos (BIGINT GENERATED ALWAYS AS IDENTITY, NUMERIC(12,2), TIMESTAMPTZ, BOOLEAN). Constraints: PRIMARY KEY compuesta en detalle_pedido (pedido_id, producto_id), UNIQUE en cliente.email y categoria.nombre, CHECK para precio >= 0 y stock >= 0, FOREIGN KEYs con ON DELETE RESTRICT (salvo detalle_pedido -> pedido en CASCADE). 3 índices comentados (idx_producto_categoria, idx_pedido_cliente, y un índice parcial en producto donde activo = TRUE). 4. Redactá las respuestas técnicas a las preguntas de integración y el archivo 'DUIA.md' registrando este proceso."*

---

## 3. Qué Generó la Inteligencia Artificial
* **Script DDL ejecutable (`schema.sql`):** Código completo de creación de tipos ENUM, 5 tablas relacionales normalizadas, restricciones declarativas (`PRIMARY KEY`, `FOREIGN KEY`, `CHECK`, `UNIQUE`, `DEFAULT`, `NOT NULL`) y 3 índices estratégicos comentados.
* **Desarrollo formal de Normalización:** Proceso matemático y relacional paso a paso desde la planilla universal plana hasta BCNF, detallando dependencias funcionales, eliminación de dependencias parciales (2FN) y eliminación de la dependencia transitiva del atributo derivado `subtotal` (3FN / BCNF).
* **Respuestas de Integración y Reflexión:** Fundamentación técnica sobre la discrepancia entre el modelado conceptual top-down (ER) y la normalización bottom-up sobre datos planos históricos, junto con el análisis de persistencia vs. cómputo al vuelo de atributos calculados.
* **Suite de Pruebas de Integridad (`test_suite.sql`):** Batería de pruebas en bloque transaccional con casos positivos y casos de prueba negativos diseñados para verificar que las restricciones del motor rechacen datos corruptos.

---

## 4. Qué se Aceptó sin Modificaciones
* **Estándar de Identificadores SQL:2003:** Uso de `BIGINT GENERATED ALWAYS AS IDENTITY` como clave primaria en todas las entidades independientes, descartando el pseudo-tipo no estándar `SERIAL`.
* **Precisión Monetaria:** Adopción de `NUMERIC(12,2)` para precios unitarios y de lista, erradicando discrepancias de redondeo inherentes a tipos de coma flotante (`FLOAT` / `REAL`).
* **Precisión Temporal y Zonas Horarias:** Uso de `TIMESTAMPTZ` con `clock_timestamp()` para capturar el instante real de registro transaccional con huso horario explícito.
* **Tipo ENUM estricto:** `CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA')` garantizando dominio cerrado en la base de datos sin depender exclusivamente de validaciones en la capa de aplicación.
* **Políticas Referenciales Diferenciadas:** Asignación de `ON DELETE CASCADE` exclusivamente en `detalle_pedido -> pedido` (entidad débil por identificación/composición) y `ON DELETE RESTRICT` en las relaciones con `producto`, `cliente` y `categoria`.

---

## 5. Qué se Modificó o Descartó, y por qué
1. **Descarte de la columna física `subtotal`:**
   * *Razón:* Almacenar `subtotal` introduce una dependencia transitiva `{nro_pedido, producto} → (cantidad, precio_unitario) → subtotal`, violando 3FN y BCNF. Genera riesgo de anomalías de modificación (inconsistencias entre los factores y el producto). Se resolvió calcularlo al vuelo en consultas y vistas (`cantidad * precio_unitario`).
2. **Atomización del atributo `cliente` en `nombre` y `apellido`:**
   * *Razón:* En la planilla plana original figuraba `cliente` como un único campo de texto (ej. "Ana Gómez"). Para respetar la 1FN (dominios atómicos) y permitir ordenamientos alfabéticos y búsquedas eficientes por apellido en PostgreSQL, se descompuso en `nombre VARCHAR(100)` y `apellido VARCHAR(100)`.
3. **Mecanismo de Congelamiento de Precios en el Detalle:**
   * *Razón:* Se analizó si `precio_unitario` en `detalle_pedido` era redundante con `producto.precio`. Se determinó que NO lo es: el precio del catálogo es mutable en el tiempo, mientras que el precio del detalle representa el precio histórico concertado al momento de la venta. Su presencia en la tabla intermedia es mandataria por regla de negocio y no viola ninguna forma normal.
4. **Preservación de registros mediante Baja Lógica (`activo`):**
   * *Razón:* Ante la regla de negocio que prohíbe eliminar físicamente productos y categorías para no romper el historial de pedidos, se descartó el borrado físico (`DELETE`) en favor de `activo BOOLEAN NOT NULL DEFAULT TRUE`, complementado con un índice parcial para mantener el rendimiento de consulta sobre ítems activos.

---

## 6. Verificación Realizada y Resultados

Se implementó y ejecutó una batería de pruebas de integridad referencial y de dominio sobre un entorno PostgreSQL 16:

### A. Casos de Inserción Válidos (Happy Path)
1. Inserción de categoría `'Pizzas'`: Exitosa.
2. Inserción de cliente `'Ana'`, `'Gómez'`, `'ana.gomez@email.com'`: Exitosa.
3. Inserción de producto `'Muzzarella'`, precio `1000.00`, stock `50`, vinculada a categoría `'Pizzas'`: Exitosa.
4. Inserción de pedido para el cliente con medio de pago `'EFECTIVO'`: Exitosa.
5. Inserción de línea de detalle con `precio_unitario = 1000.00` y `cantidad = 2`: Exitosa.
6. Consulta de comprobación con cálculo dinámico: Subtotal verificado exactamente en `$2000.00`.

### B. Batería de Casos Negativos (Rechazos de Motor Esperados)
| Operación Intentada | Restricción Evaluada | Resultado en PostgreSQL | Código de Error |
| :--- | :--- | :--- | :--- |
| `INSERT INTO producto` con `precio = -100` | `CHECK chk_producto_precio` | **RECHAZADO** (check constraint violation) | `23514` |
| `INSERT INTO producto` con `stock = -5` | `CHECK chk_producto_stock` | **RECHAZADO** (check constraint violation) | `23514` |
| `INSERT INTO detalle_pedido` con `cantidad = 0` | `CHECK chk_detalle_cantidad` | **RECHAZADO** (check constraint violation) | `23514` |
| `INSERT INTO cliente` con email ya existente | `UNIQUE (email)` | **RECHAZADO** (unique constraint violation) | `23505` |
| `INSERT INTO categoria` con nombre repetido | `UNIQUE (nombre)` | **RECHAZADO** (unique constraint violation) | `23505` |
| `INSERT INTO pedido` con `forma_pago = 'BITCOIN'` | `ENUM forma_pago_enum` | **RECHAZADO** (invalid input value for enum) | `22P02` |
| `DELETE FROM producto` referenciado en detalle | `FK ON DELETE RESTRICT` | **RECHAZADO** (foreign key violation) | `23503` |
| `DELETE FROM cliente` con pedidos registrados | `FK ON DELETE RESTRICT` | **RECHAZADO** (foreign key violation) | `23503` |

### C. Prueba de Cascada Operacional
* Al ejecutar `DELETE FROM pedido WHERE id = 1`, todas las filas correspondientes en `detalle_pedido` fueron eliminadas de manera automática y atómica gracias a la regla `ON DELETE CASCADE`, sin dejar registros huérfanos.
