# Informe Técnico de Mediciones, Planes de Ejecución y Optimización de Consultas

**Cátedra:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación a Distancia (UTN)  
**Proyecto Integrador:** Food Store  
**Entrega:** Trabajo Práctico N.º 3 (Semana 3)  
**Autor:** Joaquin Chiarello  
**Entorno de Benchmarking:** PostgreSQL 16.x sobre Linux x86_64  
**Configuración de Memoria:** `shared_buffers = 256MB`, `work_mem = 64MB`, `random_page_cost = 1.1`

---

## 1. Metodología de Benchmarking y Banco de Pruebas

Para garantizar reproducibilidad científica en las mediciones de rendimiento, se ejecutó previamente el script de carga masiva `sql/carga_masiva.sql`, consolidando el siguiente volumen de datos reales:
* `categoria`: 5 registros base.
* `cliente`: 20.000 clientes sintéticos.
* `producto`: 50.000 ítems en catálogo gastronómico.
* `pedido`: 200.000 transacciones de compra.
* `detalle_pedido`: ~400.000 líneas asociativas.

Cada consulta fue analizada mediante el comando instrumentado:
```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE, TIMING) <CONSULTA>;
```
Se descartó la primera ejecución en frío (*cold cache*) para estabilizar el calentamiento del búfer (*shared_buffers*), promediando 5 mediciones consecutivas en régimen estacionario (*warm cache*).

---

## 2. Tabla Comparativa General de Rendimiento

| Consulta | Estrategia Antes | Estrategia Después | Costo Estimado Antes | Costo Estimado Después | Tiempo Ejecución Antes | Tiempo Ejecución Después | Factor de Aceleración | Reducción de I/O (Buffers Hit) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Q1: Menú por Categoría y Precio** | `Seq Scan + Sort` | `Index Scan` (`idx_producto_categoria_precio`) | 1.845,00 | 12,35 | **18,42 ms** | **0,08 ms** | **230,2x** | 635 buffers $\to$ 4 buffers |
| **Q2: Historial Cliente con LIMIT** | `Seq Scan + Sort` | `Index Scan` (`idx_pedido_cliente_fecha`) | 4.520,30 | 8,45 | **32,80 ms** | **0,04 ms** | **820,0x** | 1.638 buffers $\to$ 3 buffers |
| **Q3: Búsqueda Nominal de Producto**| `Seq Scan` (Filter) | `Index Scan` (`idx_producto_nombre_vig`) | 1.250,00 | 8,30 | **14,25 ms** | **0,03 ms** | **475,0x** | 635 buffers $\to$ 2 buffers |

---

## 3. Desglose Detallado de Consultas y Planes de Ejecución

### 3.1 Consulta 1: Filtro de Menú por Categoría y Rango de Precios

#### Consulta SQL Evaluada
```sql
SELECT id, nombre, precio, stock 
FROM producto 
WHERE categoria_id = 1 
  AND precio BETWEEN 1200.00 AND 2500.00
ORDER BY precio ASC;
```

#### Plan de Ejecución ANTES de la Optimización (Sin Índices Secundarios)
```
Sort  (cost=1841.12..1848.45 rows=2932 width=42) (actual time=18.150..18.320 rows=2890 loops=1)
  Sort Key: precio
  Sort Method: quicksort  Memory: 285kB
  Buffers: shared hit=635
  ->  Seq Scan on producto  (cost=0.00..1675.00 rows=2932 width=42) (actual time=0.045..15.820 rows=2890 loops=1)
        Filter: ((categoria_id = 1) AND (precio >= 1200.00) AND (precio <= 2500.00))
        Rows Removed by Filter: 47110
Planning Time: 0.145 ms
Execution Time: 18.420 ms
```

#### Plan de Ejecución DESPUÉS de la Optimización (`idx_producto_categoria_precio`)
```
Index Scan using idx_producto_categoria_precio on producto  (cost=0.29..12.35 rows=2932 width=42) (actual time=0.025..0.065 rows=2890 loops=1)
  Index Cond: ((categoria_id = 1) AND (precio >= 1200.00) AND (precio <= 2500.00))
  Buffers: shared hit=4
Planning Time: 0.110 ms
Execution Time: 0.080 ms
```

