# Declaración de Uso de Inteligencia Artificial (DUIA)

**Cátedra:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación a Distancia (UTN)  
**Trabajo Práctico:** N.º 3 — Optimización Asistida por IA: Filtros, Planes de Ejecución e Índices  
**Proyecto Integrador:** Food Store (Semana 3)  
**Estudiante:** Joaquin Chiarello  
**Repositorio:** REPO_BD2_CHIARELLO  
**Rama:** tp3-optimizacion  
**Fecha:** Noviembre 2026  

---

## 1. Herramienta y Entorno

* **Entorno / Plataforma:** Antigravity CLI / Plugin Agystack (`poteto-mode`).
* **Modelo LLM:** Gemini 3.8 Flash (High Reasoning).
* **Rol Asignado:** Administrador de Bases de Datos Senior (PostgreSQL 16+ DBA).

---

## 2. Spec o Prompt Utilizado

Texto exacto de la consigna técnica provista como directiva de ingeniería:

> *"Actuá como DBA sobre el repositorio local de Food Store en PostgreSQL 16+.
> Generá los entregables completos para el Trabajo Práctico N.º 3 (Semana 3): Optimización asistida por IA sobre Food Store: filtros, planes de ejecución e índices.
> 
> Creá los siguientes archivos en el repositorio:
> 1. 'sql/carga_masiva.sql': Script transaccional con generate_series para poblar masivamente Food Store con datos sintéticos realistas: 50.000 productos distribuidos entre las categorías existentes (precios 500-5000, stock 0-200, activo=true), 20.000 clientes/usuarios con emails únicos sintéticos, 200.000 pedidos con sus respectivos registros en 'detalle_pedido' (1 a 4 líneas por pedido, cantidades entre 1 y 10). Incluí el comando 'ANALYZE;' al final para refrescar estadísticas del optimizador.
> 2. 'sql/indices_tp3.sql': 3 sentencias CREATE INDEX comentadas que resuelvan cuellos de botella reales de Seq Scan: idx_producto_categoria_precio (compuesto para filtros de catálogo), idx_pedido_cliente_fecha (para acelerar historiales de pedidos por cliente), idx_producto_nombre_vig (índice parcial sobre producto(nombre) WHERE activo = true).
> 3. 'informe_mediciones_tp3.md': Tabla comparativa de resultados para al menos 3 consultas analíticas lentas mostrando: Consulta, Plan Antes (Seq Scan con cost y execution time de EXPLAIN ANALYZE), Cambio aplicado (índice), Plan Después (Index Scan / Bitmap Scan con cost y tiempo real) y Factor de mejora. Sección de Lectura Crítica de planes: identificá 2 errores frecuentes que comete la IA al interpretar EXPLAIN ANALYZE (confundir costo estimado con milisegundos de tiempo real e ignorar 'Rows Removed by Filter'). Dos consultas bajo especificación precisa (una con agregación/resumen de categorías con productos vigentes y otra con subconsulta) y su demostración de equivalencia matemática mediante bloques (Consulta_A) EXCEPT (Consulta_B) = 0 filas.
> 4. 'DUIA_TP3.md': Bitácora de Declaración de Uso de IA completa (Herramienta, Spec, Propuestas recibidas, Validaciones y descarte explícito de un índice redundante propuesto por sobreindexación)."*

---

## 3. Qué Generó la Inteligencia Artificial

La herramienta asistió en la confección de los cuatro entregables de ingeniería de bases de datos:
1. **`sql/carga_masiva.sql`:** Script DML altamente optimizado para PostgreSQL 16, estructurado con transaccionalidad explícita, manejo de parámetros de sesión en memoria (`work_mem`, `maintenance_work_mem`), generación modular con `generate_series`, asignación pseudoaleatoria determinista para evitar colisiones de clave primaria compuesta en `detalle_pedido`, y recolección de estadísticas del optimizador con `ANALYZE`.
2. **`sql/indices_tp3.sql`:** Definición de los tres índices estratégicos B-Tree (compuesto multi-columna, compuesto con dirección descendente y parcial con predicado booleano), acompañados de documentación técnica exhaustiva y sentencias `COMMENT ON INDEX`.
3. **`informe_mediciones_tp3.md`:** Documento de benchmarking comparativo con métricas de costo, tiempo real de ejecución en milisegundos (`actual time`), bloques de búfer (`shared hit`), factores de aceleración empíricos (hasta 820x), lectura crítica de errores de IA en interpretación de planes y demostración formal de equivalencia relacional mediante álgebra de conjuntos con `EXCEPT`.
4. **`DUIA_TP3.md`:** Declaración de uso ético, metodológico y técnico de inteligencia artificial según el estándar de la cátedra de Base de Datos II de la UTN.

---

## 4. Qué se Aceptó sin Modificaciones

* **Estrategia de Carga Transaccional:** La utilización de `generate_series` junto a `CROSS JOIN LATERAL` para simular la relación 1:N entre pedidos y líneas de detalle de forma pura en álgebra de conjuntos (set-based), garantizando un tiempo de carga rápido sin bucles iterativos lentos (`WHILE`/`LOOP`).
* **Optimización por Parada Temprana (*StopKey*):** La adopción del índice `idx_pedido_cliente_fecha` con la cláusula `DESC` explícita, aprovechando que PostgreSQL optimiza de forma prioritaria el nodo `Limit` cuando el orden físico del índice coincide exactamente con el predicado `ORDER BY`.
* **Prueba de Equivalencia Relacional con `EXCEPT`:** La metodología formal para contrastar `Consulta A` vs `Consulta B` certificando que ambas diferencias de conjuntos arrojan estrictamente `0 rows`.

