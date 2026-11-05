# Ejercicio de Lectura Crítica de Scripts SQL Peligrosos

**Cátedra:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación a Distancia (UTN)  
**Proyecto:** Food Store / Sistema de Cines  
**Autor:** Joaquin Chiarello  
**Rol:** Administrador de Bases de Datos Senior (PostgreSQL 16+)

---

## 1. Análisis del Script Peligroso A

### 1.1 Código Bajo Revisión
```sql
UPDATE funcion SET activa = FALSE;
```

### 1.2 Mecánica del Error y Riesgo Catastrófico en Producción
En el estándar relacional SQL y en el motor PostgreSQL, una sentencia `UPDATE` sin cláusula `WHERE` actúa de manera indiscriminada sobre la totalidad de las filas de la relación. 

En el contexto de un sistema de gestión de salas de cine, las consecuencias de este comando en producción son inmediatas y graves:
1. **Interrupción Total de la Operación Comercial:** Desactiva de forma instantánea todas las funciones proyectadas en todas las salas del complejo para el día de hoy y para las próximas semanas.
2. **Denegación de Servicio en Puntos de Venta:** Los sistemas de boletería física, quioscos de autoservicio y la aplicación móvil de compra dejan de listar funciones disponibles, imposibilitando la venta de tickets.
3. **Pérdida de Integridad Operativa:** Funciones que contaban con espectadores con entradas ya adquiridas quedan marcadas como inactivas, obligando a procesos manuales de contingencia.
4. **Degradación Física del Motor (*Table Bloat* y Saturación de WAL):** En PostgreSQL, debido a la arquitectura MVCC, un `UPDATE` no sobrescribe el registro en el mismo bloque físico si cambian metadatos o no aplica HOT (*Heap-Only Tuples*). El motor duplica cada fila escribiendo una versión nueva en el *heap* y marcando la anterior como muerta. Actualizar una tabla completa sin discriminar genera un crecimiento desmedido en disco (*bloat*), satura la memoria del WAL (*Write-Ahead Log*) y fuerza una sobrecarga extrema en los procesos del demonio `autovacuum`.

### 1.3 Versiones Corregidas e Idiomáticas

La regla de negocio habitual exige desactivar únicamente aquellas funciones vinculadas a películas que ya fueron retiradas de cartelera (`en_cartelera = FALSE`), o aquellas cuya fecha de exhibición ya expiró.

#### Opción 1: Uso de `UPDATE ... FROM` (Sintaxis Idiomática Óptima en PostgreSQL)
```sql
-- Actualiza únicamente funciones activas de películas dadas de baja
UPDATE funcion f
SET activa = FALSE
FROM pelicula p
WHERE f.pelicula_id = p.id
  AND p.en_cartelera = FALSE
  AND f.activa = TRUE;
```

#### Opción 2: Subconsulta Correlacionada con `EXISTS` (Estándar ANSI SQL)
```sql
UPDATE funcion f
SET activa = FALSE
WHERE f.activa = TRUE
  AND EXISTS (
      SELECT 1 
      FROM pelicula p 
      WHERE p.id = f.pelicula_id 
        AND p.en_cartelera = FALSE
  );
```

### 1.4 Salvaguardas Operacionales para el DBA
1. Desactivar el autocommit en la consola interactiva mediante `\set AUTOCOMMIT off`.
2. Encapsular toda modificación masiva en bloques defensivos `BEGIN; UPDATE ...; SELECT count(*); ROLLBACK / COMMIT;`.
3. Configurar extensiones de seguridad como `safeupdate` en el cluster para que PostgreSQL aborte cualquier `UPDATE` o `DELETE` que carezca de una cláusula `WHERE` explícita.

---

## 2. Análisis del Script Peligroso B

### 2.1 Código Bajo Revisión
```sql
DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto);
```

### 2.2 La Trampa de la Lógica Trivaluada de SQL (*Three-Valued Logic - 3VL*)