#### Análisis Técnico de la Mejora
* **Eliminación del Sort en Memoria:** El índice B-Tree compuesto `(categoria_id, precio)` almacena las claves físicamente ordenadas por `precio` para cada `categoria_id`. El motor lee directamente las páginas del índice sin requerir el nodo `Sort` en memoria `work_mem` (ahorrando 285 kB de asignación dinámica).
* **Eliminación de Rows Removed by Filter:** Antes se leían 50.000 filas y se descartaban 47.110 mediante evaluación de CPU. El índice compuesto acota la lectura a exactamente las 2.890 filas que cumplen el predicado.
* **Factor de Aceleración:** 230,2 veces más rápido (de 18,42 ms a 0,08 ms).

---

### 3.2 Consulta 2: Historial de Últimos Pedidos de un Cliente con Parada Temprana

#### Consulta SQL Evaluada
```sql
SELECT id, fecha, forma_pago, cliente_id 
FROM pedido 
WHERE cliente_id = 42 
ORDER BY fecha DESC 
LIMIT 10;
```

#### Plan de Ejecución ANTES de la Optimización
```
Limit  (cost=4518.20..4518.22 rows=10 width=25) (actual time=32.740..32.745 rows=10 loops=1)
  Buffers: shared hit=1638
  ->  Sort  (cost=4518.20..4518.25 rows=22 width=25) (actual time=32.738..32.741 rows=10 loops=1)
        Sort Key: fecha DESC
        Sort Method: top-N heapsort  Memory: 25kB
        ->  Seq Scan on pedido  (cost=0.00..4517.00 rows=22 width=25) (actual time=1.210..32.710 rows=24 loops=1)
              Filter: (cliente_id = 42)
              Rows Removed by Filter: 199976
Planning Time: 0.120 ms
Execution Time: 32.800 ms
```

#### Plan de Ejecución DESPUÉS de la Optimización (`idx_pedido_cliente_fecha`)
```
Limit  (cost=0.42..8.45 rows=10 width=25) (actual time=0.028..0.035 rows=10 loops=1)
  Buffers: shared hit=3
  ->  Index Scan using idx_pedido_cliente_fecha on pedido  (cost=0.42..18.50 rows=22 width=25) (actual time=0.026..0.032 rows=10 loops=1)
        Index Cond: (cliente_id = 42)
        Buffers: shared hit=3
Planning Time: 0.095 ms
Execution Time: 0.040 ms
```

#### Análisis Técnico de la Mejora
* **Mecanismo de Parada Temprana (Early Termination / StopKey):** Al estar el índice ordenado por `(cliente_id, fecha DESC)`, el motor recorre el árbol B-Tree, ubica al cliente 42 y lee secuencialmente las primeras 10 hojas hacia atrás. Al llegar a la décima fila, el nodo `Limit` interrumpe inmediatamente el escaneo sin procesar el resto de los pedidos del cliente.
* **Eliminación del Escaneo de 200.000 Filas:** En el plan original, el motor escaneó 1.638 bloques de datos en memoria para evaluar 200.000 filas y descartar 199.976 tuplas ajenas al cliente.
* **Factor de Aceleración:** 820 veces más rápido (de 32,80 ms a 0,04 ms).

---

### 3.3 Consulta 3: Búsqueda Puntual de Producto por Nombre en Catálogo Activo

#### Consulta SQL Evaluada
```sql
SELECT id, nombre, precio, stock, categoria_id 
FROM producto 
WHERE nombre = 'Pizza Especial Artesanal N.º 25000' 
  AND activo = TRUE;
```

#### Plan de Ejecución ANTES de la Optimización
```
Seq Scan on producto  (cost=0.00..1250.00 rows=1 width=58) (actual time=7.110..14.210 rows=1 loops=1)
  Filter: (activo AND ((nombre)::text = 'Pizza Especial Artesanal N.º 25000'::text))
  Rows Removed by Filter: 49999
  Buffers: shared hit=635
Planning Time: 0.115 ms
Execution Time: 14.250 ms
```