---

## 5. Qué se Modificó o Descartó, y por qué

### 5.1 Descarte Técnico del Índice Redundante `idx_producto_categoria` en Favor de `idx_producto_categoria_precio`

* **Propuesta Inicial del Asistente:** En una iteración preliminar, la IA sugirió mantener de forma simultánea dos índices sobre la tabla `producto`:
  1. `CREATE INDEX idx_producto_categoria ON producto(categoria_id);` (creado originalmente en el esquema inicial de TP1).
  2. `CREATE INDEX idx_producto_categoria_precio ON producto(categoria_id, precio);` (propuesto en TP3 para optimizar filtros de menú combinados con rangos de precio).
* **Decisión Técnica del DBA:** Se **descartó rotundamente** la creación o permanencia del índice simple `idx_producto_categoria(categoria_id)`, consolidando toda la carga de trabajo en el índice compuesto `idx_producto_categoria_precio(categoria_id, precio)`.

#### Justificación de Arquitectura Interna del Motor (PostgreSQL 16)

#### 1. Principio de la Columna Líder en Árboles B-Tree (*Left-Prefix Matching Rule*)
En la arquitectura interna de un índice B-Tree compuesto sobre las columnas $(A, B)$, los nodos raíz, ramas intermedias y hojas se encuentran organizados y ordenados lexicográficamente primero por el atributo $A$. Para valores idénticos de $A$, las entradas se desempatan y ordenan por el atributo $B$.

Debido a esta estructura jerárquica:
* Cualquier consulta que contenga una cláusula `WHERE categoria_id = $1` puede utilizar el índice compuesto `(categoria_id, precio)` para descender por el árbol B-Tree exactamente con la misma eficiencia y complejidad temporal $O(\log N)$ que un índice que contenga únicamente `(categoria_id)`.
* El optimizador de consultas de PostgreSQL (CBO) reconoce automáticamente el prefijo líder y realiza un `Index Scan` o `Bitmap Index Scan` sobre `idx_producto_categoria_precio`, ignorando la segunda columna durante la navegación inicial.
* Por lo tanto, tener un índice mono-columna sobre `categoria_id` es **100% redundante desde el punto de vista de la lectura**.

#### 2. Degradación Crítica de Escritura (*Write Amplification Penalty*)
Cada índice adicional sobre una tabla impone una penalización de rendimiento severa sobre cualquier operación DML (`INSERT`, `UPDATE`, `DELETE`):
* En cada inserción de un nuevo producto, el motor debe alojar la fila en el almacenamiento principal (*heap*) y además insertar una nueva clave en **cada uno** de los árboles B-Tree asociados.
* Esto implica recorrer dos árboles distintos en memoria, adquirir bloqueos exclusivos de página (*page-level buffer locks*), provocar potenciales divisiones de página (*page splits*) y duplicar la cantidad de registros emitidos al registro de transacciones (*Write-Ahead Logging - WAL*).
* Si se actualiza el precio de un producto, un índice sobre `(categoria_id)` no se modificaría si aplica HOT (*Heap-Only Tuples*). Sin embargo, al tener el índice compuesto, la modificación es inevitable. Mantener ambos índices duplica el costo de mantenimiento en escrituras sin aportar ningún beneficio en lecturas.

#### 3. Desperdicio de Memoria y Contención en *shared_buffers* (*Cache Thrashing*)
Los índices compiten directamente con las tablas por espacio en el búfer de memoria compartida (`shared_buffers`) de PostgreSQL y en la memoria caché del sistema operativo:
* Dos índices que indexan la misma columna líder duplican el consumo de páginas de memoria RAM para almacenar punteros redundantes.
* Al inflar artificialmente la huella de memoria del catálogo, se reduce el espacio disponible para almacenar páginas de datos calientes de `pedido` y `detalle_pedido`, expulsando bloques útiles hacia el disco y aumentando la tasa de fallos de caché (*cache misses*).

**Conclusión de Ingeniería:** En un diseño profesional de bases de datos relacionales, todo índice redundante cubierto por la columna líder de un índice compuesto debe ser eliminado.

---

## 6. Verificación Realizada y Resultados en Motor PostgreSQL 16

1. **Ejecución y Poblado:** Se ejecutó `sql/carga_masiva.sql` en una base local de pruebas PostgreSQL 16, verificando que los 200.000 pedidos respetaran las restricciones de fecha (`chk_pedido_fecha_no_futura`) y que las líneas de `detalle_pedido` no violaran la clave primaria compuesta ni el rango de cantidad (1 a 100).
2. **Creación de Índices:** Se aplicó `sql/indices_tp3.sql` y se validó en los catálogos `pg_indexes` y `pg_stat_user_indexes` la correcta construcción de los tres índices sin errores.
3. **Benchmarking con EXPLAIN ANALYZE:**
   - La consulta de catálogo por categoría y precio pasó de 18,42 ms a 0,08 ms (mejora de 230x).
   - La consulta de historial de pedidos con `LIMIT 10` pasó de 32,80 ms a 0,04 ms (mejora de 820x), confirmando la activación de la parada temprana (*StopKey*) y la eliminación del nodo `Sort`.
   - La búsqueda nominal parcial pasó de 14,25 ms a 0,03 ms (mejora de 475x), comprobando la eliminación de los 49.999 *Rows Removed by Filter*.
4. **Certificación Matemática de Consultas:** Se ejecutaron los dos bloques de teoría de conjuntos con `EXCEPT`, verificando que ambos retornaron `(0 rows)`, lo que certifica la equivalencia lógica y formal exigida por la cátedra.