El objetivo del programador es eliminar las categorías huérfanas (aquellas que no poseen ningún producto asociado). Sin embargo, este script encierra uno de los errores más sutiles y peligrosos del álgebra relacional.

En SQL, las expresiones lógicas se evalúan bajo **Three-Valued Logic (3VL)**, cuyos tres estados posibles son `TRUE`, `FALSE` y `UNKNOWN` (producido por el manejo de `NULL`).

Por definición formal del estándar SQL, el operador `NOT IN` se descompone internamente en una conjunción de comparaciones de desigualdad negadas unidas por operadores lógicos:
```sql
id NOT IN (c1, c2, ..., cn) 
≡ NOT (id = c1 OR id = c2 OR ... OR id = cn)
≡ (id <> c1 AND id <> c2 AND ... AND id <> cn)
```

Si en la tabla `producto` existe **un solo registro** donde la columna `categoria_id` contenga un valor `NULL` (por ejemplo, un producto en borrador o sin categorizar), el conjunto devuelto por la subconsulta contendrá al menos un elemento `NULL`.

Analicemos la evaluación para una categoría cualquiera (por ejemplo, `id = 5` que no tiene productos):
```
5 NOT IN (1, 2, NULL)
≡ NOT (5 = 1 OR 5 = 2 OR 5 = NULL)
≡ NOT (FALSE OR FALSE OR UNKNOWN)
≡ NOT (UNKNOWN)
≡ UNKNOWN
```

En SQL, una cláusula `WHERE` solo selecciona las tuplas para las cuales la condición evalúa estrictamente a `TRUE`. Un resultado `UNKNOWN` se descarta de la misma forma que un `FALSE`.

### 2.3 Consecuencia en Producción: El `DELETE 0` Silencioso
Debido a la presencia del valor `NULL`, la condición jamás evaluará a `TRUE` para ninguna categoría de la base de datos, sin importar si tiene productos asociados o no.

El comando finaliza con:
```
DELETE 0
```

El script no arroja ningún mensaje de error ni aborta la transacción. El desarrollador asume erróneamente que la limpieza de categorías se ejecutó correctamente cuando en realidad **no se eliminó absolutamente nada**. El sistema acumula datos inconsistentes de forma silenciosa e imperceptible.

### 2.4 Versiones Corregidas y Robustas

#### Opción 1: Refactorización con `NOT EXISTS` (Recomendación Principal)
```sql
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1 
    FROM producto p 
    WHERE p.categoria_id = c.id
);
```

* **Inmunidad frente a valores `NULL`:** El predicado `EXISTS` evalúa si el subconjunto devuelto por la subconsulta contiene al menos una fila o si está vacío. Retorna un valor estrictamente booleano de dos estados (`TRUE` o `FALSE`), nunca `UNKNOWN`. Si una fila de `producto` tiene `categoria_id IS NULL`, la condición de igualdad `p.categoria_id = c.id` evalúa a `UNKNOWN`, esa fila no califica dentro del subconjunto, y no altera el resultado de existencia.
* **Optimización en el Planificador de PostgreSQL:** El optimizador de PostgreSQL 16 transforma la estructura `NOT EXISTS` en un plan de ejecución de tipo `Hash Anti Join` o `Merge Anti Join`. Si la columna `categoria_id` cuenta con un índice B-Tree, el planificador no requiere escanear secuencialmente toda la tabla `producto`, reduciendo el costo de I/O en órdenes de magnitud.

#### Opción 2: `NOT IN` con Filtrado Explícito de `NULL`
```sql
DELETE FROM categoria 
WHERE id NOT IN (
    SELECT categoria_id 
    FROM producto 
    WHERE categoria_id IS NOT NULL
);
```
Esta variante soluciona la trampa de 3VL al eliminar los valores nulos antes de evaluar la pertenencia. Sin embargo, en bases de datos con millones de filas, `NOT EXISTS` suele generar planes de ejecución más eficientes y es la forma canónica recomendada por las guías de ingeniería de PostgreSQL.