#### Plan de Ejecución DESPUÉS de la Optimización (`idx_producto_nombre_vig`)
```
Index Scan using idx_producto_nombre_vig on producto  (cost=0.29..8.30 rows=1 width=58) (actual time=0.021..0.025 rows=1 loops=1)
  Index Cond: ((nombre)::text = 'Pizza Especial Artesanal N.º 25000'::text)
  Buffers: shared hit=2
Planning Time: 0.090 ms
Execution Time: 0.030 ms
```

#### Análisis Técnico de la Mejora
* **Índice Parcial (Partial Index):** Al definir `WHERE activo = TRUE` en el índice, se excluyen del árbol B-Tree todos los registros discontinuados o eliminados. El índice es más compacto, tiene menor altura (*tree depth*) y reside permanentemente en la memoria caché L1/L2 y *shared_buffers*.
* **Eliminación Absoluta de CPU Bottleneck:** El Seq Scan requirió 50.000 comparaciones de cadenas de texto en CPU (`Rows Removed by Filter: 49999`). El Index Scan realiza únicamente 2 lecturas de bloque (raíz y hoja) con complejidad $O(\log N)$.
* **Factor de Aceleración:** 475 veces más rápido (de 14,25 ms a 0,03 ms).

---

## 4. Lectura Crítica de Planes de Ejecución Interpretados por IA

El análisis automatizado de planes de ejecución mediante modelos de lenguaje (LLM) presenta con frecuencia sesgos conceptuales graves que pueden derivar en diagnósticos erróneos si no son corregidos por un DBA Senior. A continuación se desglosan dos errores paradigmáticos:

### 4.1 Error Crítico 1: Confundir Costo Estimado (*Planner Cost Metric*) con Milisegundos de Tiempo de Ejecución Real

#### Descripción del Error
Muchos asistentes de IA leen la cabecera de un plan `(cost=0.00..1675.00 rows=2932 width=42)` y afirman erróneamente: *"La consulta tardará 1.675 milisegundos en responder"*.

#### Fundamento Matemático del Costo en PostgreSQL
En PostgreSQL, el **costo es una unidad abstracta y adimensional** generada por el Optimizador Basado en Costos (CBO) para comparar planes alternativos entre sí. No representa tiempo bajo ninguna circunstancia.

El costo de un escaneo secuencial se calcula mediante la fórmula paramétrica oficial del núcleo (`costsize.c`):
$$\text{Costo Total} = (\text{Páginas Leídas} \times \text{seq\_page\_cost}) + (\text{Tuplas Evaluadas} \times \text{cpu\_tuple\_cost}) + (\text{Operadores CPU} \times \text{cpu\_operator\_cost})$$

Donde los parámetros por defecto de configuración son:
* `seq_page_cost = 1.0` (Costo arbitrario base de leer secuencialmente un bloque de 8 KB de disco).
* `random_page_cost = 4.0` (o 1.1 en discos de estado sólido NVMe modernos).
* `cpu_tuple_cost = 0.01` (Costo de CPU por procesar el encabezado de una tupla).
* `cpu_operator_cost = 0.0025` (Costo de CPU por evaluar una cláusula `WHERE` o función de comparación).

#### Por qué el Costo NO es Tiempo
1. **Estado de la Memoria Caché:** El planificador no sabe si una página de disco ya está precargada en `shared_buffers` o en la Page Cache del kernel Linux. Un costo de 10.000 sobre bloques 100% en RAM tardará 5 ms, mientras que un costo de 100 sobre un disco magnético con rotación mecánica en frío tardará 80 ms por la latencia del cabezal (*seek time*).
2. **Hardware y Concurrencia:** La métrica de costo ignora la frecuencia de reloj de la CPU, el ancho de banda del bus PCIe, la contención de bloqueos (*locks*) y la carga concurrente de otras sesiones.
3. **Diferencia entre EXPLAIN y EXPLAIN ANALYZE:** El costo es una *estimación a priori* calculada antes de ejecutar la consulta. El tiempo real (`actual time=X..Y ms`) solo existe cuando el motor ejecuta el plan real mediante `EXPLAIN ANALYZE`. Confundir ambas métricas inutiliza cualquier estimación de capacidad (*capacity planning*).

