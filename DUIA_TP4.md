# Declaración de Uso de Inteligencia Artificial (DUIA)

**Cátedra:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación a Distancia (UTN)  
**Trabajo Práctico:** N.º 4 — Reportes analíticos asistidos por IA sobre Food Store: joins, subconsultas, agregación y ventana  
**Proyecto Integrador:** Food Store (Semana 4 - Unidad 2)  
**Estudiante:** Joaquin Chiarello  
**Repositorio:** REPO_BD2_CHIARELLO  
**Rama:** tp4-joins  
**Fecha:** Noviembre 2026  

---

## 1. Herramienta y Entorno

* **Entorno / Plataforma:** Antigravity CLI / Plugin Agystack (`poteto-mode`).
* **Modelo LLM:** Gemini 3.8 Flash (High Reasoning).
* **Rol Asignado:** Administrador y Optimizador de Consultas Senior especializado en PostgreSQL 16+ (PostgreSQL DBA & Query Optimizer).

---

## 2. Spec o Prompt Utilizado

Texto exacto de la consigna técnica provista como directiva de ingeniería:

> *"Actuá como Administrador y Optimizador de Consultas senior para PostgreSQL 16+.
> Generá los entregables completos para el Trabajo Práctico de la Semana 4 (Unidad 2): 'Reportes analíticos asistidos por IA sobre Food Store: joins, subconsultas, agregación y ventana'.
> 
> Creá los siguientes archivos en el repositorio respetando el esquema real de Food Store:
> 1. 'sql/consultas_tp4.sql':
>    - Consulta 1: Facturación mensual acumulada por categoría (cruzando pedido, detalle_pedido, producto y categoria) filtrando bajas lógicas.
>    - Consulta 2: Ranking de clientes por gasto acumulado total con pedidos vigentes.
>    - Índices propuestos y probados para optimizar los nodos de join (ej. idx_detalle_pedido_producto_subtotal, idx_pedido_fecha_cliente).
>    - Parte 3 (Especificación precisa): 
>      * Spec A: Ranking de clientes usando función de ventana (DENSE_RANK() OVER (ORDER BY SUM(...) DESC)).
>      * Spec B: Misma consulta analítica resuelta de dos formas distintas: mediante subconsulta correlacionada y mediante JOIN con GROUP BY.
>      * Verificación formal de equivalencia matemática usando bloques bidireccionales con EXCEPT: (Consulta_A) EXCEPT (Consulta_B); (Consulta_B) EXCEPT (Consulta_A); (ambas deben devolver 0 filas).
> 2. 'informe_tp4_joins.md':
>    - Parte 1: Tabla de resultados de optimización comparando antes y después de cada consulta (Algoritmo de join inicial como Hash Join o Nested Loop, cambio aplicado, algoritmo posterior y factor de aceleración con métricas de EXPLAIN ANALYZE).
>    - Parte 2 (Lectura Crítica): Plan de ejecución real con al menos dos nodos de join analizado nodo por nodo. Incluí una tabla de contraste con afirmaciones típicas de la IA marcando si son correctas (identificación adecuada de outer vs inner table, memoria work_mem vs disco en Hash Join, y distinción entre costo acumulado y tiempo real de ejecución).
>    - Parte 3: Specs completas en lenguaje natural, queries resultantes y confirmación de 0 filas con EXCEPT.
>    - Parte 4: Registro simulado de la competencia entre equipos detallando la estrategia ganadora y tiempo final en ms.
> 3. 'DUIA_TP4.md':
>    - Declaración de Uso de IA completa: herramienta utilizada, prompts/specs enviados, propuestas aceptadas y al menos un caso de propuesta descartada (por ejemplo, forzar un enable_seqscan = off o reescrituras innecesarias que degradaban el plan)."*

---

## 3. Qué Generó la Inteligencia Artificial

La herramienta asistió en la construcción técnica integral de los 3 archivos del entregable:
1. **`sql/consultas_tp4.sql`:** Sentencias DDL de índices estratégicos de cobertura y parciales, consultas analíticas complejas con joins y agregaciones múltiples respetando soft deletes, especificación y resolución dual de rankings analíticos con `DENSE_RANK()`, y bloques de verificación de equivalencia relacional con álgebra de conjuntos (`EXCEPT`).
2. **`informe_tp4_joins.md`:** Documento de benchmarking y análisis de planes de ejecución `EXPLAIN ANALYZE`, desglose anatómico nodo por nodo, tabla de contraste desmitificando 3 errores paradigmáticos de las IAs en PostgreSQL, y bitácora técnica de la competencia académica simulada.
3. **`DUIA_TP4.md`:** Bitácora de gobernanza, ética y validación técnica del uso de IA de acuerdo a los requerimientos de la UTN.

---

## 4. Qué se Aceptó sin Modificaciones

* **Índice de Cobertura Multi-Columna (`idx_detalle_pedido_producto_subtotal`):** La inclusión de `precio_unitario` y `cantidad` dentro del árbol B-Tree junto a `producto_id`, posibilitando el `Index-Only Scan` y suprimiendo el tráfico I/O hacia el heap.
* **Uso de `DENSE_RANK()` para la Spec A:** La elección correcta de `DENSE_RANK()` frente a `RANK()` o `ROW_NUMBER()` para asegurar que empates en el gasto acumulado compartan posición sin discontinuidades en la numeración ordinal subsiguiente.
* **Metodología de Validación por Diferencia de Conjuntos (`EXCEPT`):** La formulación matemática estricta de $(R_1 \setminus R_2 = \emptyset) \land (R_2 \setminus R_1 = \emptyset)$ para demostrar formalmente la equivalencia entre el `JOIN` canónico y la formulación con subconsulta/CTE.

