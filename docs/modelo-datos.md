# Modelo de datos

Entregable 2 de la entrega intermedia. La fuente de verdad del item es la [ARCHITECTURE §7 del backend](https://github.com/Pardosito/oncall-training-backend/blob/main/docs/ARCHITECTURE.md#7-data); la tabla la crea este repo en `terraform/foundation` ([ARCHITECTURE §3](ARCHITECTURE.md#3-foundation-resources-terraformfoundation)).

## Por qué DynamoDB y no RDS

| | DynamoDB (elegido) | RDS |
|---|---|---|
| Patrones de acceso | Todos se conocen de antemano y son por llave: una sesión, las sesiones de un usuario, el ranking de un escenario | Útil si hubiera joins o consultas ad hoc; aquí no las hay |
| Escrituras concurrentes | Cada transición de estado es un `UpdateItem` condicional (`#state = :expected`), así que mensajes duplicados o tardíos no regresan una sesión | Requiere transacciones o locks a mano |
| Costo en Learner Lab | On-demand: centavos al día y nada encendido cuando no se usa | Una instancia cobra por hora aunque nadie la use |
| Operación | Sin servidor, sin VPC, sin parches; los pods lo usan con LabRole | Subredes privadas, security groups, credenciales que guardar |
| Analítica | Las estadísticas se calculan con un `Query` por usuario; Athena quedó fuera porque el rol del lab no puede usarlo (D-37) | Habría que hacer reportes sobre la base transaccional |

**Desventaja aceptada:** no hay consultas flexibles. Cada consulta nueva necesita su llave o un GSI. En la entrega intermedia había una excepción temporal, un `Scan` filtrado para saber si ya había una sesión activa; ahora lo reemplaza un lock en Redis (ElastiCache).

## Tabla `Sessions`

On-demand, PITR activado, protección contra borrado.

| Llave | Atributo | Tipo |
|---|---|---|
| **PK** (partition) | `user_id` | S: id del usuario (Cognito `sub`; en la entrega intermedia, el header `x-dev-user`) |
| **SK** (sort) | `session_id` | S: ULID, así que ordenar por SK = ordenar por fecha |

### Atributos

| Atributo | Tipo | Lo escribe | Notas |
|---|---|---|---|
| `username` | S | api | para el ranking |
| `scenario_id` | S | api | p. ej. `orders-down` |
| `state` | S | api / injector / worker | `STARTING` → `INCIDENT_ACTIVE` → `RESOLVED` o `FAILED` |
| `created_at`, `updated_at` | S | api / todos | ISO-8601 UTC |
| `fault_injected_at` | S | injector | cuando la falla ya se aplicó en EKS |
| `acknowledged_at` | S | worker | primer `ACKNOWLEDGE` del usuario |
| `valid_fix_applied_at` | S | worker | primera acción que corrige la falla |
| `wrong_actions`, `actions_count` | N | worker | `ADD` atómico |
| `score`, `ttd_seconds`, `ttr_seconds` | N | worker (intermedia) / Step Functions (final) | solo si `RESOLVED` |
| `ended_at`, `failure_reason` | S | worker (intermedia) / Step Functions (final) | `TIMEOUT`, `ABANDONED`, `ERROR` |
| `execution_arn`, `task_token` | S | api / Step Functions | desplegado |

### GSI `Leaderboard`

| Llave | Atributo | Tipo |
|---|---|---|
| PK | `scenario_id` | S |
| SK | `score` | N |

Proyección `ALL`. Es un índice *sparse*: solo los items `RESOLVED` tienen `score`, así que solo esos aparecen.

### Item de ejemplo (sesión resuelta)

```json
{
  "user_id": "demo",
  "session_id": "01JBXK3Q7Z8M2N4P6R8T0V2W4Y",
  "username": "demo",
  "scenario_id": "orders-down",
  "state": "RESOLVED",
  "created_at": "2026-11-05T17:00:00.000Z",
  "fault_injected_at": "2026-11-05T17:00:20.410Z",
  "acknowledged_at": "2026-11-05T17:00:41.002Z",
  "valid_fix_applied_at": "2026-11-05T17:01:15.880Z",
  "wrong_actions": 0,
  "actions_count": 3,
  "score": 902,
  "ttd_seconds": 21,
  "ttr_seconds": 77,
  "ended_at": "2026-11-05T17:01:37.300Z",
  "updated_at": "2026-11-05T17:01:37.300Z"
}
```

## Consultas principales

| # | Consulta | Operación | Quién la usa |
|---|---|---|---|
| 1 | Una sesión de un usuario | `GetItem(user_id, session_id)` (consistente) | `GET /api/sessions/{id}`, el dashboard, el injector antes de aplicar la falla |
| 2 | Historial del usuario, más reciente primero | `Query(user_id = :u, ScanIndexForward = false)`, paginado con `LastEvaluatedKey` | `GET /api/me/sessions` (desplegado) |
| 3 | Top 10 de un escenario | `Query` sobre GSI `Leaderboard` (`scenario_id = :s`, descendente, `Limit 10`) | `GET /api/leaderboard/{scenarioId}` (desplegado) |

Leer siempre con `PK = usuario que llama` hace que la sesión de otro usuario responda **404**: nunca revelamos que existe.

## Otros datos

| Dónde | Qué | Estado |
|---|---|---|
| S3 `oncall-training-files-<acct>/scenarios/` | Definiciones de escenarios (`orders-down.json`), las sube el release del backend | desplegado |
| S3 `…/logs/year=/month=/day=/` | Un archivo NDJSON por sesión con sus eventos | desplegado |
| Glue `session_events` + Athena | Gráficas de desempeño | **descartado** (el rol del lab no puede usarlos, D-37); las gráficas leen DynamoDB |
| ElastiCache (Valkey) | Lock global, snapshots del dashboard | desplegado |

El bucket usa los prefijos `scenarios/` y `logs/`.