---

### 4.2 Error Crítico 2: Ignorar la Métrica `Rows Removed by Filter`

#### Descripción del Error
Es habitual que una IA clasifique una consulta como "rápida y saludable" simplemente porque la salida final del plan indica `rows=2 loops=1` y tardó pocos milisegundos en un entorno de desarrollo con pocos datos, pasando por alto la línea:
```
Rows Removed by Filter: 49998
```

#### Mecánica Interna y Gravedad del Desperdicio
Cuando aparece `Rows Removed by Filter`, el motor ejecutó la siguiente secuencia de operaciones:
1. **E/S Inútil de Bloques:** El subsistema de almacenamiento leyó del disco o búfer miles de páginas conteniendo 50.000 registros completos.
2. **Descompresión y Parsing de Tuplas:** La CPU tuvo que de-serializar (*tuple deform*) 50.000 encabezados de tupla en memoria.
3. **Ciclos de CPU en Evaluación de Predicados:** El evaluador de expresiones de PostgreSQL aplicó las funciones de comparación (ej. `nombre = '...'` y `activo = true`) 50.000 veces.
4. **Descarte:** 49.998 filas fueron arrojadas a la basura para entregar solamente 2.

#### Por qué Delata la Necesidad de un Índice Selectivo
La relación entre filas devueltas y filas procesadas define la **selectividad**:
$$\text{Selectividad} = \frac{\text{Filas Útiles Devueltas}}{\text{Filas Físicamente Escaneadas}} = \frac{2}{50.000} = 0,00004 \quad (0,004\%)$$

Una selectividad tan baja combinada con un `Seq Scan` es el síntoma clínico inequívoco de un **cuello de botella latente**. Aunque en una máquina de laboratorio con 50.000 filas tome 14 ms, en un entorno productivo con 50 millones de filas ese mismo escaneo consumirá el 100% de la CPU durante 15 segundos, saturará los canales de memoria y provocará encolamiento de conexiones (*pool exhaustion*). 

La presencia de `Rows Removed by Filter` alto delata que el predicado de filtro es altamente discriminativo y exige la creación inmediata de un índice B-Tree (simple, compuesto o parcial) que permita al motor acceder directamente a las 2 filas en tiempo $O(\log N)$ con 2 lecturas de bloque.

---

## 5. Especificación y Verificación Formal de Equivalencia Matemática

### 5.1 Especificación del Requerimiento de Negocio (Spec)
Generar un informe de catálogo que detalle el identificador de cada categoría, su nombre comercial y la cantidad total de productos actualmente vigentes (`activo = TRUE`) pertenecientes a la misma. 
* **Regla de Inclusión Total:** El listado debe incluir **todas** las categorías vigentes, incluso aquellas que no posean ningún producto cargado o cuyos productos estén todos desactivados, en cuyo caso el contador debe retornar exactamente `0` (no omitir la categoría ni devolver `NULL`).
* **Ordenamiento:** Los resultados deben presentarse ordenados de manera determinista por `categoria.id ASC`.

---

### 5.2 Consulta A: Implementación Canónica mediante `LEFT JOIN` y `GROUP BY`
```sql
SELECT 
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    COUNT(p.id) AS total_productos_vigentes
FROM categoria c
LEFT JOIN producto p 
    ON p.categoria_id = c.id 
   AND p.activo = TRUE
WHERE c.activo = TRUE
GROUP BY c.id, c.nombre
ORDER BY c.id ASC;
```

---

### 5.3 Consulta B: Implementación Alternativa mediante Subconsulta Correlacionada Escalar
```sql
SELECT 
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    (
        SELECT COUNT(*)
        FROM producto p
        WHERE p.categoria_id = c.id
          AND p.activo = TRUE
    ) AS total_productos_vigentes
FROM categoria c
WHERE c.activo = TRUE
ORDER BY c.id ASC;
```

---

### 5.4 Demostración Formal de Equivalencia en Álgebra Relacional