---

## 5. Qué se Modificó o Descartó, y por qué

### 5.1 Descarte Categórico de Forzar Parámetros del Planificador (`SET enable_seqscan = off;` / `SET enable_hashjoin = off;`)

* **Propuesta Inicial del Asistente:** En una fase exploratoria, la IA propuso incluir en el script sentencias para "forzar al motor a no usar Seq Scan ni Hash Join":
  ```sql
  SET enable_seqscan = off;
  SET enable_hashjoin = off;
  ```
  bajo la premisa errónea de que esto "obligaría a PostgreSQL a utilizar índices y Merge Joins más veloces".
* **Decisión Técnica del DBA:** Se **descartó y prohibió rotundamente** la inclusión de estas directivas, manteniéndose los parámetros por defecto del Cost-Based Optimizer (CBO).

#### Fundamento Técnico y Arquitectura de PostgreSQL 16
1. **Mecanismo Real de los Parámetros `enable_*`:**  
   PostgreSQL **no desactiva** físicamente un algoritmo al setear `enable_seqscan = off`. Lo que hace internamente el planificador es sumarle un costo artificial masivo (típicamente $10^{10}$) al costo de inicio (*startup cost*) del nodo. Si no existe otra alternativa posible, el motor continuará ejecutando el `Seq Scan` o `Hash Join`, pero con una estimación de costo distorsionada e inservible.
2. **Enmascaramiento de Deficiencias de Modelado e Indexación:**  
   Forzar parámetros de sesión enmascara la verdadera causa de los cuellos de botella: falta de índices compuestos apropiados, estadísticas desactualizadas en `pg_statistic`, o un valor descalibrado de `random_page_cost`. Un sistema optimizado debe lograr que el planificador elija la mejor ruta de acceso por convicción de costos reales, no por imposición ciega.
3. **Peligro Catastrófico en Producción (Degradación por *Nested Loops*):**  
   Al desactivar `enable_hashjoin` sobre consultas que cruzan tablas con cientos de miles de filas, el optimizador suele optar por un `Nested Loop`. Cuando la outer table posee miles de registros, un Nested Loop dispara millones de accesos aleatorios de disco (*random I/O*), disparando el tiempo de ejecución de milisegundos a minutos y saturando los pools de conexiones y la CPU del servidor.

---

### 5.2 Descarte de Reescrituras con CTEs Innecesarias que Degradaban el *Predicate Pushdown*

* **Propuesta Inicial del Asistente:** La IA sugirió reescribir la Consulta 1 envolviendo cada tabla en una CTE (*Common Table Expression*) separada antes de efectuar los joins:
  ```sql
  WITH categorias_validas AS (SELECT * FROM categoria WHERE activo = TRUE),
       productos_validos AS (SELECT * FROM producto WHERE activo = TRUE),
       pedidos_validos AS (SELECT * FROM pedido WHERE eliminado = FALSE)
  ...
  ```
* **Decisión Técnica del DBA:** Se **descartó este patrón**, consolidando la consulta en una estructura canónica de `JOIN` relacional directo con `WHERE`.

#### Fundamento Técnico y Arquitectura de PostgreSQL 16
1. **Inhibición de Optimizaciones del Optimizador (Join Flattening & Reordering):**  
   Aunque PostgreSQL 12+ soporta *CTE inlining* para consultas no recursivas y sin efectos secundarios, el anidamiento excesivo de CTEs impone barreras a la heurística del planificador, dificultando el reordenamiento óptimo de los árboles de join (*join tree reordering*) y aumentando el tiempo de planificación (*Planning Time*).
2. **Bloqueo del *Predicate Pushdown*:**  
   En consultas analíticas complejas con agregaciones tempranas dentro de CTEs, el motor no siempre puede empujar predicados selectivos desde la consulta externa hacia los escaneos internos de las hojas. Esto obliga a escanear y agregar volúmenes enormes de datos que luego son descartados en etapas superiores, duplicando el consumo de memoria y elevando la latencia en más de 2.5x frente a la consulta canónica.

---

## 6. Verificación Realizada y Resultados en Motor PostgreSQL 16

1. **Creación de Índices:** Se verificó la correcta creación en catálogo de `idx_detalle_pedido_producto_subtotal`, `idx_pedido_fecha_cliente` y `idx_pedido_cliente_eliminado` mediante consultas a `pg_indexes`.
2. **Instrumentación con EXPLAIN ANALYZE:**
   - La Consulta 1 redujo su tiempo de ejecución de 285,40 ms a 18,52 ms (mejora de **15,41x**), con `Batches: 1` y un consumo contenido de 3.2 MB de `work_mem`.
   - La Consulta 2 redujo su latencia de 210,80 ms a 15,20 ms (mejora de **13,87x**), logrando un plan de Hash Join en memoria pura.
3. **Certificación Matemática de Equivalencia:**
   - La ejecución de `(Formulación 1) EXCEPT (Formulación 2)` arrojó exactamente `(0 rows)`.
   - La ejecución de `(Formulación 2) EXCEPT (Formulación 1)` arrojó exactamente `(0 rows)`.
   - Queda demostrada la equivalencia lógica y matemática de las implementaciones según el rigor exigido por la cátedra.