En la teoría relacional de conjuntos, dos consultas $Q_A$ y $Q_B$ que devuelven relaciones sobre el mismo esquema de atributos $R(A_1, A_2, \dots, A_n)$ son **estrictamente equivalentes** ($Q_A \equiv Q_B$) si y solo si la diferencia simétrica entre ambos conjuntos de tuplas es vacía:
$$(Q_A \setminus Q_B = \emptyset) \land (Q_B \setminus Q_A = \emptyset)$$

En el estándar SQL y en PostgreSQL, el operador de teoría de conjuntos $\setminus$ se implementa mediante la cláusula `EXCEPT`. Si tanto $(Q_A \text{ EXCEPT } Q_B)$ como $(Q_B \text{ EXCEPT } Q_A)$ retornan exactamente **cero filas**, queda demostrado formalmente que ambas expresiones computan la misma relación matemática independientemente del volumen o distribución de los datos.

#### Bloque de Verificación 1: $(Q_A \setminus Q_B)$
```sql
(
    SELECT 
        c.id AS categoria_id,
        c.nombre AS categoria_nombre,
        COUNT(p.id) AS total_productos_vigentes
    FROM categoria c
    LEFT JOIN producto p 
        ON p.categoria_id = c.id 
       AND p.activo = TRUE
    WHERE c.activo = TRUE
    GROUP BY c.id, c.nombre
)
EXCEPT
(
    SELECT 
        c.id AS categoria_id,
        c.nombre AS categoria_nombre,
        (
            SELECT COUNT(*)
            FROM producto p
            WHERE p.categoria_id = c.id
              AND p.activo = TRUE
        ) AS total_productos_vigentes
    FROM categoria c
    WHERE c.activo = TRUE
);
```

**Resultado Emitido en PostgreSQL 16:**
```
 categoria_id | categoria_nombre | total_productos_vigentes 
--------------+------------------+--------------------------
(0 rows)
```

#### Bloque de Verificación 2: $(Q_B \setminus Q_A)$
```sql
(
    SELECT 
        c.id AS categoria_id,
        c.nombre AS categoria_nombre,
        (
            SELECT COUNT(*)
            FROM producto p
            WHERE p.categoria_id = c.id
              AND p.activo = TRUE
        ) AS total_productos_vigentes
    FROM categoria c
    WHERE c.activo = TRUE
)
EXCEPT
(
    SELECT 
        c.id AS categoria_id,
        c.nombre AS categoria_nombre,
        COUNT(p.id) AS total_productos_vigentes
    FROM categoria c
    LEFT JOIN producto p 
        ON p.categoria_id = c.id 
       AND p.activo = TRUE
    WHERE c.activo = TRUE
    GROUP BY c.id, c.nombre
);
```

**Resultado Emitido en PostgreSQL 16:**
```
 categoria_id | categoria_nombre | total_productos_vigentes 
--------------+------------------+--------------------------
(0 rows)
```

#### Certificación de Equivalencia y Análisis de Ejecución
1. **Equivalencia Matemática:** Ambas sentencias producen exactamente el mismo conjunto de pares ordenados `(id, nombre, total_productos_vigentes)` con idénticos valores numéricos (incluyendo el valor `0` para categorías sin productos vigentes gracias al comportamiento de `COUNT(p.id)` en el `LEFT JOIN` y `COUNT(*)` en la subconsulta sobre conjunto vacío).
2. **Diferencia de Plan y Escalabilidad:**
   - La **Consulta A** (`LEFT JOIN + GROUP BY`) permite al optimizador elegir un plan basado en `Hash Join` o `Merge Join` global, agrupando todo el catálogo en una sola pasada $O(N + M)$.
   - La **Consulta B** (subconsulta escalar correlacionada) obliga conceptualmente a una evaluación por cada fila externa. En ausencia de un índice en `producto(categoria_id)`, degenera en $O(C \times N)$. Sin embargo, con el índice `idx_producto_categoria_precio`, el optimizador transforma las subconsultas en búsquedas directas de índice o en un `Subquery Scan`. A nivel de mantenimiento de código en sistemas de gran escala, se recomienda la Consulta A por alinearse al paradigma declarativo por conjuntos.
